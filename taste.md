# taste.md — design taste for niri-setup

How things should look and feel. Match this; don't invent new styles.

## Theme: Sunset Orange AMOLED

Black backgrounds, orange accents, peach text. Warm glow on hover/active,
restraint at rest.

Sunset is the **default palette**, not the only one. The table below is what
the tokens look like when `Theme.current === "sunset"`; the same 11 token names
are what every other palette fills in. Anything that renders a colour binds the
token, never the hex, so the whole desktop moves together when the palette
changes.

| Token    | Hex       | Use                                              |
| -------- | --------- | ------------------------------------------------ |
| `--bg`   | `#000000` | page / bar background                            |
| `--panel`| `#0a0a0a` | cards, bar section containers                    |
| `--row`  | `#141010` | buttons, list rows                               |
| `--border` | `#1a1210` | faint borders, slider tracks                   |
| `--border-strong` | `#3D2B24` | card borders, button borders            |
| `--accent` | `#E85D2F` | primary actions, today/selected, active states |
| `--accent-hover` | `#FF8B4A` | hover text, highlights                  |
| `--text` | `#F7C7A1` | body text                                        |
| `--muted`| `#7C8A6A` | secondary text, hints, device names              |
| `--dim`  | `#555555` | overflow days, disabled, placeholder             |
| `--danger` | `#c30505` | wrong-password, destructive confirm            |

### Where a token may live

The token vocabulary is fixed at 11 keys. Two conventions keep it that way:

- **An alpha is not a colour.** `background #000000f2` from fuzzel and
  `#000000e6` from dunst mean "the background colour, 95%/90% opaque" — write
  `Theme.withAlpha(Theme.bg, 0.95)`. A literal `#f2000000` pins that surface to
  black and it will not move with the palette. The same applies to a token used
  as *text on* the accent: that is `--bg`, not "black".
- **No token means derive it, don't freeze it.** The 16 ANSI slots have no
  tokens of their own, so they are derived (hue rotations of `--accent` for
  blue/magenta/cyan, lightened variants for the bright half). Same for the
  `--olive`/`--text-2` names the HTML guide invented.

### Icons are neutral, and derived: `--icon` / `--icon-muted`

Icons are the one surface with **no colour of their own**: the set is monochrome
SVG with the colour written into every `stroke`/`fill`, because quickshell's
`IconImage` has no `color` property to bind. So an icon's colour cannot be a
token at the call site — it is baked by `sync-external-theme.py`. That made
`--accent` the de facto icon colour, and the bar's tray read as a row of orange
alerts competing with the one thing that *is* an alert.

Two derived colours instead, in `Theme.qml` (`Theme.icon`, `Theme.iconMuted`)
and `colorlib.neutral_icon()`:

| Token | Role |
| --- | --- |
| `--icon` | every chrome glyph: tray, media transport, weather, launcher column |
| `--icon-muted` | the *off* state of the set's two stateful pairs: `volume-muted`, `wifi-off` |

Built in three steps, and only the tint is a taste knob (`iconTint: 0.22`):

1. **anchor** — the achromatic colour with `--accent`'s exact luminance, so the
   tint cannot change how heavy the glyph looks versus what it replaced;
2. **tint** — 22% of `--accent` mixed back in, which keeps the palette
   recognisable without any icon reading as "coloured";
3. **pin** — to a contrast ratio against `--bg`, in *both* directions: 4.5:1 for
   `--icon`, 3.5:1 (the `--dim` floor) for `--icon-muted`.

The pin is why these are derived instead of authored per palette. `--accent`
only carries a 4.5 floor, so a wallpaper accent can land anywhere, and an icon
that inherited its luminance would be invisible on one wallpaper and blinding on
the next. It also keeps the 11-key vocabulary intact — `palette.sh`, tmux,
alacritty, niri and the guide read 11 tokens and nothing else.

Rules that follow:

- **Accent is for state, not chrome.** The active workspace pill, a selected
  launcher row, a critical battery percentage keep `--accent`. A tray glyph does
  not.
- **Never point a widget at `waybar/icons/`.** Those are the rollback gold and
  every colour in them is a literal sunset hex, so a widget reading from there
  ignores the palette and renders a different colour from its neighbour. Always
  `Theme.iconDir`.
- **The two implementations must agree.** `colorlib.neutral_icon()` paints the
  SVGs and `Theme.qml _pinIcon()` paints the launcher's Nerd Font glyphs, and
  those sit in one list one row apart.
  `scripts/test_icon_colors.py` extracts the real functions out of `Theme.qml`
  and runs them under `node` beside colorlib's, failing on any 8-bit
  disagreement.
- **Where an icon's state is drawn by its shape, colour is not repeated.**
  `battery`/`battery-charging` differ by the bolt and `play`/`pause` are
  mutually exclusive, so those pairs correctly take one weight. Only `volume` and
  `wifi` need two.

### Consumers

`services/Theme.qml` owns the palette and publishes the active one to
`~/.local/share/niri-setup/active-theme.json` on every change. Everything else
reads it from there:

| Consumer | Mechanism |
| --- | --- |
| quickshell (bar, popups, launcher, toasts, menus) | binds `Theme.*` directly |
| lock screen | `scripts/palette.sh get` |
| fastfetch | `scripts/sync-fastfetch-theme.py` from `fastfetch/config.jsonc.in` |
| tmux, both alacritty profiles, niri focus ring, HTML guide, stroke icons | `scripts/sync-external-theme.py` |

`scripts/sync-external-theme.py` rewrites every generated file only when its
bytes actually change, so a wallpaper that barely moves the accent costs four
`stat()`s. Its stdout names the targets that moved; `niri` in that list is the
shell's cue to hot-reload the compositor config, and it is absent when the
compositor file was already correct.

Generated (gitignored — edit the `.in` template instead):
`tmux/theme.conf`, `alacritty/default.toml`, `alacritty/float.toml`,
`help/theme.css`, `quickshell/sunset/assets/icons/theme/<fp>/`. Run it by hand
with `python3 scripts/sync-external-theme.py`.

### Legibility is a contract, not a taste call

Every palette — the 12 hand-written ones, the 4 wallust-derived ones, and
whatever the custom editor saves — is pushed to the same contrast floors before
it is drawn, by `Theme.qml`'s `legibility()`. The per-token numbers in a palette
are *tuning* (how vivid, how muted); the floors are what you are allowed to
ship. The table lives in `scripts/colorlib.py` as `FLOORS`/`FLOOR_ORDER` and is
duplicated in `Theme.qml` (QML cannot import Python);
`scripts/test_wallust_palette.py` parses the QML and fails if the two drift.

| token | floor | against | why |
| ----- | ----- | ------- | --- |
| `text` | 7.0 | `bg` | body copy, and it is *everywhere* |
| `accentHover` | 7.0 | `bg` | used as hover **text**, not just a fill |
| `accent`, `danger` | 4.5 | `bg` | WCAG AA; fills that carry text |
| `muted` | 4.5 / 3.0 | `bg` / `panel` | secondary text |
| `dim` | 3.5 / 3.0 | `bg` / `panel` | disabled and placeholder copy |
| `panel` | 1.30 | `bg` | must read as a *surface*, not a hue |
| `row` | 1.60 / 1.12 | `bg` / `panel` | buttons have to be visible |
| `border` | 1.25 | `bg` | separators, slider tracks |
| `borderStrong` | 2.50 | `panel` | card and button borders |

Two rules that came out of measuring all 16 palettes:

- **Text on an accent fill is measured, never assumed.** `Theme.onAccent` picks
  whichever of `bg`/`text` actually has more contrast against `accent`, and
  `onAccentMuted` does the same for the secondary line inside a selected row.
  `Theme.bg` on `Theme.accent` is wrong for roughly half of all palettes: two
  wallpaper palettes had *no* colour reaching 4.5:1 on their accent, so a
  selected launcher row was genuinely unreadable. Any surface filled with
  `Theme.accent` and carrying text uses these, not `Theme.bg`.
- **The search runs on the rounded 8-bit value.** Pushing a colour toward black
  or white until it clears a floor is a binary search on the mix amount, and
  rounding the result to a hex channel can land a hundredth *under* the target —
  which is exactly how the accent kept publishing at 4.49:1 against a 4.50
  floor. `floorEps` absorbs that, and pushing the far end as a "best effort"
  fallback collapses every colour to pure black or white, so there is none.

### Auto-theming has one meaning

Auto ON means *this palette follows the wallpaper*, so the picker can never show
Auto ON next to a fixed theme it is not following. An explicit pick of anything
that is not a `wallpaper*` variant turns Auto **off**; picking a wallpaper
variant keeps it on and becomes the variant auto follows (`autoVariant`), so
"Wallpaper Muted" is not undone by the next wallpaper change. `nextTheme`/`prevTheme`
route through the same entry point, so a bind cannot produce the same lie.

### Custom palette editor

`Mod+Alt+Shift+T` (launcher row "Custom Editor") opens `help/custom-theme.html`
via `scripts/custom-theme.sh`, which starts `scripts/custom-theme-server.py` on
**127.0.0.7**. Three things about it that are not decoration:

- **The page must not follow the palette.** Its chrome is a fixed neutral dark;
  only the preview takes the draft colours. An editor that themed itself would
  move the background under you while you judge a colour.
- **The server writes in place, never tmp-then-rename.** quickshell watches
  `theme-custom.json` by inode; a rename would replace the watch and the editor
  would save with nothing happening.
- **The server carries a token** in the URL and demands it in a header on POST.
  Loopback is reachable from every page in the browser, so without it any site
  you visited could POST a palette and repaint your desktop. `.7` rather than
  `.1` because `niri/rules.kdl` already pins `brave-127.0.0.1__-Default` — the
  legacy volume popup — to 400x440, which is not a usable editor window.

## Typography

- **JetBrainsMono Nerd Font everywhere**: bar, popups, lock screen, menus.
- Bar icons are minimalist stroke SVGs in `quickshell/sunset/assets/icons/`
  (24×24, 1.7px stroke, round caps), rendered by native QML widgets — never
  emoji, never font glyphs. They are monochrome with the colour written into
  every `stroke`/`fill`, so the live set is the generated copy under
  `assets/icons/theme/<fingerprint>/` (Qt caches a decoded image per URL, so a
  stable path would keep rendering the previous palette); resolve against
  `Theme.iconDir`. The originals stay as the sunset source of truth.
  (Legacy waybar session used `waybar/icons/` wired via `image#` modules
  with `waybar/scripts/*-icon.sh` resolvers.)

## Shape & glow

- Sharp rectangles. `border-radius: 0` on bar and popup cards.
- Resting shadow: `0 0 15px rgba(232, 93, 47, 0.15)`.
- Hover/active glow, e.g. text: `0 0 6px rgba(255,139,74,.9),
  0 0 18px rgba(255,139,74,.6), 0 0 35px rgba(232,93,47,.35)`.
- Selected/today: solid `--accent` fill with black text.

## Quickshell popups (calendar / volume / wifi / wallpaper / power) — LIVE

All popups are native QML components (`quickshell/sunset/components/`),
no Brave, no local servers. They follow the same visual pattern as the
legacy HTML popups below — compact floating cards hugging the content,
`Esc`/Close always closes, keyboard-first, destructive power actions need
a second click to confirm (lock runs at once).

- **Theme tokens**: `services/Theme.qml` is the single source of truth.
  No per-file hex — bind `Theme.*`.
- **One corner for hardware state**: Bluetooth, Wi-Fi, the mixer, quick
  settings and now playing are all **docked top-right under the bar**, 340
  wide, `transformOrigin: Item.TopRight`; calendar, clipboard, wallpaper,
  power, launcher and whip stay centered. A card belongs to the corner whose
  bar widget opened it. Two things that corner needs: `topInset` (the card
  anchors to the SCREEN top because its window spans the screen for the
  outside-click, so without the bar height its own header hides under the
  bar whenever no toast is up) and `toastOffset` (slide below a toast stack).
  Both are bound from `shell.qml`.
- **Toggles**: every popup/launcher exposes an `IpcHandler` target, toggled
  via `qs -c sunset ipc call <target> toggle`
  (`bluetooth | calendar | clipboard | launcher | power | settings |
  volume | wifi | wallpaper | wallpaper-menu | notifications | themes |
  sessions | whip | menu | osd | weather`), wired to bar buttons and
  `niri/binds-quickshell.kdl` (`Mod+Alt+*`). Two shortcuts deliberately
  leave quickshell and run a script instead: `Mod+Alt+S` →
  `scripts/gnome-settings.sh` (GNOME Settings replaced the old native
  Settings Center popup) and `Mod+Alt+H` → `scripts/open-help.sh`
  (`help/index.html`, the beginner guide, replaced the old native Help
  Center popup and its `?` launcher mode). Both scripts self-toggle, so a
  second press closes the window. Re-implementing what GNOME/HTML already
  do well was rejected; the shell keeps only what is shell-shaped.
- **Right-click context menus** (`components/ContextMenu.qml`): slim
  text-only row menus opened at the cursor — desktop right-click (input
  plane above the wallpaper, below windows) and bar right-click (drops
  below the bar at the click x). Same card/row tokens as the popups,
  separators in
  `--border`, rows dispatch to popups/commands and always dismiss.
- **Data**: thin services wrap the same backends — `AudioService` (Pipewire,
  holds its last volume/mute across a sink blink), `WifiService` (nmcli, two
  poll tiers: cheap always-on for the bar icon, the real scan only while the
  card is open), `MediaService` (MPRIS), `WallpaperService` (`scripts/wallpaper.sh`,
  shows busy state while a change applies), `NotificationService`
  (history 20, max 5 on-screen — dunst parity), `NiriService` (pure-QML
  `NIRI_SOCKET` EventStream for workspaces/windows).
- **Native popups need no niri window rules** (LayerShell, not windows).

## Media sources (MPRIS) — LIVE

`services/MediaService.qml` owns both "what is playing" and "which player".

- **Auto-pick is the default**: playing > paused-with-a-track > first on the
  bus. Unchanged from the waybar-era behaviour.
- **A manual pick wins** (`pinnedDbusName`, keyed by bus name — stable across
  re-registration, unlike a list index). It survives another player starting,
  and is released when the picked player loses its track (queue ended), when
  it leaves the bus, or via `releaseSource()`. Without that release the shell
  would sit on a dead player while music plays somewhere else.
- **Source switcher** in the card: one segment per player that holds a track.
  Active = accent fill + black text; a source that is *playing but not
  selected* keeps a 5px accent dot, so another app taking over is visible at a
  glance. Shown only when 2+ sources exist — with one, the dim identity line
  says it all. `S` cycles.
- ONE row, never wrapped (vertical space is scarce in this card), centred by
  anchoring, with each segment capped at `width / count` and long names
  eliding. Plain `Row` has **no** `horizontalAlignment` (RowLayout-only) and
  `Flow` wraps — both fail the whole config or the layout.
- UI never imports the Mpris module: `sourceName()` / `stateLabel()` return
  plain strings so the rows stay reactive through property reads.

## Microphone indicator — NOT IN THE BAR (rollback only)

`components/MicWidget.qml` + `services/MicService.qml`, both still on disk and
`MicService` still live through `Osd.qml` (the mic-mute OSD), but the widget is
**not instantiated in `Bar.qml`** any more (2026-10-03: "don't need the mic
icon") — the dot that lit up whenever another process held the mic was noise
rather than information. Re-add one `MicWidget {}` line to the right cluster to
bring it back; everything below is how it worked and why it was cheap to build.

- **A privacy light is carried by a dot, not an icon.** The stroke pipeline
  collapses every accent-ish role onto ONE neutral `icon` colour, so an icon
  physically cannot render "more alarming" than its own idle self — an
  accent-coloured microphone would come out the same grey. Recording is a
  6px `Theme.accent` dot that breathes (scale 1.0→1.3, opacity 1→0.5, 620ms
  `InOutSine`, both loops gated on `Theme.reduceMotion`). It sits to the right
  of the icon in the same `Row`, so the widget grows by exactly one item and
  the bar re-centres for that moment — acceptable, because the alternative
  (a permanently reserved 6px hole) reads as a misaligned icon when idle.
- **Three states, two icons.** Idle → `microphone.svg`. Recording → same icon
  plus the dot. Muted or no source → `microphone-off.svg`. Muted and absent
  are deliberately the *same* off half: neither is a privacy concern, and both
  mean "nothing can reach the mic right now".
- **The off icon keeps its own step** (`#555555` → `iconMuted`). That is the
  rule for the off half of a stateful pair (volume/volume-muted, wifi/wifi-off,
  microphone/microphone-off). Collapsing it onto the on step makes "muted" and
  "live" the same picture, which is the one thing this widget must never do.
- **Left click mutes; right click belongs to the bar menu.** Muting is the only
  privacy action worth one click and needs no popup. `MicWidget` must NOT
  claim `Qt.RightButton` — `Bar` routes that to `ContextMenu`.
- **No level meter.** `PwNodePeakMonitor.channels` is read-only and defaults to
  channels 3/4, which do not exist on a mono mic, so it reports 0 forever — even
  while something records from that same device. A dead meter pinned next to a
  lit recording dot is worse than no meter. If a level reading is ever needed it
  belongs to the dictation pipeline, which already holds the PCM.

## Now-playing timeline — LIVE

`components/NowPlayingPopup.qml`, Material 3 Expressive ("wavy linear") seek bar.

- **Four layers, one track**: translucent aura wave (phase-lagged), solid
  accent wave, and a circle head carrying a soft glow plus a ring that pulses
  outward. Layer order is draw order; the aura is the accent token at 26%
  alpha, never a new colour.
- **Loud only while it plays.** `root.waveLevel` (0/1 off
  `MediaService.isPlaying`, 420ms `InOutSine`) is a multiplier on both
  amplitudes, so it eases UP into the wave and eases OUT to a flatline
  symmetrically; `root.flow` keeps running while `waveLevel > 0.01` so the
  sine travels during the settle instead of freezing mid-ripple. Paused is a
  plain flat bar and the head ring fades out (its `opacity` binding takes over
  from the stopped loop, with a Behavior). Hover/drag is the other trigger
  (`expanded`): track 15px → 24px, amplitudes roughly double, front stroke
  5 → 7px. The track is sized so a crest at max swell still fits — a clipped
  crest is what made the sine read as aliased. `Theme.reduceMotion`
  scales every amplitude by 0 and stops both loops, so the kill-switch
  flattens the bar instead of hiding it.
- **The head stays a circle** — it only grows (20 → 28px on drag) with an
  OutBack overshoot. No pill morph.
- **One phase for every layer** (`root.flow`, a single looping
  `NumberAnimation` at 60fps); per-layer animations drift apart and triple the
  per-frame property churn. Layers differ only by `phaseOffset`.
- **The sine is sampled every 3px** (~24 points per 72px wavelength). Coarser
  steps are not a perf win: the round-capped stroke turns into a scalloped
  rope that reads as aliasing. Measured on this machine, quality is FREE here —
  60fps/3px costs the same as 30fps/10px, because the per-frame cost is the
  full-screen transparent window, not the geometry.
- `PathPolyline.path` needs `Qt.point(x, y)` entries — a flat `[x,y,x,y]`
  list type-checks but draws nothing. Default GeometryRenderer on purpose:
  `Shape.CurveRenderer` needs a real RHI backend.
- **Crest depth follows the sink level** (`root.swell` = 0.7 at mute → 1.45 at
  100% off `AudioService.volume`/`muted`); it is a plain multiplier on both
  layers' `amplitude`, so the bar breathes with the music. The floor is high on
  purpose: at 0.4 the amplitude fell to ~1px and the thick stroke read as a
  jagged rope. Layer `Behavior`s smooth the steps.
- **Nothing animates out of sight.** Every loop is gated on `win.visible`
  (plus `waveLevel`), so a closed popup costs nothing — measured 0% CPU while
  music still plays. While it IS open the wave costs ~20% of one core; that is
  per-frame window overhead and is unavoidable without giving up the
  full-screen click-outside-to-close backdrop (a card-sized window measured
  10%).
- `fillW` (the filled width) must NOT be `readonly`: QML refuses a `Behavior`
  on a read-only property. Its behaviour is disabled while dragging so the
  fill can't lag the head.

### Playback-mode toggles — LIVE

`NpToggle` (repeat / shuffle / pin), the row under the transport buttons.

- **State is shape + underline, never an accent fill.** `Theme.onAccent` is
  measured for *Text*; a stroked SVG cannot be repainted for a bright
  background because QtQuick's `Image` has no `color` (binding one does not
  tint, it fails to load). Filling the pill put a `dim`-weight glyph on an
  accent fill and it read as a grey smudge. The pill stays `row`/transparent
  and an accent underline carries the state — the `Workspaces.qml` active-pill
  trick, reused deliberately.
- **Repeat has three glyphs**, not three tints: `repeat-off` (None),
  `repeat-one` (Track), `repeat` (Playlist). At 26px a fill-only tell was not
  readable, and "off" needs the slash to differ from "on" without relying on
  colour at all.
- **Off-state icons are authored on `#555555`**, so the generator maps them to
  `iconMuted`. `#555555` is the only role in `ICON_ROLE_BY_SUNSET_HEX` with its
  own step, and it is load-bearing: shape is what distinguishes muted from
  working, colour only reinforces.
- **Ask the player whether it supports the mode** (`loopSupported` /
  `shuffleSupported`), never the metaobject. Brave exports neither `LoopStatus`
  nor `Shuffle`, so an unconditional row is dead buttons that look live; the
  hint line is assembled from the same flags so it cannot advertise a key that
  does nothing.
- The pin is hidden unless 2+ sources exist — with one player there is nothing
  to protect against, and an untestable control should not be advertised.

## HTML popups (calendar / volume / wallpaper / power) — LEGACY

Waybar rollback session only. All four follow one pattern — keep it
(only touch when fixing the rollback session):

- Self-contained single HTML file, no external deps. Inline CSS + JS.
- `brave --app=<url>` with a **dedicated profile** per popup
  (`~/.cache/niri-calendar`, `niri-volume`, `niri-wallpaper`, `niri-power`).
- Small fixed window that **hugs the content**: utils `400×440`
  (near-square; clock `400×490` with its tab bar), gallery `760×560`. No dead space, no scrolling unless a
  list genuinely overflows (extra sinks).
- Card centered, small even margin. Centered text for headers/readouts.
- Toggle on re-click. `Esc` and a Close button always close (`window.close()`).
- Keyboard first: arrows adjust, `Home`/today resets, `M` mutes,
  double-click sets wallpaper, destructive power actions need a second
  click to confirm (lock runs at once).
- Live data: poll status every ~1.5s, pause polling while dragging a slider.
- Static pages (calendar) use `file://`; pages needing actions use a
  **stdlib-only** Python backend on loopback (volume `127.0.0.1`,
  wallpaper `localhost`, power `127.0.0.2` — distinct hosts give distinct
  Brave app-ids). Servers bind an ephemeral port and publish it to a
  `$STATE_DIR/port` file. APIs take ids/indexes, never filesystem paths;
  power actions are a fixed 5-command allowlist.
- Waybar tooltips get a one-line hint of click behavior
  (e.g. `Left: Mixer | Right: Mute`), styled dim/small.

## Lock screen — LIVE

`Mod+L` → `scripts/swaylock.sh` → `swaylock` (swaylock-effects 1.8.1) over an
image built by `scripts/swaylock-bg.sh`.

- **All the text is baked into the background image**, because swaylock takes the
  output with `ext-session-lock-v1` and nothing may draw over it: big clock
  top-left, date under it, `scripts/lock-info.sh` rows under that, and a
  centred `` (nf-fa-lock) `enter password` hint. The hint
  is the resting affordance — with no `--indicator`, swaylock draws *nothing*
  until the first keypress. Baked time is correct when locking and does not tick
  while locked. The hint sits **below** the hairline, not above: the top of the
  circle is where the fourth widget row lands, and a hint up there overlapped
  `artist — title`.
- **Widget rows** come from `scripts/lock-info.sh`, up to `ROWS=4` (not 3 —
  weather is two lines, so a third slot would push the battery off the bottom
  the moment music started). Order: weather, media, battery. `MAX_COLS=70` caps a
  row so a long track name cannot run to the right edge.
- **Now playing** (`lock-info.sh media`) prints one `♪ artist — title` line, and
  prints **nothing at all** unless some MPRIS player's status is literally
  `Playing` — a paused player 40 minutes ago must not leave a stale row on the
  lock screen. It probes per player and skips the ones that are not playing, and
  the whole probe is inside one `timeout` (~125 ms) because it runs while the
  user watches a spinner. `LOCK_INFO_SECTIONS=weather,battery` drops it.
- **The backdrop is a scrim, not a blackout.** `DARKEN=0.40` over a blur of
  `BLUR_SIGMA=9` at a `SCALE=4` canvas (≈sigma 36 on screen): recognisable
  picture, no readable detail. `SCRIM=0.55` ramps over the left 64% for the
  baked text; `DOT_GLOW=0.42` is a centred ellipse so the indicator text reads on
  any wallpaper. One earlier version used `DARKEN=0.75` + sigma 18 and composited
  a `w×h` scrim over a *wider* base — that is what "my wallpaper isn't showing"
  was. Sizes must match exactly or you get hard rectangular seams.
- **Theme colours come from `scripts/palette.sh`**, so wallust and ThemePicker
  both repaint the lock. `muted` is mixed toward `text` for the date/rows/hint
  because the token is tuned for a bar on a dark panel and has to survive an
  arbitrary photograph.
- **This locker draws no password dots.** Verified in `render.c` (v1.8.1) and
  live: `state->password` is never read there, so there is no character count and
  no option that invents one. What it does have, inside a single `if
  (args.indicator || …)` block, is: inside fill, ring, one state *message*, a 60°
  arc that jumps on every keypress, border circles and the layout box. So
  `--no-unlock-indicator` silences the lot — never pass it expecting dots.
  The reaction budget is therefore: hairline ring (radius 100, thickness 2) as a
  seat for the keystroke arc, fully transparent inside and border circles, and
  one short word per state — `checking…` / `wrong password` (danger) /
  `cleared` (muted) / `caps lock`. Keep those words short: `2*RADIUS` is the
  widest they can be.
- Never pass `--clock` (second clock, centre) or `--show-keyboard-layout` (the
  big `English (US)` chip); `-K` is passed as a belt-and-braces override.
- Never pass `--ignore-empty-password`: it means pressing Enter on an empty field
  unlocks. If the backdrop can't render, lock on a flat `--color` rather than
  not locking.

## Launcher "Open" section

The launcher's empty query shows what is **already running**, pinned between
Controls and Bookmarks — one row per app, not per window and not per .desktop
entry.

- **Names and glyphs only.** No geometry, no workspace coordinates, no `app_id`,
  no window id, ever. Those are niri internals and they made the old `$` window
  rows read like a debug dump. Detail line is `N windows`, or that app's window
  title when there is exactly one.
- Nerd Font glyph, not an SVG: `` (Alacritty), `` (Brave),
  `` (Code), `` (Files). Written as `\uXXXX` escapes — the private-use
  area has no fallback font, so a wrong codepoint is a silent wrong icon, and a
  pasted raw glyph is unreviewable in a diff.
- A generic `` (bars) is the fallback for an unrecognised `app_id`, and
  the name is derived by dropping reverse-DNS packaging words
  (`desktop`/`app`/`client`/…), so `org.telegram.desktop` reads "Telegram"
  rather than "Desktop".
- One row per `app_id`, so each installed Chromium PWA keeps its own row. That is
  deliberate: they are separate apps, but they still match the browser table by
  substring and so all get the browser glyph.
- Controls stay first so the default selection is still Settings.

## Don'ts

- No `yad`/`zenity` GTK dialogs — they can't match the theme.
- No Cancel/OK chrome on view popups; no window decorations needed.
- No blue/grey (`#b7d4ed`, `#61768F`) or Ubuntu fonts — that was the old
  Frosted Midnight theme, fully replaced.
- No full-screen or tiled popups: floating, compact, centered.
- No new accent colors. If white is needed (wrong-password), that's the
  only exception.
