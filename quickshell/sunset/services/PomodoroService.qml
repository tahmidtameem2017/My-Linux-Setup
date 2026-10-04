pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io

// PomodoroService.qml — pomodoro + countdown timing engine (singleton).
//
// Extracted from components/CalendarPopup.qml engine (server parity with
// legacy waybar/clock/timer-server.py — same state file, same JSON shape).
// The engine runs here so Bar widgets can bind to live state and
// phase/timer expiry can fire sticky notifications with the popup closed.
//
// State file: $NIRI_CLOCK_DIR/state.json (default
// ~/.cache/niri-clock/state.json):
//   {pomo:{phase,round,remain,running,last},
//    timer:{remain,running,last,minutes,seconds,finished},
//    alarm:{hour,min,enabled,repeat,lastFire},
//    cfg:{focus,short,long,rounds}} plus the active tab (tab lives in the
// popup, not here). Old state.json files are picked up and caught up by
// wall-clock, so in-flight timers survive restarts.
//
// Notifications (user choice: ALL timers, STICKY critical so expiry is
// never missed): phase transitions + countdown expiry send
// `notify-send -a Pomodoro -u critical` which loops back through the
// owned org.freedesktop.Notifications server (Toasts.qml) into a sticky
// toast + history. Audio beep (pw-play||paplay||aplay, reusing
// ~/.cache/niri-clock/beep.wav when present) is kept alongside.
// DND semantics: Toasts.silent hides toasts but history is preserved;
// beep bypasses DND (existing behavior).
Singleton {
    id: root

    // ---- pomodoro state ----
    property string pomoPhase: "focus" // focus | short | long
    property int pomoRound: 1
    property real pomoRemain: 25 * 60
    property bool pomoRunning: false
    property double pomoLast: 0
    property int cfgFocus: 25
    property int cfgShort: 5
    property int cfgLong: 15
    property int cfgRounds: 4

    // ---- countdown state ----
    property real timerRemain: 5 * 60
    property bool timerRunning: false
    property double timerLast: 0
    property int timerMin: 5
    property int timerSec: 0
    property bool timerFinished: false

    // ---- session latches (runtime only, drive bar pill visibility) ----
    // True once started, false on reset. Persisted implicitly: applyState
    // re-derives from remain-vs-full so a pause survives restarts.
    property bool pomoActive: false
    property bool timerActive: false

    // ---- alarm state (single wall-clock alarm, HH:MM) ----
    property int alarmHour: 7
    property int alarmMin: 0
    property bool alarmEnabled: false
    property bool alarmRepeat: true // daily repeat; one-shot when false (auto-disables after firing)
    property string alarmLastFire: "" // YYYY-MM-DD of last fire (prevents refire; defers past-time sets to tomorrow)

    // Bar pill visibility: hide when idle (nothing started/finished/armed).
    // Finished countdown stays visible until reset/new start (sticky);
    // an armed alarm stays visible until cleared/disabled (one-shot) or toggled off.
    readonly property bool pillVisible: root.pomoActive || root.timerActive || root.alarmEnabled

    // Which clock the pill shows. Pomo wins when it runs or when the
    // timer is idle; a running/finished timer wins over a paused pomo;
    // an armed alarm shows only when neither pomo nor timer is active.
    readonly property bool showTimer: (root.timerRunning || root.timerFinished) && !root.pomoRunning
    readonly property bool showAlarm: root.alarmEnabled && !root.pomoActive && !root.timerActive
    readonly property bool pillPaused: root.pillVisible && !root.pomoRunning && !root.timerRunning && !root.timerFinished && !root.showAlarm

    // Emitted where playBeep() now sits (one per transition batch).
    signal pomoAdvanced(string newPhase, int round)
    signal timerExpired()
    signal alarmFired(string timeStr)

    // ---- paths (server parity) ----
    readonly property string clockDir: Quickshell.env("NIRI_CLOCK_DIR") ?? (Quickshell.env("HOME") + "/.cache/niri-clock")
    readonly property string statePath: clockDir + "/state.json"

    property double lastSave: 0
    property bool saving: false

    function clampInt(v: int, lo: int, hi: int): int {
        if (isNaN(v))
            return lo;
        return Math.max(lo, Math.min(hi, v));
    }
    function pomoDur(phase: string): real {
        if (phase === "focus")
            return clampInt(cfgFocus, 1, 180) * 60.0;
        if (phase === "short")
            return clampInt(cfgShort, 1, 60) * 60.0;
        return clampInt(cfgLong, 1, 60) * 60.0;
    }
    function pomoAdvance(): void {
        if (pomoPhase === "focus") {
            pomoPhase = (pomoRound >= clampInt(cfgRounds, 1, 12)) ? "long" : "short";
        } else {
            if (pomoPhase === "short")
                pomoRound += 1;
            else
                pomoRound = 1;
            pomoPhase = "focus";
        }
        pomoRemain = pomoDur(pomoPhase);
    }
    function pomoPhaseName(phase: string): string {
        if (phase === "short")
            return "Short break";
        if (phase === "long")
            return "Long break";
        return "Focus";
    }
    function pomoPhaseMinutes(phase: string): int {
        if (phase === "focus")
            return clampInt(cfgFocus, 1, 180);
        if (phase === "short")
            return clampInt(cfgShort, 1, 60);
        return clampInt(cfgLong, 1, 60);
    }

    // Sticky critical toast via notify-send (loops back through Toasts'
    // NotificationServer into a sticky toast + history[20]).
    function notify(summary: string, body: string): void {
        Quickshell.execDetached(["notify-send", "-a", "Pomodoro", "-u", "critical", "-t", "0", summary, body]);
    }
    function notifyPomoPhase(): void {
        const rounds = clampInt(cfgRounds, 1, 12);
        const roundTxt = "Round " + Math.min(pomoRound, rounds) + "/" + rounds;
        if (pomoPhase === "focus")
            notify("Focus time — " + roundTxt, pomoPhaseName("focus") + " " + pomoPhaseMinutes("focus") + "m started");
        else
            notify("Focus finished — " + roundTxt, pomoPhaseName(pomoPhase) + " " + pomoPhaseMinutes(pomoPhase) + "m started");
        pomoAdvanced(pomoPhase, pomoRound);
    }
    function notifyTimerDone(): void {
        notify("Countdown finished", "Timer done — " + fmt(timerMin * 60 + timerSec));
        timerExpired();
    }
    function notifyAlarm(): void {
        notify("Alarm — " + alarmTimeStr(), alarmRepeat ? "Daily alarm ringing" : "One-shot alarm ringing");
        alarmFired(alarmTimeStr());
    }

    // ---- alarm helpers ----
    function alarmTimeStr(): string {
        const h = clampInt(alarmHour, 0, 23);
        const m = clampInt(alarmMin, 0, 59);
        return (h < 10 ? "0" : "") + h + ":" + (m < 10 ? "0" : "") + m;
    }
    function alarmDayStr(d: var): string {
        return d.getFullYear() + "-" + (d.getMonth() + 1) + "-" + d.getDate();
    }
    function nextAlarmDate(now: var): var {
        const t = new Date(now.getTime());
        t.setHours(clampInt(alarmHour, 0, 23), clampInt(alarmMin, 0, 59), 0, 0);
        if (t.getTime() <= now.getTime())
            t.setDate(t.getDate() + 1);
        return t;
    }
    function alarmStatus(): string {
        if (!alarmEnabled)
            return "Off";
        const now = new Date();
        const next = nextAlarmDate(now);
        let mins = Math.max(1, Math.round((next.getTime() - now.getTime()) / 60000));
        const h = Math.floor(mins / 60);
        const m = mins % 60;
        const when = (next.getDate() !== now.getDate()) ? ("tomorrow at " + alarmTimeStr()) : ("today at " + alarmTimeStr());
        const inTxt = h > 0 ? ("in " + h + "h " + m + "m") : ("in " + m + "m");
        return "Rings " + when + " (" + inTxt + ")" + (alarmRepeat ? " · daily" : " · once");
    }
    function alarmSet(h: int, m: int, repeat: var): void {
        alarmHour = clampInt(h, 0, 23);
        alarmMin = clampInt(m, 0, 59);
        if (repeat === true || repeat === false)
            alarmRepeat = repeat;
        alarmEnabled = true;
        // A set for a time already past today means tomorrow: mark today
        // done so checkAlarm doesn't fire immediately on the stale target.
        const now = new Date();
        const t = new Date(now.getTime());
        t.setHours(alarmHour, alarmMin, 0, 0);
        if (t.getTime() <= now.getTime())
            alarmLastFire = alarmDayStr(now);
        saveState();
    }
    function alarmEnable(): void {
        alarmEnabled = true;
        const now = new Date();
        const t = new Date(now.getTime());
        t.setHours(clampInt(alarmHour, 0, 23), clampInt(alarmMin, 0, 59), 0, 0);
        if (t.getTime() <= now.getTime() && alarmLastFire !== alarmDayStr(now))
            alarmLastFire = alarmDayStr(now);
        saveState();
    }
    function alarmDisable(): void {
        alarmEnabled = false;
        saveState();
    }
    function alarmToggle(): void {
        if (alarmEnabled)
            alarmDisable();
        else
            alarmEnable();
    }
    function alarmClear(): void {
        alarmEnabled = false;
        saveState();
    }
    function checkAlarm(nowSec: double): void {
        if (!alarmEnabled)
            return;
        const now = new Date(nowSec * 1000);
        const today = alarmDayStr(now);
        if (alarmLastFire === today)
            return;
        const t = new Date(now.getTime());
        t.setHours(clampInt(alarmHour, 0, 23), clampInt(alarmMin, 0, 59), 0, 0);
        if (now.getTime() >= t.getTime()) {
            alarmLastFire = today;
            playBeep();
            notifyAlarm();
            if (!alarmRepeat)
                alarmEnabled = false;
            saveState();
        }
    }

    function playBeep(): void {
        // Detached per beep (server parity: overlapping Popen players).
        Quickshell.execDetached(["bash", "-c", root.beepCmd]);
    }

    // Kawaii music-box chime (C6-E6-G6-C7, soft decay, -6dB). Reuses
    // the old server's beep.wav when present, else a freedesktop
    // fallback; player chain mirrors timer-server.py (pw-play/paplay/aplay).
    readonly property string beepCmd: "f=\"$HOME/.cache/niri-clock/beep.wav\"; if [ ! -f \"$f\" ]; then f=\"/usr/share/sounds/freedesktop/stereo/complete.oga\"; fi; pw-play \"$f\" 2>/dev/null || paplay \"$f\" 2>/dev/null || aplay -q \"$f\" 2>/dev/null"

    function catchUp(nowSec: double): void {
        if (pomoRunning) {
            pomoRemain -= (nowSec - pomoLast);
            let guard = 0;
            let transitioned = false;
            while (pomoRemain <= 0 && guard < 1000) {
                guard += 1;
                playBeep();
                const overflow = -pomoRemain;
                pomoAdvance();
                pomoRemain -= overflow;
                transitioned = true;
            }
            // One sticky toast for the final phase (avoids spam when the
            // shell was away across several phases; beep kept per phase).
            if (transitioned)
                notifyPomoPhase();
        }
        pomoLast = nowSec;
        if (timerRunning) {
            timerRemain -= (nowSec - timerLast);
            if (timerRemain <= 0) {
                timerRemain = 0;
                timerRunning = false;
                timerFinished = true;
                playBeep();
                notifyTimerDone();
            }
        }
        timerLast = nowSec;
        checkAlarm(nowSec);
    }
    function poll(): void {
        const now = Date.now() / 1000;
        if (pomoLast === 0)
            pomoLast = now;
        if (timerLast === 0)
            timerLast = now;
        // Decrement live so bindings repaint without any polling view.
        catchUp(now);
        if ((pomoRunning || timerRunning || alarmEnabled) && now - lastSave > 5)
            saveState();
    }
    function pomoCmd(cmd: string): void {
        catchUp(Date.now() / 1000);
        if (cmd === "start") {
            if (pomoRemain <= 0)
                pomoRemain = pomoDur(pomoPhase);
            pomoRunning = true;
            pomoActive = true;
        } else if (cmd === "pause") {
            pomoRunning = false;
        } else if (cmd === "reset") {
            pomoPhase = "focus";
            pomoRound = 1;
            pomoRemain = pomoDur("focus");
            pomoRunning = false;
            pomoActive = false;
        } else if (cmd === "skip") {
            pomoAdvance();
            pomoActive = true;
            pomoLast = Date.now() / 1000;
            notifyPomoPhase();
        }
        saveState();
    }
    function applyCfg(focus: int, short: int, long: int, rounds: int): void {
        cfgFocus = clampInt(focus, 1, 180);
        cfgShort = clampInt(short, 1, 60);
        cfgLong = clampInt(long, 1, 60);
        cfgRounds = clampInt(rounds, 1, 12);
        saveState();
    }
    function timerStart(seconds: int): void {
        catchUp(Date.now() / 1000);
        if (seconds > 0) {
            // Explicit fresh start from the given inputs.
            timerRemain = Math.min(359999, seconds);
            timerMin = Math.floor(timerRemain / 60);
            timerSec = Math.floor(timerRemain % 60);
        } else if (!(timerRemain > 0)) {
            return; // resume requested with nothing left: ignore.
        }
        timerRunning = true;
        timerFinished = false;
        timerActive = true;
        saveState();
    }
    function timerPause(): void {
        catchUp(Date.now() / 1000);
        timerRunning = false;
        saveState();
    }
    function timerReset(seconds: int): void {
        timerRemain = Math.max(0, Math.min(359999, seconds));
        timerMin = Math.floor(timerRemain / 60);
        timerSec = Math.floor(timerRemain % 60);
        timerRunning = false;
        timerFinished = false;
        timerActive = false;
        timerLast = Date.now() / 1000;
        saveState();
    }
    function fmt(s: real): string {
        s = Math.max(0, Math.ceil(s));
        const m = Math.floor(s / 60);
        const r = Math.floor(s % 60);
        return (m < 10 ? "0" : "") + m + ":" + (r < 10 ? "0" : "") + r;
    }
    function pomoLabel(): string {
        const name = pomoPhase === "focus" ? "FOCUS" : (pomoPhase === "short" ? "SHORT BREAK" : "LONG BREAK");
        const rounds = clampInt(cfgRounds, 1, 12);
        return name + " · ROUND " + Math.min(pomoRound, rounds) + "/" + rounds;
    }
    // Compact bar text. Pomo: "🍅 24:59 · FOCUS 2/4" (⏸ when paused,
    // timer: "⏱ 04:59" / "⏱ 00:00 DONE" when finished,
    // alarm (armed, nothing else active): "⏰ 07:00".
    function pillText(): string {
        if (showTimer) {
            if (timerFinished)
                return "⏱ " + fmt(timerRemain) + " DONE";
            return (timerRunning ? "⏱ " : "⏸ ") + fmt(timerRemain);
        }
        if (pomoActive) {
            const rounds = clampInt(cfgRounds, 1, 12);
            const name = pomoPhase === "focus" ? "FOCUS" : (pomoPhase === "short" ? "BREAK" : "LONG");
            return (pomoRunning ? "🍅 " : "⏸ ") + fmt(pomoRemain) + " · " + name + " " + Math.min(pomoRound, rounds) + "/" + rounds;
        }
        if (alarmEnabled)
            return "⏰ " + alarmTimeStr();
        return "⏰ " + alarmTimeStr();
    }
    function snapshot(): string {
        return JSON.stringify({
            "pomo": {
                "phase": pomoPhase,
                "round": pomoRound,
                "remain": pomoRemain,
                "running": pomoRunning,
                "last": pomoLast
            },
            "timer": {
                "remain": timerRemain,
                "running": timerRunning,
                "last": timerLast,
                "minutes": timerMin,
                "seconds": timerSec,
                "finished": timerFinished
            },
            "alarm": {
                "hour": alarmHour,
                "minutes": alarmMin,
                "enabled": alarmEnabled,
                "repeat": alarmRepeat,
                "lastFire": alarmLastFire
            },
            "cfg": {
                "focus": cfgFocus,
                "short": cfgShort,
                "long": cfgLong,
                "rounds": cfgRounds
            }
        });
    }
    function applyState(obj: var): void {
        try {
            if (obj.pomo) {
                const p = obj.pomo;
                if (p.phase === "focus" || p.phase === "short" || p.phase === "long")
                    pomoPhase = p.phase;
                pomoRound = clampInt(parseInt(p.round), 1, 12);
                pomoRemain = Math.max(0, Number(p.remain) || 0);
                pomoRunning = !!p.running;
                pomoLast = Number(p.last) || 0;
            }
            if (obj.timer) {
                const t = obj.timer;
                timerRemain = Math.max(0, Math.min(359999, Number(t.remain) || 0));
                timerRunning = !!t.running;
                timerLast = Number(t.last) || 0;
                timerMin = clampInt(parseInt(t.minutes), 0, 5999);
                timerSec = clampInt(parseInt(t.seconds), 0, 59);
                timerFinished = !!t.finished;
            }
            if (obj.alarm) {
                const a = obj.alarm;
                alarmHour = clampInt(parseInt(a.hour), 0, 23);
                alarmMin = clampInt(parseInt(a.minutes ?? a.min), 0, 59);
                alarmEnabled = !!a.enabled;
                alarmRepeat = a.repeat !== false;
                alarmLastFire = (typeof a.lastFire === "string") ? a.lastFire : "";
            }
            if (obj.cfg) {
                const c = obj.cfg;
                cfgFocus = clampInt(parseInt(c.focus), 1, 180);
                cfgShort = clampInt(parseInt(c.short), 1, 60);
                cfgLong = clampInt(parseInt(c.long), 1, 60);
                cfgRounds = clampInt(parseInt(c.rounds), 1, 12);
            }
        } catch (e) {
            console.warn("sunset/PomodoroService: ignoring corrupt state.json");
        }
        // Re-derive session latches so a paused session survives restarts.
        pomoActive = pomoRunning || (pomoRemain < pomoDur(pomoPhase) - 0.5);
        timerActive = timerRunning || timerFinished;
        // Catch up on time that passed while the shell was away.
        const now = Date.now() / 1000;
        if (pomoLast === 0)
            pomoLast = now;
        if (timerLast === 0)
            timerLast = now;
        catchUp(now);
    }
    function saveState(): void {
        lastSave = Date.now() / 1000;
        saving = true;
        stateFile.setText(snapshot());
    }

    Process {
        id: mkdirProc
        command: ["mkdir", "-p", root.clockDir]
        running: false
        onExited: {
            // Load once the directory exists (setText needs it too).
            if (!stateFile.loaded)
                stateFile.reload();
        }
    }

    FileView {
        id: stateFile
        path: root.statePath
        blockLoading: true
        watchChanges: true
        onLoaded: {
            if (root.saving)
                return;
            try {
                root.applyState(JSON.parse(text()));
            } catch (e) {
                console.warn("sunset/PomodoroService: state.json unparsable, keeping defaults");
            }
        }
        onLoadFailed: {
            // First run (or deleted cache): persist defaults.
            const now = Date.now() / 1000;
            root.pomoLast = now;
            root.timerLast = now;
            root.saveState();
        }
        onFileChanged: {
            if (!root.saving)
                reload();
        }
        onSaved: root.saving = false
        onSaveFailed: root.saving = false
    }

    // Engine tick runs while a timer runs OR an alarm is armed (server
    // parity). Idle (nothing started/armed): zero wakeups — pill is hidden
    // and remain values are static. Starting/resuming (pomoCmd/timerStart)
    // flips pomoRunning/timerRunning, arming (alarmSet/alarmEnable) flips
    // alarmEnabled, which restarts the tick via this binding; pausing/
    // finishing/disarming stops it again. External state.json edits still
    // apply instantly through the FileView watcher + catchUp there.
    // 1000ms: halves 500ms wake rate on weak CPUs, still 1s-accurate pill.
    Timer {
        id: tick
        interval: 1000
        running: root.pomoRunning || root.timerRunning || root.alarmEnabled
        repeat: true
        onTriggered: root.poll()
    }

    Component.onCompleted: mkdirProc.running = true
    Component.onDestruction: saveState()
}
