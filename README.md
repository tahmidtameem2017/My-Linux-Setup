<div align="center">

# 🌅 Sunset Niri

**A complete, animated macOS-style Wayland desktop — bar, launcher, popups, theming and all.**

*Scrollable-tiling [niri](https://github.com/YaLTeR/niri) compositor + a native
[Quickshell](https://quickshell.org/) QML shell, a dynamic wallpaper-aware theme engine,
and 16 lazy-loaded popups.*

[![niri](https://img.shields.io/badge/compositor-niri%2026.04-blue)](https://github.com/YaLTeR/niri)
[![quickshell](https://img.shields.io/badge/shell-quickshell%200.3.1-purple)](https://quickshell.org/)
[![license](https://img.shields.io/badge/license-GPL--3.0-green)](./LICENSE)
[![based on](https://img.shields.io/badge/based%20on-acaibowlz%2Fniri--setup-ff69b4)](https://github.com/acaibowlz/niri-setup)

Built by **[tahmidtameem2017](https://github.com/tahmidtameem2017)** —
a full rewrite of the original
[`niri-setup`](https://github.com/acaibowlz/niri-setup) by
[acaibowlz](https://github.com/acaibowlz). See [Credits](#-credits--acknowledgements).

</div>

---

## 📝 Changelog

**2026-10-05 — The launcher has a right-click menu, and you can pin things.**
Right-click any row — or press <kbd>F10</kbd>, or the Menu key — and get a menu
that matches what that row *is*. An app gets Preview · Reveal · Terminal ·
Copy · Pin. A file gets the same, plus Open in file manager. A bookmark gets
Rename · Delete. Right-click the search box, or the empty space under the
list, and you get the plain "how to use this" menu instead:

| Right-clicking… | gives you |
| :-- | :-- |
| an app row | Preview · Reveal · Terminal · Copy · Pin |
| a file row | the same, plus Open in file manager |
| a saved site | the same, plus Search this site |
| the search box | the help menu — what every symbol means |
| the desktop, or the bar | the desktop menu (Settings, Help, lock, …) |

Every item shows its keyboard twin on the right, so you learn the shortcut
instead of the mouse path. **Nothing is offered that the row cannot do** — a
folder in the help list with no real path gets no Terminal or Copy.

> **<kbd>F10</kbd>, not <kbd>;</kbd>.** <kbd>;</kbd> is already the launcher's
> *Modes* prefix, so it cannot be both. <kbd>F10</kbd> is unbound in niri, so
> the key handler handles it directly — adding a compositor bind would make it
> fire twice.

**Pinned rows** land in their own **Pinned** section above Controls, and stay
there next session. Pick **Pin to top** from the right-click menu, or press
<kbd>F10</kbd> and choose it there. A pin is a *duplicate*, not a move: the
Applications list stays complete and alphabetical, and typing shows no pinned
block at all, so a search can never return the same app twice.

Also new in the launcher:

| Keys | What it does |
| :-- | :-- |
| <kbd>Ctrl</kbd>+<kbd>T</kbd> | Open a terminal in the highlighted file's own folder |
| <kbd>Ctrl</kbd>+<kbd>Tab</kbd> | Fill in the highlighted site's shortcut, so you can search *that* site |
| <kbd>Ctrl</kbd>+<kbd>Space</kbd> | Instant web search (moved from Quick Look) |

Pinned by two new tests that run the launcher's real functions: one compares
both halves of the menu's command allowlist (a name present in one and not the
other renders an item that silently does nothing), the other pins the
site-shortcut logic.

**2026-10-05 — <kbd>Ctrl</kbd>+<kbd>Space</kbd> is instant web search.**
Press it, type your query, press <kbd>Enter</kbd> — the launcher opens
*already in web search*, with `@` filled in for you, so you go straight to
typing:

| You type | What opens |
| :-- | :-- |
| <span class="pill">google weather</span> | Google (the `google` site shortcut) |
| <span class="pill">how to tile windows</span> | DuckDuckGo |
| <span class="pill">github niri</span> | GitHub |
| <span class="pill">https://…</span> | the link itself |

All eight site shortcuts — `@dd` `@g` `@yt` `@w` `@gh` `@so` `@r` `@maps`
— work exactly as before, because this is the **same**
`WebProvider` the typed `@` prefix already used. The result opens with
`xdg-open`, i.e. a tab in your real browser.

> **Quick Look moved to <kbd>Ctrl</kbd>+<kbd>Alt</kbd>+<kbd>Space</kbd>.**
> <kbd>Ctrl</kbd>+<kbd>Space</kbd> belonged to the launcher's file preview
> since before this desktop was written up. Web search wanted that chord
> specifically, so Quick Look moved one modifier along. Highlights the file
> row as before.

Also works from a terminal:

```sh
qs -c sunset ipc call launcher websearch
```

Backed by `Launcher.qml`'s `websearch()` (it calls the existing
`applyPrefix()`, extracted so the `;` mode rows and this keybind share one
code path instead of two copies of the debounce handling), the `launcher`
IPC shim in `shell.qml`, and one bind in `niri/binds-quickshell.kdl`.
No new QML component, no new icon, no new script — the whole feature is a
re-pointing of a prefix that was already there.

**2026-10-04 — All-in-one Config Editor.** <kbd>Alt</kbd>+<kbd>Space</kbd>
→ **Config Editor** opens a floating panel that tunes the compositor
itself — no config file, no logout:

| Setting | Range |
| :-- | :-- |
| Window gaps · focus-ring width · corner radius | sliders, in px |
| Default column width · window opacity | sliders, in % |
| Center focused column | never / on-overflow / always |
| Window open / close animations | 0–600 ms each |
| Tap-to-click · natural scrolling | toggles |
| Mouse acceleration | −1 … +1 |

Three things make it safe: it edits the **live** `~/.config/niri/*.kdl`
(not the repo, so your tweaks survive a theme sync), every change is
`niri validate`d **before** the compositor sees it — a bad drag restores
the old files — and applying is a hot-reload, not a restart. Run the row
again to close it. Backed by `scripts/config-editor.sh` +
`scripts/config-editor-server.py` (a loopback page on `127.0.0.8` — a
`file://` page cannot write your config — with a token in the URL and a
required header on every POST, so no other page can reconfigure the
compositor), pinned to 620×860 by a `rules.kdl` window rule.

**2026-10-04 — The launcher's `%` list is a real bookmark manager.**
Four things landed:

- **Import from your browser** — <kbd>Alt</kbd>+<kbd>Space</kbd> →
  **Import Bookmarks** pulls in bookmarks from Brave, Chrome, Chromium,
  Vivaldi, Edge, Opera, Arc, Firefox, LibreWolf and Waterfox, **with
  their favicons** taken from the browser's own cache (nothing is
  fetched over the network). The import only ever **adds**: run it again
  after bookmarking something new and only the genuinely new ones arrive —
  anything you renamed, reordered or deleted in the launcher is left
  alone, and a bookmark you deleted there is never brought back.
- **Delete with <kbd>Delete</kbd>** — highlight a bookmark and press
  <kbd>Delete</kbd>: the row vanishes in place and the menu **stays
  open**, so several can be removed in a row. `%delete <name>` still
  works for deleting by name without highlighting.
- **Rename** — `%rename <old> to <new>` rewrites the name only; the link
  and its icon survive. Half-typed renames do nothing.
- **Real names for URL-only bookmarks** — a bookmark saved as a bare
  link now shows a name derived from the URL's path
  (`github.com/anthropics` → *anthropics*), not the link itself.

Backed by `scripts/import-browser-bookmarks.py` (pure stdlib —
`sqlite3` + `json`; databases are copied to a temp dir before reading,
because Chromium keeps them open in WAL mode) + `scripts/import-bookmarks.sh`
(the launcher row relays the report as a notification), covered by
`scripts/test_import_bookmarks.py`.

**2026-10-04 — `Ctrl+C` copies any file row.** In the launcher, type `/`
to search files, highlight a row, press <kbd>Ctrl</kbd>+<kbd>C</kbd>:

| File type | What lands on the clipboard |
| :-- | :-- |
| **Text** — `.txt` `.md` `.py` `.c` `.cpp` `.sh` `.json` … | the file's **contents** — paste into a terminal, editor or chat |
| **Pictures** — `.jpg` `.png` `.jpeg` `.webp` `.gif` … | the **image itself** — paste anywhere a screenshot pastes |
| **Everything else** — folders, binaries, archives | the **path** |

The menu stays open, so you can copy several files in a row. The other
file-row keys are unchanged: <kbd>Enter</kbd> opens,
<kbd>Ctrl</kbd>+<kbd>Enter</kbd> reveals in the file manager, and
drag-and-drop still works. Backed by `scripts/copy-file.sh`
(`wl-copy`), covered by `scripts/test_copy_file.py`.

> 🎬 **See it in action** — the demo walks through copying a script, a wallpaper
> image and a `.c` file straight out of the launcher:
>
> [**▶ Play the demo**](https://raw.githubusercontent.com/tahmidtameem2017/My-Linux-Setup/refs/heads/main/Screenshots/demo-copy-paste-and-performance.mp4)
> (also in `Screenshots/demo-copy-paste-and-performance.mp4`)

**2026-10-04 — On-demand performance monitor.** A CPU · GPU · MEM · BAT pill in the
bar's center island. <kbd>Mod</kbd>+<kbd>Alt</kbd>+<kbd>P</kbd>, the launcher's
**Performance** row, or `qs -c sunset ipc call perf toggle`:

| Surface | What it does |
| :-- | :-- |
| **Keyboard** | <kbd>Mod</kbd>+<kbd>Alt</kbd>+<kbd>P</kbd> |
| **Launcher** | **Performance** row |
| **IPC** | `qs -c sunset ipc call perf toggle \| turnOn \| turnOff` |
| **Click the pill** | Opens `btop` in a floating terminal |

It is **hidden by default** — the island is just weather + clock until you ask for
it, and turning it off collapses it away completely. Missing sensors (a GPU without
frequency reporting, no battery) hide their own segment instead of showing a `0`.
CPU is a real delta over 0.5 s rather than an instantaneous reading. Backed by
`services/PerfService.qml` + `scripts/perf-stats.sh`, covered by
`scripts/test_perf_stats.py`.

---

## 📸 Screenshots

**The desktop as it actually runs today** — taken from this build:

| Desktop | Volume mixer | Now Playing |
| :--: | :--: | :--: |
| ![Desktop](https://raw.githubusercontent.com/tahmidtameem2017/My-Linux-Setup/refs/heads/main/.github/assets/screenshots/desktop.png) | ![Volume mixer](https://raw.githubusercontent.com/tahmidtameem2017/My-Linux-Setup/refs/heads/main/.github/assets/screenshots/volume-mixer.png) | ![Now Playing](https://raw.githubusercontent.com/tahmidtameem2017/My-Linux-Setup/refs/heads/main/.github/assets/screenshots/now-playing.png) |

**Startup RAM usage** — the whole desktop (bar, compositor, a terminal)
about 40 s after login, measured with btop:

![Startup RAM usage](Screenshots/startup%20ram%20usage%20.png)

> `quickshell` 246 MB · `niri` 106 MB · `alacritty` 72 MB — with every
> popup lazy-loaded on demand rather than resident.

### 📸 Screenshots still to capture

New in this build and **not photographed yet**. Each row is one image to grab;
drop it in `.github/assets/screenshots/` with the exact filename and tick the
box — the table below and the `Screenshots needed` note in the agent prompt
(`scripts/CHANGELOG-AGENT.md`) are the checklist.

| # | What to show | Why it earns a picture | File | Done |
| :-: | :-- | :-- | :-- | :-: |
| 1 | Launcher with the **row menu** open on an app row | The whole feature is a right-click, so a static shot of the launcher shows none of it. Show Preview · Reveal · Terminal · Copy · Pin and the keyboard hints on the right. | `launcher-row-menu.png` | ☐ |
| 2 | Launcher with the **Pinned** section populated | Pinning is invisible until rows are pinned — an unpinned launcher looks identical whether the feature works or not. | `launcher-pinned.png` | ☐ |
| 3 | **Ctrl+Space** web search mid-query | Proves `@` is pre-filled and the site shortcuts still resolve — the "just works" moment. | `launcher-websearch.png` | ☐ |
| 4 | **Ctrl+Tab** on a highlighted site | One keypress fills the site's shortcut. Static before/after in a single frame if you can. | `launcher-site-seed.png` | ☐ |
| 5 | **Ctrl+T** terminal opened in a file's folder | Proves the cwd is the file's *own* folder, which is the entire point. Terminal title/prompt should show the path. | `launcher-terminal.png` | ☐ |
| 6 | **CaptureBar** with all eight tools | Replaces the older `screenshot6.png` capture shot, which shows a different menu. | `capture-bar.png` | ☐ |
| 7 | **Config Editor** window | Last build's headline feature; `Alt+Space` → Config Editor. | `config-editor.png` | ☐ |
| 8 | **Wi-Fi card** docked top-right | Moving from a floating nmtui terminal to a native card is a visible change. | `wifi-card.png` | ☐ |
| 9 | Bar with the **performance pill** visible | It's hidden by default, so the default desktop shot can never show it. Toggle with `Mod+Alt+P`. | `performance-pill.png` | ☐ |
| 10 | **Theme picker** on a wallpaper-derived palette | The dynamic theming pitch is one picture: wallpaper colours in the bar and popups. | `theme-picker.png` | ☐ |

> `.github/assets/screenshots/screenshot7.png` is tracked but referenced
> nowhere — reuse or delete it rather than leaving a third spare. Rename the
> new images to match the existing lowercase-hyphen style (`desktop.png`,
> `volume-mixer.png`, `now-playing.png`) so the table stays consistent.

<details>
<summary><b>More from the original niri-setup (acaibowlz)</b></summary>

| | | |
| :--: | :--: | :--: |
| ![Desktop](https://raw.githubusercontent.com/tahmidtameem2017/My-Linux-Setup/refs/heads/main/.github/assets/screenshots/screenshot1.png) | ![Launcher](https://raw.githubusercontent.com/tahmidtameem2017/My-Linux-Setup/refs/heads/main/.github/assets/screenshots/screenshot2.png) | ![Now Playing](https://raw.githubusercontent.com/tahmidtameem2017/My-Linux-Setup/refs/heads/main/.github/assets/screenshots/screenshot3.png) |
| ![Wallpapers](https://raw.githubusercontent.com/tahmidtameem2017/My-Linux-Setup/refs/heads/main/.github/assets/screenshots/screenshot4.png) | ![Power Menu](https://raw.githubusercontent.com/tahmidtameem2017/My-Linux-Setup/refs/heads/main/.github/assets/screenshots/screenshot5.png) | ![Capture](https://raw.githubusercontent.com/tahmidtameem2017/My-Linux-Setup/refs/heads/main/.github/assets/screenshots/screenshot6.png) |

</details>

---

## 🧰 Tech Stack

This is not just a `config.kdl` — it is a full desktop shell written in QML, plus a
theming engine and ~80 helper scripts.

| Layer | Technology | What it does |
| :-- | :-- | :-- |
| **Compositor** | [niri](https://github.com/YaLTeR/niri) 26.04 | Scrollable-tiling Wayland WM, driven by modular KDL config |
| **Shell** | [Quickshell](https://quickshell.org/) 0.3.1 | Native QML bar, 16 popups, toasts, OSD — replaces Waybar/dunst |
| **Launcher** | Native QML (Fuzzel kept as fallback) | App search + pinned "Controls" rows + Bookmarks + Sessions |
| **Theme engine** | `services/Theme.qml` + Python | 11 color tokens, 15 themes, contrast-enforced legibility |
| **Wallpapers** | [swaybg](https://github.com/swaywm/swaybg) + [wallust](https://github.com/dwallust/wallust) | Auto-theming: extracts a palette from every wallpaper |
| **Notifications** | Quickshell Toasts | Owns `org.freedesktop.Notifications` (dunst = rollback only) |
| **Lock / Idle** | [swaylock-effects](https://github.com/swaywm/swaylock) + [swayidle](https://github.com/swaywm/swayidle) | Image-based lock screen with live clock/weather/media |
| **Clipboard** | [cliphist](https://github.com/sentriz/cliphist) + `wl-clipboard` | History, image paste, preview |
| **Screenshots** | [flameshot](https://flameshot.org/) + [tesseract](https://github.com/tesseract-ocr/tesseract) | Region/window/screen/scroll/record/OCR in one panel |
| **Terminal** | [Alacritty](https://github.com/alacritty/alacritty) + [tmux](https://github.com/tmux/tmux) 3.7 | Themed, auto-generated from the active palette |
| **Dictation** | [whisrs](https://github.com/collada/whisrs) (whisper.cpp) | 100% offline voice typing |
| **Music** | [yt-dlp](https://github.com/yt-dlp/yt-dlp) + mpv + [playerctl](https://github.com/altdesktop/playerctl) | Download, play, dedup, MPRIS |
| **Network / Audio** | `nmcli`, PipeWire, `wpctl`, `playerctl` | Wi-Fi card, mixer, Bluetooth |

> Everything renders in **QML**. The icon set is generated per-palette, and the
> whole theme (tmux, Alacritty, niri, help pages) re-themes live when you change
> the wallpaper.

---

## 💻 Built for Laptops

This is an **opinionated laptop desktop**, inspired by
[omarchy](https://github.com/omarchy-dev/omarchy). It is tuned for a machine you
carry around and use with your hands, not a tower you sit in front of.

**Trackpad-first.** niri's compositor handles touchpad input natively through
libinput — no helper daemon, no extra process. Touchpads are already enabled and
tuned in `niri/input.kdl`:

```kdl
touchpad {
    tap              # tap-to-click
    natural-scroll   # inverted, like macOS
    drag-lock        # keep holding a drag when your finger lifts briefly
}
```

The mouse gets `natural-scroll` and a gentle `accel-speed 0.3`.

Multi-finger gestures (three-finger workspace switch, pinch-to-zoom) are available
via the [Gestures wiki](https://github.com/niri-wm/niri/wiki/Gestures) if you want
them — this setup ships with the defaults, which already cover scroll, click, and
drag.

**One hand, one keyboard.** The whole shell is built around the keyboard: a
launcher, 16 popups and every action on a shortcut, so you rarely need to reach for
the trackpad twice.

**Laptop-aware power.** `swayidle` locks and suspends on idle, with a configurable
timeout (`scripts/swayidle.sh`). You can change it without touching code:

```bash
bash scripts/change-idle-time.sh     # 5 / 10 / 20 / 30 minutes, or infinity
```

> [!WARNING]
> **This repo is tuned for a laptop with no battery** (a desktop-class machine or a
> battery-less laptop), which is what it was developed on. Two consequences:
>
> - **No battery icon.** `BatteryWidget` reads UPower and **collapses itself
>   automatically** when no battery is present — no config change needed. On a real
>   laptop with a battery it simply appears.
> - **The CPU governor is pinned to performance** (`scripts/cpu-permanent.sh`, 2.4 GHz
>   minimum, bypasses battery throttling). That is correct for a mains-powered
>   battery-less machine, but **on a laptop with a real battery it will drain it
>   fast**. If you have a battery, **skip Phase 4 (privileged extras) in the install
>   prompt** — or just don't let the agent install those two CPU rules.

---

## 🆓 Make It Yours

**This setup is free to change, and you are encouraged to.** There is no "correct"
configuration — it's the one I happened to land on after a lot of fiddling. Fork it,
break it, rewrite it.

**Nothing here is precious.** Every file is plain text in git: KDL for niri, QML for
the shell, shell/Python for the scripts. Change what you don't like and keep going.

### The five-minute customisation

Most things need no editing at all — they're knobs:

```bash
# look at every wallpaper knob
bash scripts/wallpaper-process.sh get

# change some (validated as a set — one bad value changes nothing)
bash scripts/wallpaper-process.sh setmany INTERVAL 30 DOWNSCALE 1920x1080

# switch theme instantly, then make it stick
qs -c sunset ipc call themes set nord

# change your idle timeout
bash scripts/change-idle-time.sh
```

### Where to edit what

| To change… | Edit | Then |
| :-- | :-- | :-- |
| **Keybindings** | `niri/binds.kdl`, `niri/binds-quickshell.kdl` | `cp niri/*.kdl ~/.config/niri/ && niri validate && niri msg action load-config-file` |
| **Colours / theme** | `quickshell/sunset/services/Theme.qml` — or use the editor (<kbd>Mod</kbd>+<kbd>Alt</kbd>+<kbd>Shift</kbd>+<kbd>T</kbd>) | restart shell: <kbd>Mod</kbd>+<kbd>Shift</kbd>+<kbd>Q</kbd> |
| **The compositor itself** (gaps, focus ring, column width, opacity, corner radius, animations, touchpad, mouse) | <kbd>Alt</kbd>+<kbd>Space</kbd> → **Config Editor** | applied live — `niri validate`d first |
| **The bar layout** | `quickshell/sunset/components/Bar.qml` | restart shell |
| **A popup's look** | the matching `quickshell/sunset/components/XPopup.qml` | restart shell |
| **Wallpaper behaviour** | `scripts/wallpaper-process.sh` (`get`/`setmany`/`reset`) | takes effect immediately |
| **Window rules** (opacity, floating, sizing) | `niri/rules.kdl` | `niri msg action load-config-file` |
| **Screenshots folder** | `niri/misc.kdl` (`screenshot-path`) | `niri msg action load-config-file` |
| **Touchpad behaviour** | `niri/input.kdl` | `niri msg action load-config-file` |
| **Terminal look** | `alacritty/*.toml.in` — **not** the generated `.toml` | `python3 scripts/sync-external-theme.py` |
| **tmux behaviour** | `tmux/tmux.conf` (colours are generated separately) | `tmux source-file ~/.config/tmux/tmux.conf` |

> [!IMPORTANT]
> **Never hardcode a hex colour in a QML component.** Every colour comes from
> `Theme` (`services/Theme.qml`) so it follows the palette. A literal hex is the one
> mistake that silently breaks theming — and a test enforces it.

> [!TIP]
> **After editing `niri/*.kdl` you must copy them to `~/.config/niri/`** — see the
> install step above. Symlink per-file instead if you want the repo to stay live.

### Ideas you could add

The bar, launcher and popups are all QML with existing patterns to copy:

- A **new popup** — copy an existing `components/XPopup.qml`, register it in
  `shell.qml` (both a `LazyLoader` and an `IpcHandler`), then bind a key to
  `qs -c sunset ipc call <target> toggle`.
- **A new launcher row** — `components/launcher/providers/`.
- **A new theme palette** — add an entry to `Theme.qml`; contrast floors are enforced
  automatically.

`AGENTS.md` documents the architecture in detail — read it before a big change.

---

## 🙌 Contributing

**Contributions are very welcome.** If you've made changes you think improve this,
please send them.

**Good contributions are:**
- A new palette, wallpaper source, launcher provider or popup
- Bug fixes, especially on non-Arch distros or unusual hardware
- Better defaults for other people's machines (touchpads, HiDPI, battery)
- Documentation you had to write for yourself because it wasn't here
- Cleanups — this is opinionated, so "I did it differently" is worth saying out loud

**Please open an issue or a PR on
[My-Linux-Setup](https://github.com/tahmidtameem2017/My-Linux-Setup).** If your change
touches the theme, run the tests first:

```bash
python3 -m unittest discover -s scripts -p 'test_*.py'    # 202 tests, ~14s
niri validate
```

**A note on scope:** this is a personal setup, not a distribution. Changes that make
it more broadly useful (new hardware, other distros, accessibility) are the most
welcome; changes that only suit one machine are fine too — just say who they're for.

---

## 🖥️ Compatibility

The desktop is **Wayland-only** and needs a modern GPU stack. It runs on **Arch Linux,
Fedora and Debian/Ubuntu (and derivatives)** — the shell itself is pure QML and is
100% distro-independent; only *package names* differ.

| Component | Arch | Fedora | Debian / Ubuntu |
| :-- | :--: | :--: | :--: |
| niri | ✅ official repo | ✅ COPR / official | ✅ pacstall / build |
| Quickshell 0.3.1 | ✅ AUR | ✅ COPR | ⚠️ build from source |
| swaybg / swayidle / swaylock-effects | ✅ | ✅ | ✅ |
| fuzzel, cliphist, wlogout, dunst | ✅ | ✅ | ✅ |
| All Python helpers | ✅ stdlib only | ✅ stdlib only | ✅ stdlib only |

**Minimum versions:** `niri ≥ 25.11` (26.04 recommended) · `quickshell ≥ 0.3.0` ·
`tmux ≥ 3.6` · Python 3.9+. **No Python `pip` packages are required** — every
script is standard library only.

> [!TIP]
> **Non-technical?** Skip to [🚀 Super-Easy Install](#-super-easy-install) — you can
> copy-paste **one command** per distro, or paste a single prompt into an AI assistant.

---

## 🚀 Super-Easy Install

> [!IMPORTANT]
> **Already have niri + Quickshell installed?** Jump to
> [Step 3 only](#step-3--install-this-desktop-30-seconds) and skip the package commands.

### Step 1 — Pick your distro

<table>
<tr><td width="50%">

**🅰️ Arch / EndeavourOS / Manjaro**
```bash
sudo pacman -S --needed git base-devel
```

</td><td width="50%">

**🅱️ Fedora**
```bash
sudo dnf install -y git gcc gcc-c++ make
```

</td></tr>
<tr><td colspan="2" align="center"><b>🅾 Debian / Ubuntu / Mint</b></td></tr>
<tr><td colspan="2">

```bash
sudo apt update && sudo apt install -y git build-essential curl pkg-config
```

</td></tr>
</table>

### Step 2 — Install the desktop pieces

<details open>
<summary><b>🅰️ Arch Linux</b> — click to expand</summary>

```bash
# An AUR helper is required for quickshell + swaylock-effects
sudo pacman -S --needed paru
paru -S --needed quickshell niri xwayland-satellite xdg-desktop-portal-gnome \
  swaybg swayidle swaylock-effects fuzzel cliphist wl-clipboard \
  alacritty tmux magick playerctl mpv yt-dlp tesseract flameshot \
  nmcli networkmanager bluez brightnessctl power-profiles-daemon \
  pipewire wireplumber thunar gvfs wlogout btop fastfetch
```

> Using EndeavourOS or Manjaro? You already have `yay` — use `yay` instead of `paru`.

</details>

<details>
<summary><b>🅱️ Fedora</b> — click to expand</summary>

```bash
sudo dnf copr enable -y yalter/niri      # niri compositor
sudo dnf copr enable -y errornointernet/quickshell  # Quickshell shell

sudo dnf install -y niri quickshell xwayland-satellite xdg-desktop-portal-gnome \
  swaybg swayidle swaylock fuzzel cliphist wl-clipboard \
  alacritty tmux ImageMagick playerctl mpv yt-dlp tesseract flameshot \
  NetworkManager nmstate bluez bluez-tools brightnessctl power-profiles-daemon \
  pipewire wireplumber thunar gvfs wlogout btop fastfetch
```

</details>

<details>
<summary><b>🅾 Debian / Ubuntu</b> — click to expand</summary>

```bash
# Quickshell is not in Debian stable — build it once (Qt6 + CMake)
sudo apt install -y qt6-base-dev qt6-declarative-dev cmake ninja-build pkg-config \
  libgl1-mesh-dev libxkbcommon-dev wayland-protocols libgbm-dev libgles2-mesa-dev

git clone https://github.com/quickshell-mirror/quickshell
cmake -S quickshell -B quickshell/build -G Ninja \
  -DCMAKE_BUILD_TYPE=Release -DNO_WAYLAND=OFF
cmake --build quickshell/build
sudo cmake --install quickshell/build
```

Then the rest (all in Debian repos):
```bash
sudo apt install -y niri swaybg swayidle swaylock swaylock-effects fuzzel cliphist \
  wl-clipboard alacritty tmux imagemagick playerctl mpv yt-dlp tesseract flameshot \
  network-manager bluez bluez-tools brightnessctl power-profiles-daemon \
  pipewire wireplumber thunar gvfs btop fastfetch
```

> [!NOTE]
> If `niri` or `swaylock-effects` aren't in your Debian suite, see
> [Troubleshooting](#-troubleshooting) for the pacstall / source-build route.

</details>

### Step 3 — Install this desktop (30 seconds)

> [!WARNING]
> **Clone into `~/niri-setup` exactly** — this is the safest path and matches what the
> config expects. (You *can* change it, but see [Relocating the repo](#relocating-the-repo).)

```bash
git clone https://github.com/tahmidtameem2017/My-Linux-Setup.git ~/niri-setup
cd ~/niri-setup
```

**Now run the installer for your distro — this matters:**

<table>
<tr><td width="50%">

**🅰️ Arch** — installs everything itself:
```bash
./setup.sh
```

</td><td width="50%">

**🅱️ Fedora / 🅾 Debian** — you already installed the
packages in Step 2, so skip the
package step:
```bash
./setup.sh --skip-install
```

</td></tr>
</table>

> [!IMPORTANT]
> **Why the flag?** `setup.sh` without `--skip-install` calls `pacman` to install
> packages. On Fedora or Debian that command doesn't exist, so the script stops
> immediately. Passing `--skip-install` tells it *"packages are already done, just
> wire up the config"* — which is exactly right, because Step 2 already installed them.

Either way, `setup.sh` will:
1. Symlink your tmux + Alacritty configs
2. Generate the theme files from the active palette
3. Attempt to link the niri config (see the caveat below)

<details open>
<summary><b>⚠️ Three manual fixes the installer does NOT do — required on every distro</b></summary>

These are genuine gaps in `setup.sh`. **Skip them and you get a broken or empty
desktop.** They are not optional.

**① Copy the whole niri config, don't just symlink `config.kdl`**

`setup.sh` only links `config.kdl`, but that file `include`s 10 more files
(`input.kdl`, `layout.kdl`, `binds.kdl`, …). niri resolves includes **relative to
the symlink's own directory**, so a lone symlink fails validation:

```
error parsing KDL
╰─▶ failed to read included config from ".../input.kdl": No such file
```

Copy every file instead — this is what a working install actually looks like:

```bash
mkdir -p ~/.config/niri
cp ~/niri-setup/niri/*.kdl ~/.config/niri/
niri validate            # must print nothing
```

> After this, the repo is **not** live-editable — re-copy after editing, or symlink
> each file individually instead:
> ```bash
> for f in ~/niri-setup/niri/*.kdl; do ln -sfn "$f" ~/.config/niri/; done
> ```

**② Switch the session to the Quickshell shell**

A fresh clone ships `spawn-at-startup.kdl` that is **byte-identical to the Waybar
variant** — it starts `waybar` + `dunst`, *not* the Quickshell shell this project is
built around. Flip it explicitly:

```bash
~/niri-setup/scripts/switch-shell.sh quickshell
```

**③ Create the quickshell config symlink**

Without it there is **no bar and no popups**:

```bash
mkdir -p ~/.config/quickshell
ln -sfn ~/niri-setup/quickshell/sunset ~/.config/quickshell/sunset
```

</details>

<details>
<summary><b>🔑 Fixing the polkit agent path (needed off-Arch)</b></summary>

`spawn-at-startup.kdl` starts the polkit agent from the **Arch-only** absolute path
`/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1`. `setup.sh` rewrites only
`$NIRICONF`, so on Fedora/Debian this never resolves and password prompts silently
never appear. Point it at the real binary:

```bash
# find the correct one for your distro
ls /usr/libexec/polkit-gnome-authentication-agent-1 2>/dev/null \
  || ls /usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1 2>/dev/null
```

Then edit the `polkit-gnome` line in `~/.config/niri/spawn-at-startup.kdl` with the
path that exists, and run `niri msg action load-config-file`.

</details>

### Step 4 — Make it yours

This setup ships with **my personal defaults** baked in — they will not match yours.
Change them:

```bash
cd ~/niri-setup

# see every knob currently set
bash scripts/wallpaper-process.sh get

# change them (setmany validates everything before writing)
bash scripts/wallpaper-process.sh setmany INTERVAL 30 DOWNSCALE 1920x1080

# pick your wallpaper folder, then set one
bash scripts/wallpaper.sh set ~/Pictures/Wallpapers/<your-file>

# turn on auto-theming so the palette follows every wallpaper change
bash scripts/wallpaper-process.sh set AUTOSTART true
```

| Default | Where it's set | Change with |
| :-- | :-- | :-- |
| Wallpaper folder `~/Pictures/Wallpapers` | `.state/wallpaper-process.conf` | `scripts/wallpaper-process.sh` |
| Rotation interval, downscale, format, quality | same file | `wallpaper-process.sh setmany` |
| Theme palette | `quickshell/sunset/services/Theme.qml` | `Mod+Alt+Shift+T` editor, or `qs -c sunset ipc call themes set <name>` |
| City / timezone (clock, weather, lock screen) | weather + OS state | `WeatherService` / system timezone |
| Idle timeout (~10m) | `scripts/change-idle-time.sh` | `change-idle-time.sh` |
| Power profile (balanced) | `scripts/change-power-profile.sh` | `change-power-profile.sh` |
| tmux prefix `C-b` | `tmux/tmux.conf` | edit + `tmux source-file` |
| Browser Brave, files Thunar | `niri/binds.kdl` | edit + re-copy (see the fixes above) |
| Window opacity / floating rules | `niri/rules.kdl` | edit + re-copy |

### Step 5 — Log in

1. **Log out** of your current desktop.
2. At the login screen, pick **niri** as your session.
3. Log back in.

**🎉 You now have the Sunset desktop.**

First things to try:

| Shortcut | Try this |
| :-- | :-- |
| <kbd>Super</kbd>+<kbd>Enter</kbd> | Open a terminal |
| <kbd>Alt</kbd>+<kbd>Space</kbd> | Open the launcher — start typing |
| <kbd>Mod</kbd>+<kbd>Alt</kbd>+<kbd>T</kbd> | Change the theme (live!) |
| <kbd>Mod</kbd>+<kbd>Ctrl</kbd>+<kbd>W</kbd> | Pick a new wallpaper (auto-themes) |

---

## 🤖 AI-Guided Installation

> **My recommendation: use [opencode](https://opencode.ai).** It's free, open source,
> and its model catalogue includes several **genuinely free models** — so you can run
> this whole install without burning through a paid subscription's usage limits.
>
> Pick a free model with `/models` inside opencode. Good picks for this task:
>
> | Model | Model ID | Why |
> | :-- | :-- | :-- |
> | **Muse Spark 1.3** | `opencode/muse-spark-1.3-contributor-free` | Best all-rounder for multi-step install work |
> | **Space Bunny** | `opencode/space-bunny-free` | 1M-token context, zero-retention, strong at code |
> | **Fledge Alpha** | `opencode/fledge-alpha-free` | Solid general-purpose fallback |
>
> ```bash
> # install opencode (free, open source):
> curl -fsSL https://opencode.ai/install | bash
> ```
>
> Then, **inside the opencode TUI**, type `/models` and pick one of the free models
> above. Any agent works though — Claude Code, Codex, Cursor, Cline, Aider — so use
> whatever you already have. The prompts below are self-contained either way.

> [!NOTE]
> Free models are listed as *"free for a limited time"* by OpenCode, and a few
> (**Muse Spark 1.3 Contributor**, **Fledge Alpha**) train on your prompts during
> that period. **Space Bunny** and **LongCat** are explicitly **zero-retention**. Use
> the free ones for this install; nothing here contains anything secret.
>
> **Before you start:** back up anything you care about. This install rewrites
> `~/.config/niri/` and installs system packages.

### How to use

1. Open your coding agent in a directory you control (e.g. `~`).
2. Copy the entire block for your distro below and paste it as your first message.
3. The agent will ask before anything needing `sudo`.
4. At the end it prints a verification report and a personalised cheat-sheet.

<details>
<summary><b>🅰️ Arch Linux · EndeavourOS · Manjaro</b></summary>

````text
You are installing AND personalising the "Sunset Niri" desktop environment on Arch
Linux (or EndeavourOS/Manjaro).
Repository: https://github.com/tahmidtameem2017/My-Linux-Setup

You have permission to run shell commands, edit files, and manage packages. Work
AUTONOMOUSLY through every phase below. Verify each step by actually running the
verification command — never assume a command worked. When something fails, read the
error, find the ROOT CAUSE, fix it, and re-verify. Only interrupt me for (a) sudo
passwords, (b) a choice only I can make (city, timezone, wallpaper folder,
default apps — Phase 6f), or (c) a destructive action.

PHASE 0 — ENVIRONMENT AUDIT
  cat /etc/os-release | head -3; uname -r
  command -v paru yay aura trizen            # AUR helper present?
  command -v niri quickshell swaybg          # already installed?
  ls /dev/dri/                               # GPU render nodes
  systemctl is-enabled sddm lightdm gdm 2>/dev/null   # display manager
Report a short ENVIRONMENT summary. Missing pieces are expected on a fresh box.

PHASE 1 — PACKAGES
Ensure an AUR helper exists (paru preferred; yay on EndeavourOS/Manjaro; install
gum too, since setup.sh needs it). Then install, reporting any that fail and
continuing past them:
  quickshell niri xwayland-satellite xdg-desktop-portal-gnome swaybg swayidle
  swaylock-effects fuzzel cliphist wl-clipboard alacritty tmux magick playerctl
  mpv yt-dlp tesseract flameshot networkmanager bluez brightnessctl
  power-profiles-daemon pipewire wireplumber thunar gvfs wlogout btop fastfetch
Also ensure fonts: ttf-jetbrains-mono-nerd ttf-ubuntu-mono-nerd noto-fonts-cjk.
Verify: niri --version; quickshell --version.

PHASE 2 — CLONE + RUN setup.sh
  git clone https://github.com/tahmidtameem2017/My-Linux-Setup.git ~/niri-setup
  cd ~/niri-setup && ./setup.sh
On Arch plain ./setup.sh is correct — it installs packages via the AUR helper too.
If prompted "niri config exists, overwrite? (Y/n)" answer Y. A failure from the
final `niri validate` inside setup.sh is EXPECTED until Phase 3 — continue.

PHASE 3 — CRITICAL FIXES (this repo is not a clean-install script; all five apply)
FIX 0 — REWRITE THE HARDCODED PATHS (do this FIRST, before anything else).
  This repo was written on a machine whose username was "me", so ~150 paths are
  hardcoded as /home/me/niri-setup. If YOUR username is not "me", EVERY one of them
  is wrong and the desktop will be badly broken — scripts not found, wallpaper
  failing, sudo rules pointing at a nonexistent file.
  First, find out where I ACTUALLY cloned the repo (do not assume ~/niri-setup —
  ask me if it is not there). Let REPO be that path. Then:
    cd "$REPO"
    echo "current user: $(whoami) | repo: $REPO"
    grep -rl '/home/me/niri-setup' --exclude-dir=.git . \
      | xargs -r sed -i "s|/home/me/niri-setup|$REPO|g"
    sed -i "s|\bme ALL|$(whoami) ALL|g" scripts/sudoers-cpu 2>/dev/null
    grep -rIo '/home/me/niri-setup' --exclude-dir=.git . | wc -l   # must print 0
  Confirm the count is 0 before continuing. If you deliberately keep the repo at
  /home/me/niri-setup then there is nothing to rewrite — say so and skip.
  NOTE: this makes the repo user-specific. Tell me that re-cloning or moving it
  means re-running this rewrite.
FIX 1 — install ALL niri config files.
  setup.sh only symlinks config.kdl, but it `include`s ~10 more .kdl files and niri
  resolves includes relative to the symlink directory. A lone symlink fails with
  "failed to read included config from .../input.kdl".
    mkdir -p ~/.config/niri
    cp ~/niri-setup/niri/*.kdl ~/.config/niri/
  (If I prefer the repo to stay live-editable, symlink each file individually:
    for f in ~/niri-setup/niri/*.kdl; do ln -sfn "$f" ~/.config/niri/; done
   Both validate; tell me which you used and how to re-sync after edits.)
FIX 2 — switch the session to the Quickshell shell.
  A fresh clone's spawn-at-startup.kdl is byte-identical to the Waybar variant, so it
  would start waybar+dunst instead of this project's shell.
    ~/niri-setup/scripts/switch-shell.sh quickshell
FIX 3 — create the shell config symlink (setup.sh never does this).
    mkdir -p ~/.config/quickshell
    ln -sfn ~/niri-setup/quickshell/sunset ~/.config/quickshell/sunset
  Without it there is no bar and no popups.
FIX 4 — enable the Quickshell keybinds.
  The live config.kdl does not include binds-quickshell.kdl, leaving ~15 shell
  shortcuts (theme picker, wifi, now playing, dictation...) dead.
    grep -q binds-quickshell ~/.config/niri/config.kdl || \
      echo 'include "binds-quickshell.kdl"' >> ~/.config/niri/config.kdl
    niri validate

PHASE 4 — HARDWARE PROFILE + PRIVILEGED EXTRAS (ask before each sudo)
FIRST, detect my hardware profile — this changes what you install:
  ls /sys/class/power_supply/ 2>/dev/null | grep -i bat   # a battery?
  upower -e 2>/dev/null | grep -i bat
If a battery IS present, this is a laptop: SKIP step (b) below entirely (it pins
the CPU to performance and would flatten the battery), and tell me I skipped it and
why. Also mention that BatteryWidget in the bar appears automatically once a battery
is detected, and needs no config change.
Offer the rest one at a time, explaining the benefit, and let me decline:
  a) Login theme:  sudo ~/niri-setup/sddm/install.sh   (Sunset SDDM theme;
     preview first with: sddm-greeter --test-mode --theme ~/niri-setup/sddm/sunset)
  b) CPU governor — BATTERY-LESS MACHINES ONLY. The repo ships scripts/sudoers-cpu
     and scripts/50-cpu-freq.rules but BOTH HARDCODE the username "me" and the path
     /home/me/niri-setup. Do NOT install them as-is. Generate correct copies instead:
       sed "s/^me ALL/$(whoami) ALL/; s|/home/me/niri-setup|$HOME/niri-setup|g" \
         ~/niri-setup/scripts/sudoers-cpu > /tmp/cpu-freq
       (then: sudo install -m 440 /tmp/cpu-freq /etc/sudoers.d/cpu-freq
             sudo visudo -c  # must parse cleanly)
     Same substitution for scripts/50-cpu-freq.rules into
     /etc/polkit-1/rules.d/50-cpu-freq.rules. ALWAYS run `sudo visudo -c` afterwards —
     a malformed sudoers file can lock me out. If it does not parse, remove it
     immediately.
     Explain: cpu-permanent.sh pins every core to performance/2.4GHz and bypasses
     battery throttling. Correct for a mains-powered machine with no battery (which
     is what this setup was built on); WRONG for a laptop with a real battery.
     Also note it is Intel-cpufreq specific — on AMD, or any machine without
     /sys/devices/system/cpu/cpu*/cpufreq, it silently does nothing.

  c) Touchpad: confirm niri/input.kdl already enables tap, natural-scroll and
     drag-lock. If I have a trackpad and want more, point me at the Gestures wiki
     rather than guessing at gesture names.

PHASE 5 — VERIFY (run each; report PASS/FAIL)
  niri validate                                  # expect "config is valid"
  ls -l ~/.config/quickshell/sunset              # expect symlink -> .../sunset
  diff -q ~/niri-setup/niri/spawn-quickshell.kdl ~/.config/niri/spawn-at-startup.kdl \
    && echo "PASS: quickshell session live"
  grep -q 'QS_ICON_THEME=Colloid quickshell -c sunset' ~/.config/niri/spawn-at-startup.kdl \
    && echo "PASS: shell auto-starts"
  ls ~/.config/niri/*.kdl | wc -l                # expect >= 10
  timeout 8 quickshell -c sunset 2>&1 | head -20   # expect NO fatal QML errors
    (benign warning: "another handler is registered for target X" — ignore)
  python3 -m unittest discover -s ~/niri-setup/scripts -p 'test_*.py' 2>&1 | tail -3

PHASE 6 — ONBOARDING (personalise it; ask me for choices)
  3. Defaults and identity — DO NOT SKIP. This setup ships with the original
     author's personal defaults baked in. Replace every one of these with mine:
       a) Wallpaper directory (default: ~/Pictures/Wallpapers) and the rotation
          knobs — interval, downscale, format, JPEG quality, PNG compression,
          canvas colour, and whether wallust auto-theming runs:
            ~/niri-setup/scripts/wallpaper-process.sh get
            ~/niri-setup/scripts/wallpaper-process.sh setmany INTERVAL 30 DOWNSCALE 1920x1080
          Explain what each knob does before changing it. setmany validates every
          pair first and refuses the whole write if any value is invalid.
       b) Theme palette — list the 15 available and let me pick a permanent default:
            qs -c sunset ipc call themes set <name>
          Explain that auto-theming ("auto on") is what makes the palette follow my
          wallpaper; picking a fixed palette turns auto off by design.
       c) City / timezone — drives the clock, weather popup and lock screen.
       d) Idle timeout and power profile (shipped defaults: ~10m idle, balanced):
            ~/niri-setup/scripts/change-idle-time.sh
            ~/niri-setup/scripts/change-power-profile.sh
       e) Terminal font/size and tmux behaviour (default prefix is C-b):
            ~/niri-setup/tmux/tmux.conf   # behaviour only — colours are generated
       f) Default apps — ASK ME FOR EACH ONE, never assume: browser,
          file manager, terminal, AND the settings app (the one most
          often forgotten). Shipped defaults: Brave browser, Thunar
          files, GNOME Settings. The settings app is GNOME Settings
          (gnome-control-center) only because that is the desktop this
          repo was built on — ASK which settings app I want: GNOME,
          KDE (systemsettings6), COSMIC (cosmic-settings), XFCE
          (xfce4-settings-manager), or another. If the answer is NOT
          GNOME: install it, then repoint EVERY place that calls it —
            scripts/gnome-settings.sh   the exec line, the
                                       XDG_CURRENT_DESKTOP value, and
                                       drop the gtk-nocsd LD_PRELOAD
                                       if the app is not GTK
            niri/binds.kdl              Mod+Shift+I (Network panel),
                                       Mod+Shift+P (all settings)
            niri/binds-quickshell.kdl   Mod+Alt+S
            quickshell/sunset/components/Launcher.qml
                                       the "Settings" control row
                                       (gnomeSettingsScript property)
          For browser/files/terminal, change the matching binds in
          niri/binds.kdl and tell me the app-id to use in niri/rules.kdl.
     For EVERY value you change, print a before/after table so I can see exactly what
     differs from the shipped defaults.
  4. Keybindings: ask for the 5 things I do most (open browser, screenshot, music,
     terminal, clipboard), add them to niri/binds.kdl or binds-quickshell.kdl, then
       cp ~/niri-setup/niri/*.kdl ~/.config/niri/
       niri validate && niri msg action load-config-file
  5. Startup apps: show me ~/.config/niri/spawn-at-startup.kdl and let me add/remove.
  6. Rollback safety net: document that
       ~/niri-setup/scripts/switch-shell.sh waybar
     reverts to the classic Waybar+dunst shell, and
       ~/niri-setup/scripts/rollback-to-waybar.sh
     is the emergency path. Tell me how to re-enter niri from a TTY (`niri-session`).
PHASE 7 — FINAL REPORT
Print:
  - Verification table (every Phase 5 check with PASS/FAIL)
  - Packages that failed and why
  - Which niri-config sync method I chose (copy vs per-file symlink)
  - Exactly what to do at the login screen: log out, choose "niri", log back in
  - A personalised cheat-sheet of MY most useful shortcuts
  - Where to edit what:
      keybindings  -> niri/binds.kdl + niri/binds-quickshell.kdl
      colours      -> quickshell/sunset/services/Theme.qml (or the palette editor)
      bar layout   -> quickshell/sunset/components/Bar.qml
      wallpaper    -> scripts/wallpaper-process.sh
      window rules -> niri/rules.kdl
    and remind me that after editing niri/*.kdl I must re-copy to ~/.config/niri/
    and run `niri validate && niri msg action load-config-file`.
````

</details>

<details>
<summary><b>🅱️ Fedora</b></summary>

````text
You are installing AND personalising the "Sunset Niri" desktop environment on Fedora.
Repository: https://github.com/tahmidtameem2017/My-Linux-Setup

You have permission to run shell commands, edit files, and manage packages. Work
AUTONOMOUSLY through every phase below. Verify each step by actually running the
verification command — never assume a command worked. When something fails, read the
error, find the ROOT CAUSE, fix it, and re-verify. Only interrupt me for (a) sudo
passwords, (b) a choice only I can make (city, timezone, wallpaper folder,
default apps — Phase 6f), or (c) a destructive action.

*** READ THIS FIRST — setup.sh IS ARCH-ONLY ***
setup.sh calls `pacman`. On Fedora it dies instantly with
"[ERROR] missing dependency: gum". You MUST run `./setup.sh --skip-install`
AFTER installing packages yourself via dnf. Never run plain ./setup.sh here.

PHASE 0 — ENVIRONMENT AUDIT
  cat /etc/os-release | head -3; uname -r
  command -v niri quickshell 2>/dev/null
  ls /dev/dri/                                  # GPU render nodes
  rpm -q NetworkManager bluez pipewire 2>/dev/null
  systemctl is-enabled sddm 2>/dev/null
Report an ENVIRONMENT summary. Missing pieces are expected on a fresh box.

PHASE 1 — REPOS + PACKAGES
Ask before sudo, then:
  sudo dnf copr enable -y yalter/niri                 # niri
  sudo dnf copr enable -y errornointernet/quickshell # Quickshell
If a COPR has no build for my Fedora version, say so and fall back to building
Quickshell from source (Qt6 + CMake + Ninja) and report exactly what you did.
Then install, reporting failures and continuing:
  sudo dnf install -y niri quickshell xwayland-satellite
  xdg-desktop-portal-gnome swaybg swayidle swaylock fuzzel cliphist wl-clipboard
  alacritty tmux ImageMagick playerctl mpv yt-dlp tesseract flameshot
  NetworkManager bluez bluez-tools brightnessctl power-profiles-daemon
  pipewire wireplumber thunar gvfs wlogout btop fastfetch
Fonts: google-jetbrains-mono-nerd-fonts google-ubuntu-mono-nerd-fonts
       google-noto-sans-cjk-fonts
Verify: niri --version; quickshell --version.

PHASE 2 — CLONE + RUN setup.sh (WITH THE FLAG)
  git clone https://github.com/tahmidtameem2017/My-Linux-Setup.git ~/niri-setup
  cd ~/niri-setup && ./setup.sh --skip-install

PHASE 3 — CRITICAL FIXES (all five apply)
FIX 0 — REWRITE THE HARDCODED PATHS (do this FIRST, before anything else).
  This repo was written on a machine whose username was "me", so ~150 paths are
  hardcoded as /home/me/niri-setup. If MY username is not "me", EVERY one of them
  is wrong and the desktop will be badly broken — scripts not found, wallpaper
  failing, sudo rules pointing at a nonexistent file.
  First, find out where I ACTUALLY cloned the repo (do not assume ~/niri-setup —
  ask me if it is not there). Let REPO be that path. Then:
    cd "$REPO"
    echo "current user: $(whoami) | repo: $REPO"
    grep -rl '/home/me/niri-setup' --exclude-dir=.git . \
      | xargs -r sed -i "s|/home/me/niri-setup|$REPO|g"
    sed -i "s|\bme ALL|$(whoami) ALL|g" scripts/sudoers-cpu 2>/dev/null
    grep -rIo '/home/me/niri-setup' --exclude-dir=.git . | wc -l   # must print 0
  Confirm the count is 0 before continuing. If you deliberately keep the repo at
  /home/me/niri-setup then there is nothing to rewrite — say so and skip.
  NOTE: this makes the repo user-specific. Tell me that re-cloning or moving it
  means re-running this rewrite.
FIX 1 — install ALL niri config files.
  setup.sh only symlinks config.kdl, which `include`s ~10 more .kdl files; niri
  resolves includes relative to the symlink directory, so a lone symlink fails.
    mkdir -p ~/.config/niri
    cp ~/niri-setup/niri/*.kdl ~/.config/niri/
  (Or per-file symlinks if I want the repo live-editable:
    for f in ~/niri-setup/niri/*.kdl; do ln -sfn "$f" ~/.config/niri/; done)
FIX 2 — switch the session to the Quickshell shell.
    ~/niri-setup/scripts/switch-shell.sh quickshell
FIX 3 — create the shell config symlink.
    mkdir -p ~/.config/quickshell
    ln -sfn ~/niri-setup/quickshell/sunset ~/.config/quickshell/sunset
FIX 4 — enable the Quickshell keybinds.
    grep -q binds-quickshell ~/.config/niri/config.kdl || \
      echo 'include "binds-quickshell.kdl"' >> ~/.config/niri/config.kdl
    niri validate

PHASE 4 — HARDWARE PROFILE, POLKIT PATH FIX + PRIVILEGED EXTRAS
FIX 5 — the polkit agent. spawn-at-startup.kdl hardcodes the Arch-only path
  /usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1, and setup.sh rewrites
  only $NIRICONF, so password dialogs (mounting disks, suspend) never appear.
  Find the real binary and rewrite that line:
    P=$(command -v polkit-gnome-authentication-agent-1 || \
        ls /usr/libexec/polkit-gnome-authentication-agent-1 2>/dev/null)
    sed -i "s|/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1|$P|" \
      ~/.config/niri/spawn-at-startup.kdl
FIRST, detect my hardware profile — this changes what you install:
  ls /sys/class/power_supply/ 2>/dev/null | grep -i bat
If a battery IS present, this is a laptop: SKIP the CPU-governor extra (b) entirely
(it pins the CPU to performance and would flatten the battery), and tell me you
skipped it and why. BatteryWidget then appears in the bar automatically — no config
change is needed.
Offer the remaining OPTIONAL extras one at a time, letting me decline:
  a) Login theme: sudo ~/niri-setup/sddm/install.sh
     (preview: sddm-greeter --test-mode --theme ~/niri-setup/sddm/sunset)
  b) CPU governor: the shipped scripts/sudoers-cpu and scripts/50-cpu-freq.rules
     HARDCODE the username "me" and /home/me/niri-setup. Never install as-is —
     generate correct copies for me:
       sed "s/^me ALL/$(whoami) ALL/; s|/home/me/niri-setup|$HOME/niri-setup|g" \
         ~/niri-setup/scripts/sudoers-cpu > /tmp/cpu-freq
       sudo install -m 440 /tmp/cpu-freq /etc/sudoers.d/cpu-freq
       sudo visudo -c        # MUST parse; if not, sudo rm the file at once
     Same substitution into /etc/polkit-1/rules.d/50-cpu-freq.rules.
     Warn me this pins every core to performance/2.4GHz and bypasses battery
     throttling. Correct for a mains-powered machine with NO battery (what this setup
     was built on); wrong for a laptop. Also Intel-cpufreq specific — on AMD, or any
     machine without /sys/devices/system/cpu/cpu*/cpufreq, it silently does nothing.

PHASE 5 — VERIFY (run each; report PASS/FAIL)
  niri validate                                   # expect "config is valid"
  ls -l ~/.config/quickshell/sunset               # expect symlink present
  diff -q ~/niri-setup/niri/spawn-quickshell.kdl ~/.config/niri/spawn-at-startup.kdl \
    && echo "PASS: quickshell session live"
  ls /usr/libexec/polkit-gnome-authentication-agent-1 \
    && echo "PASS: polkit agent exists"
  ls ~/.config/niri/*.kdl | wc -l                 # expect >= 10
  timeout 8 quickshell -c sunset 2>&1 | head -20   # expect NO fatal QML errors
    ("another handler is registered for target X" is BENIGN — ignore it)
  python3 -m unittest discover -s ~/niri-setup/scripts -p 'test_*.py' 2>&1 | tail -3

PHASE 6 — ONBOARDING (personalise it; ask me for choices)
  3. Defaults and identity — DO NOT SKIP. This setup ships with the original
     author's personal defaults baked in. Replace every one of these with mine:
       a) Wallpaper directory (default: ~/Pictures/Wallpapers) and the rotation
          knobs — interval, downscale, format, JPEG quality, PNG compression,
          canvas colour, and whether wallust auto-theming runs:
            ~/niri-setup/scripts/wallpaper-process.sh get
            ~/niri-setup/scripts/wallpaper-process.sh setmany INTERVAL 30 DOWNSCALE 1920x1080
          Explain what each knob does before changing it. setmany validates every
          pair first and refuses the whole write if any value is invalid.
       b) Theme palette — list the 15 available and let me pick a permanent default:
            qs -c sunset ipc call themes set <name>
          Explain that auto-theming ("auto on") is what makes the palette follow my
          wallpaper; picking a fixed palette turns auto off by design.
       c) City / timezone — drives the clock, weather popup and lock screen.
       d) Idle timeout and power profile (shipped defaults: ~10m idle, balanced):
            ~/niri-setup/scripts/change-idle-time.sh
            ~/niri-setup/scripts/change-power-profile.sh
       e) Terminal font/size and tmux behaviour (default prefix is C-b):
            ~/niri-setup/tmux/tmux.conf   # behaviour only — colours are generated
       f) Default apps — ASK ME FOR EACH ONE, never assume: browser,
          file manager, terminal, AND the settings app (the one most
          often forgotten). Shipped defaults: Brave browser, Thunar
          files, GNOME Settings. The settings app is GNOME Settings
          (gnome-control-center) only because that is the desktop this
          repo was built on — ASK which settings app I want: GNOME,
          KDE (systemsettings6), COSMIC (cosmic-settings), XFCE
          (xfce4-settings-manager), or another. If the answer is NOT
          GNOME: install it, then repoint EVERY place that calls it —
            scripts/gnome-settings.sh   the exec line, the
                                       XDG_CURRENT_DESKTOP value, and
                                       drop the gtk-nocsd LD_PRELOAD
                                       if the app is not GTK
            niri/binds.kdl              Mod+Shift+I (Network panel),
                                       Mod+Shift+P (all settings)
            niri/binds-quickshell.kdl   Mod+Alt+S
            quickshell/sunset/components/Launcher.qml
                                       the "Settings" control row
                                       (gnomeSettingsScript property)
          For browser/files/terminal, change the matching binds in
          niri/binds.kdl and tell me the app-id to use in niri/rules.kdl.
     For EVERY value you change, print a before/after table so I can see exactly what
     differs from the shipped defaults.
  4. Keybindings: ask for the 5 things I do most (open browser, screenshot, music,
     terminal, clipboard), add them to niri/binds.kdl or binds-quickshell.kdl, then
       cp ~/niri-setup/niri/*.kdl ~/.config/niri/
       niri validate && niri msg action load-config-file
  5. Startup apps: show me ~/.config/niri/spawn-at-startup.kdl and let me add/remove.
  6. Rollback safety net: document that
       ~/niri-setup/scripts/switch-shell.sh waybar
     reverts to the classic Waybar+dunst shell, and
       ~/niri-setup/scripts/rollback-to-waybar.sh
     is the emergency path. Tell me how to re-enter niri from a TTY (`niri-session`).
PHASE 7 — FINAL REPORT
Print:
  - Verification table (every Phase 5 check with PASS/FAIL)
  - Packages/COPRs that failed and why
  - Which Quickshell install method you used
  - Which niri-config sync method I chose
  - Exactly what to do at the login screen: log out, choose "niri", log back in
  - A personalised cheat-sheet of MY most useful shortcuts
  - Where to edit what:
      keybindings  -> niri/binds.kdl + niri/binds-quickshell.kdl
      colours      -> quickshell/sunset/services/Theme.qml (or the palette editor)
      bar layout   -> quickshell/sunset/components/Bar.qml
      wallpaper    -> scripts/wallpaper-process.sh
      window rules -> niri/rules.kdl
    and remind me that after editing niri/*.kdl I must re-copy to ~/.config/niri/
    and run `niri validate && niri msg action load-config-file`.
````

</details>

<details>
<summary><b>🅾 Debian · Ubuntu · Mint · Pop!_OS</b></summary>

````text
You are installing AND personalising the "Sunset Niri" desktop environment on Debian
(or Ubuntu/Mint/Pop!_OS).
Repository: https://github.com/tahmidtameem2017/My-Linux-Setup

You have permission to run shell commands, edit files, and manage packages. Work
AUTONOMOUSLY through every phase below. Verify each step by actually running the
verification command — never assume a command worked. When something fails, read the
error, find the ROOT CAUSE, fix it, and re-verify. Only interrupt me for (a) sudo
passwords, (b) a choice only I can make (city, timezone, wallpaper folder,
default apps — Phase 6f), or (c) a destructive action.

*** READ THIS FIRST — setup.sh IS ARCH-ONLY ***
setup.sh calls `pacman`. On Debian it dies instantly with
"[ERROR] missing dependency: gum". You MUST run `./setup.sh --skip-install`
AFTER installing packages yourself via apt. Never run plain ./setup.sh here.

*** HARDEST PART — QUICKSHELL ON DEBIAN ***
Quickshell is often NOT packaged for Debian stable. Try in this order and report
which method you used:
  1. pacstall:
       sudo bash -c "$(wget -q https://pacstall.dev/q/install -O -)"
       pacstall -S quickshell          # and the niri pacscript if niri is missing
  2. A trusted prebuilt .deb from a Debian niri packaging project (verify the source).
  3. Build from source:
       sudo apt install -y qt6-base-dev qt6-declarative-dev cmake ninja-build
         pkg-config libgl1-mesh-dev libxkbcommon-dev wayland-protocols
         libgbm-dev libgles2-mesa-dev
       git clone https://github.com/quickshell-mirror/quickshell
       cmake -S quickshell -B quickshell/build -G Ninja -DCMAKE_BUILD_TYPE=Release
       cmake --build quickshell/build && sudo cmake --install quickshell/build
Verify `quickshell --version` before continuing. If niri or swaylock-effects are also
unpackaged, use pacstall or build them, and report what you did.

PHASE 0 — ENVIRONMENT AUDIT
  cat /etc/os-release | head -3; uname -r
  command -v niri quickshell 2>/dev/null
  ls /dev/dri/                                  # GPU render nodes
  dpkg -l | grep -E 'network-manager|bluez|pipewire' | head
  systemctl is-enabled sddm lightdm gdm 2>/dev/null
Report an ENVIRONMENT summary.

PHASE 1 — PACKAGES
  sudo apt update
  sudo apt install -y niri swaybg swayidle swaylock swaylock-effects fuzzel
    cliphist wl-clipboard alacritty tmux imagemagick playerctl mpv yt-dlp
    tesseract flameshot network-manager bluez bluez-tools brightnessctl
    power-profiles-daemon pipewire wireplumber thunar gvfs btop fastfetch
Continue past individual failures and report each one. Then install Quickshell using
the ladder above. Fonts:
  sudo apt install -y fonts-jetbrains-mono fonts-noto-cjk

PHASE 2 — CLONE + RUN setup.sh (WITH THE FLAG)
  git clone https://github.com/tahmidtameem2017/My-Linux-Setup.git ~/niri-setup
  cd ~/niri-setup && ./setup.sh --skip-install

PHASE 3 — CRITICAL FIXES (all five apply)
FIX 0 — REWRITE THE HARDCODED PATHS (do this FIRST, before anything else).
  This repo was written on a machine whose username was "me", so ~150 paths are
  hardcoded as /home/me/niri-setup. If MY username is not "me", EVERY one of them
  is wrong and the desktop will be badly broken — scripts not found, wallpaper
  failing, sudo rules pointing at a nonexistent file.
  First, find out where I ACTUALLY cloned the repo (do not assume ~/niri-setup —
  ask me if it is not there). Let REPO be that path. Then:
    cd "$REPO"
    echo "current user: $(whoami) | repo: $REPO"
    grep -rl '/home/me/niri-setup' --exclude-dir=.git . \
      | xargs -r sed -i "s|/home/me/niri-setup|$REPO|g"
    sed -i "s|\bme ALL|$(whoami) ALL|g" scripts/sudoers-cpu 2>/dev/null
    grep -rIo '/home/me/niri-setup' --exclude-dir=.git . | wc -l   # must print 0
  Confirm the count is 0 before continuing. If you deliberately keep the repo at
  /home/me/niri-setup then there is nothing to rewrite — say so and skip.
  NOTE: this makes the repo user-specific. Tell me that re-cloning or moving it
  means re-running this rewrite.
FIX 1 — install ALL niri config files.
  setup.sh only symlinks config.kdl, which `include`s ~10 more .kdl files; niri
  resolves includes relative to the symlink directory, so a lone symlink fails.
    mkdir -p ~/.config/niri
    cp ~/niri-setup/niri/*.kdl ~/.config/niri/
  (Or per-file symlinks if I want the repo live-editable:
    for f in ~/niri-setup/niri/*.kdl; do ln -sfn "$f" ~/.config/niri/; done)
FIX 2 — switch the session to the Quickshell shell.
    ~/niri-setup/scripts/switch-shell.sh quickshell
FIX 3 — create the shell config symlink.
    mkdir -p ~/.config/quickshell
    ln -sfn ~/niri-setup/quickshell/sunset ~/.config/quickshell/sunset
FIX 4 — enable the Quickshell keybinds.
    grep -q binds-quickshell ~/.config/niri/config.kdl || \
      echo 'include "binds-quickshell.kdl"' >> ~/.config/niri/config.kdl
    niri validate

PHASE 4 — HARDWARE PROFILE, POLKIT PATH FIX + PRIVILEGED EXTRAS
FIX 5 — the polkit agent. spawn-at-startup.kdl hardcodes the Arch-only path
  /usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1; on Debian it is usually
  under /usr/libexec. Find it and rewrite that line:
    P=$(command -v polkit-gnome-authentication-agent-1 || \
        ls /usr/libexec/polkit-gnome-authentication-agent-1 2>/dev/null)
    sed -i "s|/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1|$P|" \
      ~/.config/niri/spawn-at-startup.kdl
FIRST, detect my hardware profile — this changes what you install:
  ls /sys/class/power_supply/ 2>/dev/null | grep -i bat
If a battery IS present, this is a laptop: SKIP the CPU-governor extra (b) entirely
(it pins the CPU to performance and would flatten the battery), and tell me you
skipped it and why. BatteryWidget then appears in the bar automatically — no config
change is needed.
Offer the remaining OPTIONAL extras one at a time, letting me decline:
  a) Login theme: sudo ~/niri-setup/sddm/install.sh
     (preview: sddm-greeter --test-mode --theme ~/niri-setup/sddm/sunset)
  b) CPU governor: the shipped scripts/sudoers-cpu and scripts/50-cpu-freq.rules
     HARDCODE the username "me" and /home/me/niri-setup. Never install as-is —
     generate correct copies for me:
       sed "s/^me ALL/$(whoami) ALL/; s|/home/me/niri-setup|$HOME/niri-setup|g" \
         ~/niri-setup/scripts/sudoers-cpu > /tmp/cpu-freq
       sudo install -m 440 /tmp/cpu-freq /etc/sudoers.d/cpu-freq
       sudo visudo -c        # MUST parse; if not, sudo rm the file immediately
     Same substitution into /etc/polkit-1/rules.d/50-cpu-freq.rules.
     Warn me this pins every core to performance/2.4GHz and bypasses battery
     throttling. Correct for a mains-powered machine with NO battery (what this setup
     was built on); wrong for a laptop. Also Intel-cpufreq specific — on AMD, or any
     machine without /sys/devices/system/cpu/cpu*/cpufreq, it silently does nothing.

PHASE 5 — VERIFY (run each; report PASS/FAIL)
  niri validate                                   # expect "config is valid"
  ls -l ~/.config/quickshell/sunset               # expect symlink present
  diff -q ~/niri-setup/niri/spawn-quickshell.kdl ~/.config/niri/spawn-at-startup.kdl \
    && echo "PASS: quickshell session live"
  ls ~/.config/niri/*.kdl | wc -l                 # expect >= 10
  timeout 8 quickshell -c sunset 2>&1 | head -20   # expect NO fatal QML errors
    ("another handler is registered for target X" is BENIGN — ignore it)
  python3 -m unittest discover -s ~/niri-setup/scripts -p 'test_*.py' 2>&1 | tail -3

PHASE 6 — ONBOARDING (personalise it; ask me for choices)
  3. Defaults and identity — DO NOT SKIP. This setup ships with the original
     author's personal defaults baked in. Replace every one of these with mine:
       a) Wallpaper directory (default: ~/Pictures/Wallpapers) and the rotation
          knobs — interval, downscale, format, JPEG quality, PNG compression,
          canvas colour, and whether wallust auto-theming runs:
            ~/niri-setup/scripts/wallpaper-process.sh get
            ~/niri-setup/scripts/wallpaper-process.sh setmany INTERVAL 30 DOWNSCALE 1920x1080
          Explain what each knob does before changing it. setmany validates every
          pair first and refuses the whole write if any value is invalid.
       b) Theme palette — list the 15 available and let me pick a permanent default:
            qs -c sunset ipc call themes set <name>
          Explain that auto-theming ("auto on") is what makes the palette follow my
          wallpaper; picking a fixed palette turns auto off by design.
       c) City / timezone — drives the clock, weather popup and lock screen.
       d) Idle timeout and power profile (shipped defaults: ~10m idle, balanced):
            ~/niri-setup/scripts/change-idle-time.sh
            ~/niri-setup/scripts/change-power-profile.sh
       e) Terminal font/size and tmux behaviour (default prefix is C-b):
            ~/niri-setup/tmux/tmux.conf   # behaviour only — colours are generated
       f) Default apps — ASK ME FOR EACH ONE, never assume: browser,
          file manager, terminal, AND the settings app (the one most
          often forgotten). Shipped defaults: Brave browser, Thunar
          files, GNOME Settings. The settings app is GNOME Settings
          (gnome-control-center) only because that is the desktop this
          repo was built on — ASK which settings app I want: GNOME,
          KDE (systemsettings6), COSMIC (cosmic-settings), XFCE
          (xfce4-settings-manager), or another. If the answer is NOT
          GNOME: install it, then repoint EVERY place that calls it —
            scripts/gnome-settings.sh   the exec line, the
                                       XDG_CURRENT_DESKTOP value, and
                                       drop the gtk-nocsd LD_PRELOAD
                                       if the app is not GTK
            niri/binds.kdl              Mod+Shift+I (Network panel),
                                       Mod+Shift+P (all settings)
            niri/binds-quickshell.kdl   Mod+Alt+S
            quickshell/sunset/components/Launcher.qml
                                       the "Settings" control row
                                       (gnomeSettingsScript property)
          For browser/files/terminal, change the matching binds in
          niri/binds.kdl and tell me the app-id to use in niri/rules.kdl.
     For EVERY value you change, print a before/after table so I can see exactly what
     differs from the shipped defaults.
  4. Keybindings: ask for the 5 things I do most (open browser, screenshot, music,
     terminal, clipboard), add them to niri/binds.kdl or binds-quickshell.kdl, then
       cp ~/niri-setup/niri/*.kdl ~/.config/niri/
       niri validate && niri msg action load-config-file
  5. Startup apps: show me ~/.config/niri/spawn-at-startup.kdl and let me add/remove.
  6. Rollback safety net: document that
       ~/niri-setup/scripts/switch-shell.sh waybar
     reverts to the classic Waybar+dunst shell, and
       ~/niri-setup/scripts/rollback-to-waybar.sh
     is the emergency path. Tell me how to re-enter niri from a TTY (`niri-session`).
PHASE 7 — FINAL REPORT
Print:
  - Verification table (every Phase 5 check with PASS/FAIL)
  - Which Quickshell install method you used, and anything you had to build
  - Packages that failed and why
  - Which niri-config sync method I chose
  - Exactly what to do at the login screen: log out, choose "niri", log back in
  - A personalised cheat-sheet of MY most useful shortcuts
  - Where to edit what:
      keybindings  -> niri/binds.kdl + niri/binds-quickshell.kdl
      colours      -> quickshell/sunset/services/Theme.qml (or the palette editor)
      bar layout   -> quickshell/sunset/components/Bar.qml
      wallpaper    -> scripts/wallpaper-process.sh
      window rules -> niri/rules.kdl
    and remind me that after editing niri/*.kdl I must re-copy to ~/.config/niri/
    and run `niri validate && niri msg action load-config-file`.
````

</details>

---

## 🛠️ AI-Guided Updates

Installed it already? These are the prompts for **changing** the desktop later
— the same one-paste style as the install prompts above, and just as
self-contained. Paste one as your agent's first message in `~/niri-setup`.

Each one ends with the same rule, and it is the whole point:

```bash
python3 scripts/changelog.py verify     # must exit 0
python3 -m unittest discover -s scripts -p 'test_*.py'
```

`scripts/changelog.py` owns the one number a human cannot keep straight:
`help/index.html` declares a row count per section, and adding a shortcut row
without bumping it makes the in-app help quietly lie about itself. It was
already wrong before the tool existed — the launcher section claimed 59 rows
while holding 62.

### A · Fix this machine's install

*Paths rewritten, hardware guessed, defaults replaced with yours. No new
features.* This is the one most people actually need.

````text
You are repairing MY installed copy of the "Sunset Niri" desktop so it matches
MY machine, not the machine it was written on. Repository is cloned at the path
below — find it, do not assume.

PHASE 1 — AUDIT. Do not change anything yet. Run and report:
  whoami; echo $HOME; niri --version; quickshell --version
  git -C "$REPO" remote -v | head -2; git -C "$REPO" status --short | head -20
  ls -l ~/.config/niri/ ~/.config/quickshell/ 2>&1 | head -20
  diff -q "$REPO/niri/config.kdl" ~/.config/niri/config.kdl
  ls /dev/dri/; lspci | grep -iE 'vga|3d|display'
  free -h | head -2; nproc

PHASE 2 — THE USERNAME BUG (do this first, it breaks everything else).
  ~150 paths are hardcoded as /home/me/niri-setup. If my username is not "me",
  every one is wrong. Find every occurrence:
    grep -rn '/home/me' "$REPO" --exclude-dir=.git --exclude-dir=node_modules
  Replace with the real path. Do NOT rewrite occurrences inside comments that
  are quoting example output, and do NOT touch test fixtures that use /home/me
  as an arbitrary string. Then verify nothing is left that matters:
    grep -rn '/home/me' "$REPO/niri" "$REPO/quickshell" "$REPO/waybar" "$REPO/scripts"

PHASE 3 — MAKE THE REPO THE SOURCE OF TRUTH.
  ~/.config/niri/*.kdl are COPIES, not symlinks, so they drift silently. Report
  every file that differs between the repo and ~/.config/niri. For each, show me
  the diff and ask whether the live copy or the repo copy is correct — do NOT
  overwrite either until I answer. ~/.config/quickshell/sunset SHOULD be a
  symlink into the repo; if it is a real directory, say so and stop.

PHASE 4 — HARDWARE-SPECIFIC DEFAULTS.
  brave/brave-flags.conf was tuned for an Intel Broadwell iGPU with 7.6 GB of
  RAM. Read it, read my GPU from PHASE 1, and propose flags for MY hardware.
  Explain each change in one line. Apply nothing until I approve.

PHASE 5 — PERSONAL DEFAULTS. Ask me, then write the answers:
  wallpaper folder · rotation interval · idle timeout · power profile ·
  city (for weather) · timezone · browser · file manager · terminal
  Write them with scripts/wallpaper-process.sh (setmany validates before
  writing), never by hand-editing .state/wallpaper-process.conf.

PHASE 6 — VERIFY. Actually run these and report PASS/FAIL for each:
  niri validate
  python3 scripts/changelog.py verify
  python3 -m unittest discover -s scripts -p 'test_*.py'
  bash -n on every scripts/*.sh
  quickshell -c sunset --version
Then print: what you changed, what you deliberately left alone, and anything
still hardcoded for the original machine.
````

### B · Make it yours (look, don't touch)

*Walks you through the settings by showing you the current values first. No
surprises, and it never edits without asking.*

````text
You are helping me PERSONALISE the "Sunset Niri" desktop in this repo. Show me
what is currently set BEFORE changing anything, and ask before every write.

STEP 1 — READ AND REPORT. Print a table of the current value and where it lives
for each of these, read from the real files (do not guess):
  bash scripts/wallpaper-process.sh get
  grep -A3 'focus-ring' niri/layout.kdl
  grep -E 'opacity|corner' niri/rules.kdl | head
  grep -cE '^\s*\w+\s*\{' niri/binds.kdl niri/binds-quickshell.kdl
  qs -c sunset ipc call themes list 2>/dev/null || true

STEP 2 — WHAT LOOKS WRONG. Point out defaults that are clearly somebody else's:
  the wallpaper folder path, a rotation interval I would find too fast, a theme
  that clashes with my wallpaper, gaps or opacity I would want different. Offer
  a concrete alternative for each and wait for me to pick.

STEP 3 — APPLY ONLY WHAT I PICKED. Write it with the repo's own tool for that
  setting (wallpaper-process.sh for wallpaper knobs), never by editing the
  state file directly. After any niri/*.kdl edit:
    cp niri/<file> ~/.config/niri/<file>
    niri validate && niri msg action load-config-file
  After any QML edit, remind me: Mod+Shift+Q restarts the shell, no niri reload
  needed, because ~/.config/quickshell/sunset is a symlink into the repo.

STEP 4 — PREVIEW THE THEMES. List the palettes from services/Theme.qml with
  their bg/accent hex values, and offer to switch one at a time so I can see it:
    qs -c sunset ipc call themes set <name>
  Remind me that a wallpaper-derived palette follows the wallpaper while
  auto-theming is on, and that picking a fixed theme turns auto off.

Finish by printing a short cheat-sheet of the shortcuts I actually use.
````

### C · Add a feature (read the repo's own rules first)

*The one to use when you want a new keybinding, popup or launcher row. Teaches
the agent the traps this repo has already paid for.*

````text
You are adding ONE feature to the "Sunset Niri" desktop in this repo. Read these
files BEFORE writing any code — they document traps that are not visible in the
source and have each caused a silent, hard-to-debug failure:
  AGENTS.md      (the full list; read the sections your feature touches)
  scripts/CHANGELOG-AGENT.md  (how docs must be updated alongside code)
  taste.md       (design tokens and popup conventions)

HARD RULES FOR THIS REPO, all of them load-bearing:
  - NEVER hardcode a colour. Use a token from quickshell/sunset/services/Theme.qml
    (bg, text, dim, accent, onAccent...). A literal hex silently stops
    following the palette, which is exactly how 8 files once got stuck.
  - NEVER write the output of scripts/sync-external-theme.py into git. It owns
    tmux/theme.conf, alacritty/*.toml, help/theme.css, niri/layout.kdl. Edit the
    *.in template instead.
  - A file the shell watches must be written IN PLACE, never tmp-then-rename:
    FileView watches the inode, and os.replace() kills the watch silently.
  - An IPC verb is not automatically the method it forwards to. shell.qml does
    loader.item[fn], so a function that exists only inside an IpcHandler throws
    and does nothing. Any new verb needs BOTH the shim in shell.qml and a root
    method on the popup.
  - If a keybinding moves or changes meaning, grep every doc for the old chord:
      grep -rn 'Ctrl+Space' README.md help/index.html AGENTS.md
  - LazyLoader.active is ASYNCHRONOUS. You cannot activate and call in the same
    tick; park the call and replay it in onItemChanged.

WORKING STEPS
  1. Restate the feature in one sentence, and name the key it answers to. Ask me
     to confirm before writing code.
  2. Find the existing pattern it most resembles and copy that shape exactly.
  3. Write the code. Comment only the non-obvious WHY — this repo's comments
     explain decisions and traps, not syntax.
  4. If it changes behaviour that a test can pin, write the test by LIFTING the
     real function out of the QML and running it under node, the way
     scripts/test_launcher_row_menu.py and test_icon_colors.py already do.
     Reimplementing the logic in the test is worthless — it tests the copy.
  5. Update the docs: new chord into niri/binds*.kdl AND the README keybinding
     tables AND help/index.html. Then run
       python3 scripts/changelog.py counts --write
       python3 scripts/changelog.py verify
  6. Add a row to the README's "Screenshots still to capture" table if the
     feature is visual. A feature nobody can picture does not get believed.

BEFORE YOU REPORT DONE
  niri validate
  python3 scripts/changelog.py verify
  python3 -m unittest discover -s scripts -p 'test_*.py'
Then tell me: what you added, which existing pattern you copied, what you
deliberately did NOT do, and which of my HARD RULES applied to this change.
````

> The full brief these three prompts are condensed from lives in
> **`scripts/CHANGELOG-AGENT.md`** — read it directly if you want the agent to
> follow the checklist step by step rather than paraphrasing it.

---

## ✨ Features

### 🎨 Dynamic, wallpaper-aware theming
- **10 hand-crafted palettes** (`sunset`, `tokyo-night`, `catppuccin-mocha`, `gruvbox-dark`,
  `everforest`, `kanagawa-wave`, `nord`, `rose-pine`, `dracula`, `matte-black`)
  **+ 4 auto-generated from your wallpaper** + 1 custom = **15 themes** in the picker.
- **11 color tokens** (`bg`, `text`, `accent`, `dim`, …) pushed to **tmux, Alacritty,
  niri, and the help pages** — everything re-themes live when you change wallpaper.
- **Legibility is enforced, not requested**: every palette is contrast-checked against
  WCAG floors before it's allowed to render.
- **A visual palette editor** (`Mod+Alt+Shift+T`) — edit all 11 tokens with live preview.

### 🧩 A real desktop shell (not just a bar)
- **16 lazy-loaded popups**, built on first use and torn down when closed: Launcher,
  Calendar+Pomodoro, Clipboard, Wallpaper picker, Wallpaper menu, Theme picker,
  Now Playing, Quick Settings, Wi-Fi, Bluetooth, Power, Volume mixer, Weather,
  Screenshot actions, Sessions, and the fun Whip overlay.
- **Memory-smart**: popups are torn down 600 ms after close (~208 MB → ~177 MB at rest).

### ⌨️ Thoughtful everyday details
- **Instant web search** (<kbd>Ctrl</kbd>+<kbd>Space</kbd>) — the launcher opens already in `@` mode; type, <kbd>Enter</kbd>, and it opens in your browser. All eight site shortcuts still work.
- **A right-click menu on every launcher row** (<kbd>F10</kbd> too) — the items follow the row: an app gets Preview · Reveal · Terminal · Copy · Pin, a bookmark gets Rename · Delete. Each item names its keyboard twin, and a row is never offered something it cannot do.
- **Pin what you use** — pinned rows get their own section above Controls and survive a restart. A duplicate, not a move: Applications stays complete, and searching never shows the same app twice.
- **Search the highlighted site** (<kbd>Ctrl</kbd>+<kbd>Tab</kbd>) — fills in that site's shortcut, so you never have to remember which one goes with which site.
- **Offline voice dictation** with `whisrs` (whisper.cpp) — no cloud, no key.
- **Copy any file with `Ctrl+C`** in the launcher — text and pictures copy their contents, everything else copies the path.
- **A real bookmark manager in the launcher** (`%`) — import from any browser with favicons, delete with <kbd>Delete</kbd>, rename with `%rename`, and URL-only entries get real names.
- **Config Editor** — tune niri itself (gaps, focus ring, column width, opacity, corner radius, animations, touchpad, mouse) from the launcher; validated and hot-reloaded live.
- **Music**: download from a link, dedup, and play your whole library; MPRIS-aware.
- **On-demand performance monitor** (`Mod+Alt+P`) — a CPU · GPU · MEM · BAT
  pill in the bar's center island, hidden by default so the island stays just
  weather + clock; click the pill for `btop`.
- **Smart power**: idle daemon, power profiles, brightness OSD, mic-mute indicator.
- **Dropdown scratchpad terminal** (`Mod+`` ` ``).
- **Scrollable-tiling** at its finest: consume/expel columns, resize, float, workspaces.

---

## ⌨️ Keybindings

`Mod` = <kbd>Super</kbd>.

### Applications

| Keys | Action |
| :-- | :-- |
| <kbd>Mod</kbd>+<kbd>Enter</kbd> | Terminal |
| <kbd>Alt</kbd>+<kbd>Space</kbd> / <kbd>Mod</kbd>+<kbd>Ctrl</kbd>+<kbd>Enter</kbd> | Launcher |
| <kbd>Ctrl</kbd>+<kbd>Space</kbd> | Web search — opens the launcher already in `@` mode |
| <kbd>F10</kbd> / <kbd>Menu</kbd> / right-click | Menu for the highlighted launcher row |
| <kbd>Ctrl</kbd>+<kbd>Tab</kbd> | Search the highlighted site |
| <kbd>Mod</kbd>+<kbd>B</kbd> | Browser (Brave) |
| <kbd>Mod</kbd>+<kbd>E</kbd> | Files (Thunar) |
| <kbd>Mod</kbd>+<kbd>L</kbd> | Lock screen |
| <kbd>Mod</kbd>+<kbd>C</kbd> | Clipboard menu |
| <kbd>Mod</kbd>+<kbd>Shift</kbd>+<kbd>Q</kbd> | Restart the shell |

### Shell & popups (the fun ones)

| Keys | Action |
| :-- | :-- |
| <kbd>Mod</kbd>+<kbd>Alt</kbd>+<kbd>T</kbd> | Theme picker |
| <kbd>Mod</kbd>+<kbd>Alt</kbd>+<kbd>Shift</kbd>+<kbd>T</kbd> | Palette editor |
| <kbd>Mod</kbd>+<kbd>Alt</kbd>+<kbd>W</kbd> | Wallpaper menu |
| <kbd>Mod</kbd>+<kbd>Alt</kbd>+<kbd>F</kbd> | Wi-Fi card |
| <kbd>Mod</kbd>+<kbd>Alt</kbd>+<kbd>M</kbd> | Now Playing |
| <kbd>Mod</kbd>+<kbd>Alt</kbd>+<kbd>P</kbd> | Performance monitor (CPU · GPU · MEM · BAT pill) |
| <kbd>Mod</kbd>+<kbd>Shift</kbd>+<kbd>O</kbd> | Sessions editor |
| <kbd>Mod</kbd>+<kbd>Alt</kbd>+<kbd>D</kbd> | Voice dictation (toggle) |
| <kbd>Mod</kbd>+<kbd>Alt</kbd>+<kbd>Esc</kbd> | Dictation panic key |
| <kbd>Mod</kbd>+<kbd>Alt</kbd>+<kbd>S</kbd> | GNOME Settings |
| <kbd>Mod</kbd>+<kbd>Alt</kbd>+<kbd>H</kbd> | Help & Guide |

### Windows & columns

| Keys | Action |
| :-- | :-- |
| <kbd>Mod</kbd>+<kbd>Q</kbd> | Close window |
| <kbd>Mod</kbd>+<kbd>T</kbd> | Toggle floating |
| <kbd>Mod</kbd>+<kbd>M</kbd> | Maximize column |
| <kbd>Mod</kbd>+<kbd>F</kbd> | Fullscreen |
| <kbd>Mod</kbd>+<kbd>←</kbd>/<kbd>→</kbd> | Focus column |
| <kbd>Mod</kbd>+<kbd>Ctrl</kbd>+<kbd>←</kbd>/<kbd>→</kbd> | Move column |
| <kbd>Mod</kbd>+<kbd>Shift</kbd>+<kbd>←</kbd>/<kbd>→</kbd> | Resize column |
| <kbd>Mod</kbd>+<kbd>[</kbd> / <kbd>]</kbd> | Consume / expel window |

### Workspaces

| Keys | Action |
| :-- | :-- |
| <kbd>Mod</kbd>+<kbd>1</kbd>…<kbd>0</kbd> | Jump to workspace |
| <kbd>Mod</kbd>+<kbd>Ctrl</kbd>+<kbd>1</kbd>…<kbd>0</kbd> | Move column to workspace |
| <kbd>Mod</kbd>+<kbd>Page Up</kbd>/<kbd>Down</kbd> | Focus workspace |

### Screenshots & capture

| Keys | Action |
| :-- | :-- |
| <kbd>Mod</kbd>+<kbd>Shift</kbd>+<kbd>5</kbd> | Screenshot panel (all tools) |
| <kbd>Mod</kbd>+<kbd>Ctrl</kbd>+<kbd>S</kbd> | Region capture + OCR pill |
| <kbd>Mod</kbd>+<kbd>Shift</kbd>+<kbd>S</kbd> | Scrolling screenshot |
| <kbd>Mod</kbd>+<kbd>Shift</kbd>+<kbd>R</kbd> | Toggle screen recording |

---

## 🧪 Development & Validation

This repo ships a **202-test suite** guarding the theming and export logic:

```bash
python3 -m unittest discover -s scripts -p 'test_*.py'   # run the tests
niri validate                                            # check niri config syntax
qs -c sunset ipc call themes set sunset-orange           # switch palette live
bash scripts/palette.sh get                              # print the active 11 tokens
python3 scripts/sync-external-theme.py                   # regenerate tmux/alacritty/niri
```

---

## 🔧 Troubleshooting

<details>
<summary><b>❌ "[ERROR] missing dependency: gum" or setup.sh exits instantly</b></summary>

You're on **Fedora or Debian** and ran plain `./setup.sh`. Its package step calls
`pacman`, which only exists on Arch. Run it with the flag instead:

```bash
./setup.sh --skip-install
```

</details>

<details>
<summary><b>❌ Everything is black / no bar after logging in</b></summary>

Work through this list in order:

```bash
# 1. Is the quickshell config linked? (the #1 cause of an empty desktop)
ls -l ~/.config/quickshell/sunset

# 2. Is niri actually using this repo's config?
ls -l ~/.config/niri/config.kdl

# 3. Does niri accept the config?
niri validate

# 4. Is the shell running? Look for QML errors:
pkill quickshell; quickshell -c sunset 2>&1 | head -30
```

If step 4 prints a QML error, the most common cause on non-Arch systems is a
**missing dependency** — check the binary named in the error is installed.

</details>

<details>
<summary><b>❌ "Password required" prompts won't open / no polkit dialog</b></summary>

The config starts the polkit agent from an **Arch-specific absolute path**
(`/usr/lib/polkit-gnome/...`). On Fedora and Debian the path differs, so the agent
never starts. Find yours and edit `niri/spawn-at-startup.kdl`:

```bash
# Fedora / Debian usually use libexec:
ls /usr/libexec/polkit-gnome-authentication-agent-1
```

Then replace the path on that line and reload: `niri msg action load-config-file`.

</details>

<details>
<summary><b>The bar is missing / nothing appears</b></summary>

Your `quickshell` symlink probably isn't set. This is the one thing `setup.sh` does
**not** create automatically:

```bash
mkdir -p ~/.config/quickshell
ln -sfn ~/niri-setup/quickshell/sunset ~/.config/quickshell/sunset
pkill quickshell; quickshell -c sunset &
```

Then check for errors: `quickshell -c sunset 2>&1 | head -30`.

</details>

<details>
<summary><b>"Niri config file exists — overwrite?"</b></summary>

That prompt is expected on a fresh install — it means niri already has a config. Answer
<kbd>Y</kbd> to use this one.

</details>

<details>
<summary><b>Nothing happens when I press a shortcut</b></summary>

1. Confirm you're logged into **niri**, not another session.
2. Check the config is linked: `ls -l ~/.config/niri/config.kdl`
3. Reload after manual edits: `niri msg action load-config-file`

</details>

<details>
<summary><b>Relocating the repo (advanced)</b></summary>

The config references the repo by absolute path in several places. If you clone
somewhere other than `~/niri-setup`, run `setup.sh` from the new location so the paths
get rewritten. **The safest option is to keep it at `~/niri-setup`.**

</details>

---

<a id="relocating-the-repo"></a>

### 📁 Relocating the repo

If you keep the repo anywhere other than `~/niri-setup`, rewrite the absolute paths
inside it once after cloning:

```bash
cd /path/to/your/niri-setup
grep -rl '/home/me/niri-setup' --exclude-dir=.git . \
  | xargs sed -i "s|/home/me/niri-setup|$PWD|g"
./setup.sh
```

Cloning to `~/niri-setup` makes this unnecessary — that's why Step 3 recommends it.

---

## 🙏 Credits & Acknowledgements

This project stands on the shoulders of a lot of people. Thank you to everyone who
built the tools this desktop is made of.

### This repository
- **[tahmidtameem2017](https://github.com/tahmidtameem2017)** — author and maintainer of
  this setup. What began as a stock `niri-setup` install was rebuilt from the ground up:
  the Waybar/dunst shell was replaced with a native Quickshell QML shell, a wallpaper-aware
  theme engine was built from scratch, and the install was made cross-distro.
- **[acaibowlz](https://github.com/acaibowlz)** *(aka **[@hengtseChou](https://github.com/hengtseChou)*
  *— hankthedev)* — creator of the original
  [`niri-setup`](https://github.com/acaibowlz/niri-setup) that this project started from,
  and author of the native Quickshell migration this build descends from. The KDL config
  layout, the Waybar theme, and much of the original design are their work — credited
  and deeply respected.

### The upstream tools this desktop is built on
A desktop is a team of open-source projects. In no particular order, with gratitude:

- **[niri](https://github.com/YaLTeR/niri)** — YaLTeR — the scrollable-tiling Wayland
  compositor at the heart of everything.
- **[Quickshell](https://quickshell.org/)** — the QtQuick shell toolkit powering the bar,
  popups, and toasts.
- **[Waybar](https://github.com/Alexays/Waybar)** · **[dunst](https://github.com/dunst-project/dunst)**
  · **[wlogout](https://github.com/ArtsyMacaw/wlogout)** · **[fuzzel](https://codeberg.org/dnkl/fuzzel)**
  — kept on disk as the rollback "gold" for the shell.
- **[Sway](https://github.com/swaywm/sway) project** — `swaybg`, `swayidle`, `swaylock`.
- **[Alacritty](https://github.com/alacritty/alacritty)** · **[tmux](https://github.com/tmux/tmux)**
  · **[starship](https://github.com/starship/starship)** — terminal stack.
- **[PipeWire](https://github.com/PipeWire/pipewire)** · **[playerctl](https://github.com/altdesktop/playerctl)**
  · **[wl-clipboard](https://github.com/bugaevc/wl-clipboard)** · **[cliphist](https://github.com/sentriz/cliphist)**
  — audio + clipboard plumbing.
- **[wallust](https://github.com/dwallust/wallust)** — the wallpaper palette extractor.
- **[Flameshot](https://flameshot.org/)** · **[Tesseract](https://github.com/tesseract-ocr/tesseract)**
  — screenshots and OCR.
- **[yt-dlp](https://github.com/yt-dlp/yt-dlp)** · **[mpv](https://github.com/mpv-player/mpv)**
  — the music pipeline.
- **[whisper.cpp](https://github.com/ggerganov/whisper.cpp)** — offline dictation engine.
- **[Colloid GTK theme](https://github.com/vinceliuice/Colloid-gtk-theme)** ·
  **[Colloid icons](https://github.com/vinceliuice/Colloid-icon-theme)** ·
  **[JetBrains Mono](https://github.com/JetBrains/JetBrainsMono)** · **[Nerd Fonts](https://github.com/ryanoasis/nerd-fonts)**
  — visual identity.
- **[SDDM](https://github.com/sddm/sddm)** · **[LightDM](https://github.com/grevutiu-gabriel/lightdm)**
  — login theming.

A full architectural reference lives in **[`AGENTS.md`](./AGENTS.md)** and the design
philosophy in **[`taste.md`](./taste.md)**. Read `AGENTS.md` if you ever plan to modify
the shell — it's remarkably detailed.

---

## 📄 License

[GPL-3.0](./LICENSE) — same license as the original `niri-setup`.