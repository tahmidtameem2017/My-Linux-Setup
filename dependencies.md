# dependencies.md — every external dependency in this repo

Exhaustive inventory of what a new machine needs to install so that **all** tools and
workflows in `niri-setup` work: the live quickshell shell, the waybar rollback session, every
`scripts/*.sh` workflow, the Python services, the tests, and the generated artefacts.

Each entry carries the file that justifies it, so you can verify rather than trust.
Anything marked **[not in setup.sh]** is a real gap — `setup.sh`'s `pkgs=()` list predates
the quickshell migration and does not cover it.

Verified against this machine (`command -v` / `pacman -Qi`, 2026-10-04).

---

## TL;DR — one install command

```bash
# 1. Native + AUR (paru/yay/aura/trizen), everything except the two -git / build-by-hand bits
paru -Syu --needed \
  niri xwayland-satellite niriswitcher \
  quickshell qt6-wayland qt6-declarative qt6-svg qt6-base qt6-tools \
  poppler-qt6 nodejs wallust lm_sensors udiskie bluez bluez-utils \
  swaybg swayidle swaylock-effects swww wlogout dunst waybar \
  fuzzel gum wl-clipboard pamixer brightnessctl \
  networkmanager wireguard-tools \
  power-profiles-daemon upower polkit-gnome \
  imagemagick yt-dlp mpv playerctl ffmpeg tesseract tesseract-data-eng \
  cliphist hyprpicker sushi wofi wf-recorder grim slurp \
  btop fastfetch starship jq curl alacritty kitty tmux thunar \
  thunar-volman gvfs tumbler xfce4-settings xfce4-power-manager \
  pavucontrol pwvucontrol

# 2. AUR
paru -S --needed gtk-nocsd-git flameshot-git     # gtk-nocsd used as AUR pkg here; fallback below

# 3. System groups (needed for hotplug / screen / audio)
sudo pacman -S --needed xf86-input-libinput libwacom

# 4. Hand-built (no package provides it)
build-gtk-nocsd() {   # https://codeberg.org/jbicha/GTK-NoCSD — builds with no sudo
  git clone --depth 1 https://codeberg.org/jbicha/GTK-NoCSD
  make -C GTK-NoCSD && sudo make -C GTK-NoCSD install
}
pipx install whisrs   # dictation daemon; binaries land in ~/.local/bin (see §3)

# 5. Fonts (all repo configs hardcode the Nerd Font family)
paru -S --needed ttf-jetbrains-mono-nerd otf-font-awesome noto-fonts-emoji
```

Then `./setup.sh` and `Mod+Shift+Q`.

Two non-negotiables that break silently:

- **`qt6-wayland`** — without it quickshell cannot map a `WlrLayerShell` surface, so the
  bar and every popup silently fail to appear. No error, no window.
- **`ttf-jetbrains-mono-nerd`** — the launcher renders Nerd Font *codepoints* as `Text`
  (`row.glyph` is `\uXXXX`, not an `assets/icons/` basename). Without the font those rows are
  empty boxes. It is also the tmux status glyph (`U+F02A`), the alacritty family, all six
  `fuzzel/*.ini`, `dunst/dunstrc` and `kitty/kitty.conf`.

---

## 1. Native packages (Arch)

### 1.1 Compositor, session, portal
| Package | Binary | Why |
| --- | --- | --- |
| `niri` | `niri` | compositor; `niri validate`, `niri msg action load-config-file`, `niri msg windows` (AGENTS.md "Window rule conventions") |
| `xwayland-satellite` | `xwayland-satellite` | XWayland for X11 apps; needed by Brave/GTK dialogs |
| `xdg-desktop-portal` + `-wlr` / `-gnome` | — | file chooser / screenshare portals (waybar session) |
| `niri` config validation | `niri validate` | `setup.sh` gates on it at the end |

### 1.2 Live shell (quickshell)
| Package | Binary | Why |
| --- | --- | --- |
| **`quickshell`** | `quickshell`, `qs` | the shell itself. Spawned as `QT_QPA_PLATFORM=wayland NIRI_SETUP_HOME=<repo> quickshell -c sunset`; `qs` is the IPC client used by `binds-quickshell.kdl` |
| **`qt6-wayland`** | — | **[not in setup.sh]** Qt's Wayland platform plugin. Without it quickshell cannot map a `WlrLayerShell` surface — the bar and every popup silently fail to appear |

Qt modules pulled in by the QML `import` list in §6 — install as one line:
`qt6-declarative qt6-svg qt6-wayland qt6-base`

**Do NOT hunt for `qt6-shapes` or `wayland-protocols`** — neither is a package here.
`QtQuick/Shapes` and `QtQuick/Pdf` live inside `qt6-declarative` + `poppler-qt6`, and
quickshell **bundles its own protocol XML internally** (verified: this machine has *no*
`/usr/share/wayland-protocols` and no `wlr-*.xml` on disk, yet the shell runs).
`wayland-protocols` is only worth installing if you run *other* clients that need it.

### 1.3 Wallpaper / idle / lock / login
| Package | Binary | Used by |
| --- | --- | --- |
| `swaybg` | `swaybg` | `scripts/wallpaper.sh`, `auto-wallpaper.sh`, `change-wallpaper.sh`; every `niri/spawn-*.kdl` |
| `swayidle` | `swayidle` | `scripts/swayidle.sh` (called by `change-idle-time.sh` and at startup) |
| **`swaylock-effects`** | `swaylock` | `scripts/swaylock.sh` — swaylock **1.8.1** specifically, because `swaylock` upstream ships no `--no-unlock-indicator` / arc reactions. See taste.md → Lock screen |
| `sddm` | `sddm`, `sddm-greeter` | **live** login manager on this machine; theme in `sddm/sunset` + `sddm/install.sh` |
| `lightdm` | — | `lightdm/` is an alternative theme dir, not installed |
| `swww` | `swww` | `waybar/` / `scripts/change-wallpaper*` alternate backend; not spawned by the live session |

### 1.4 Rollback shell (waybar session)
| Package | Binary | Used by |
| --- | --- | --- |
| `waybar` | `waybar` | `waybar/config`; spawned from `niri/spawn-waybar.kdl` and `rollback-to-waybar.sh` |
| `dunst` | `dunst` | `dunst/dunstrc`, spawned by `niri/spawn-waybar.kdl`. **Not in the live session** — quickshell `Toasts` owns `org.freedesktop.Notifications` |
| `wlogout` | `wlogout` | `wlogout/` kept for rollback; `scripts/wlogout.sh` |
| `python-gobject` / `python-pywayland` | — | `waybar/modules/window_info.py`, `waybar/scripts/clipboard-pick.py` (waybar session only) |

### 1.5 Launchers / menus
| Package | Binary | Why |
| --- | --- | --- |
| **`fuzzel`** | `fuzzel` | all six `fuzzel/*.ini`. **Unbound fallback** — every live menu is quickshell's `Launcher` |
| **`gum`** | `gum` | `setup.sh` **hard-fails without it** (`is_installed gum`); `scripts/change-wallpaper.sh`, `wallust-theme.sh` env vars, `gum choose` |
| `walker` | — | mentioned in AGENTS.md as rollback-only fallback; not referenced by any script |
| `hyprpicker` | `hyprpicker` | color picker (waybar session) |

### 1.6 Clipboard, screenshot, OCR, recording
| Package | Binary | Used by |
| --- | --- | --- |
| **`wl-clipboard`** | `wl-copy`, `wl-paste` | `spawn-at-startup.kdl` runs `wl-paste --watch cliphist store` + an image watcher; `screenshot.sh` wl-copies the capture; QML `ClipboardPopup` reads `wl-paste -t text` |
| **`cliphist`** | `cliphist` | clipboard history store. **32 refs** across scripts + `Launcher`/`ClipboardPopup` |
| **`tesseract`** + **`tesseract-data-eng`** | `tesseract` | `scripts/ocr.sh`, `ocr-latest.sh` (the `OCR` row of `CaptureBar`) |
| **`ffmpeg`** | `ffmpeg`, `ffprobe` | `scripts/record-screen.sh` (screen/video record), `download-track.sh` (post-processing), `music-dedup.sh` (tags via `ffprobe`) |
| **`grim`** + **`slurp`** | `grim`, `slurp` | `scroll-screenshot.sh` (scroll capture stitching) |
| `wf-recorder` | `wf-recorder` | legacy record backend referenced by `record-screen.sh` |
| **`flameshot-git`** | `flameshot` | **AUR.** AGENTS.md: *every capture row goes through `scripts/screenshot.sh`, never a bare `flameshot gui`* — the bare form skips the wl-copy + the OCR/Copy/Open/Delete pill |
| `swappy` | `swappy` | optional overlay for `wf-recorder` |
| `xdg-desktop-portal` | — | `gnome-screenshot` / portal capture path |

### 1.7 Audio
| Package | Binary | Used by |
| --- | --- | --- |
| **`pipewire`** + **`pipewire-pulse`** + **`wireplumber`** | — | the whole audio stack; `AudioService.qml` wraps `Quickshell.Services.Pipewire` |
| `pulseaudio-utils` | `wpctl` | `set-volume.sh`, `limit-volume.sh`, `waybar/modules/pulseaudio.jsonc`, bar `VolumeWidget` |
| **`pamixer`** | `pamixer` | quick volume/mute from binds |
| `pavucontrol` | `pavucontrol` | mixer GUI |
| `pwvucontrol` | `pwvucontrol` | PipeWire-native mixer (setup.sh) |

`pw-cli` / `pw-top` / `pw-dump` / `pactl` are also referenced (5 + 5 refs) for the
`dictation-reset.sh mic` verb and `waybar/modules/*`.

### 1.8 Network / Bluetooth
| Package | Binary | Used by |
| --- | --- | --- |
| **`networkmanager`** | `nmcli` | `WifiService.qml` (two-tier polling), `WifiPopup`, 13 script refs. **`nmcli` is mandatory** — the Wi-Fi card is a pure view over it |
| **`bluez`** + **`bluez-utils`** | `bluetoothctl` | `BluetoothPopup` runs `bluetoothctl --timeout 25 scan on` as a *held* process; `BluetoothService.qml` wraps `Quickshell.Bluetooth` (needs bluez + `quickshell` bluetooth bindings) |
| `wpa_supplicant` | — | WPA backend for NM (also used to check STA mode) |
| `wireguard-tools` | `wg` | VPNs live in GNOME Settings, not the shell |
| `nmtui` | `nmtui` | **removed from the shell** (AGENTS.md Wi-Fi section); `niri/rules.kdl` still has a legacy Alacritty-title rule |

**`nmcli -t` escape trap:** it escapes `:` as `\:`. Any parser splitting on a bare `":"`
truncates an SSID containing a colon. `WifiService.splitEscaped()` handles it.

### 1.9 Power, idle, input, session services
| Package | Binary | Used by |
| --- | --- | --- |
| **`power-profiles-daemon`** | `powerprofilesctl` | `scripts/change-power-profile.sh`, `QuickSettings`, `fuzzel/power-profile.ini` |
| **`upower`** | `upower` | `Quickshell.Services.UPower` → `BatteryWidget` |
| `xfce4-power-manager` / `xf86-power-manager` | — | legacy; the live battery pill reads UPower |
| `brightnessctl` | `brightnessctl` | QML brightness keys, `scripts/`, waybar `backlight.jsonc` |
| `acpi` | `acpi` | lid/suspend |
| **`udiskie`** | `udiskie` | `spawn-at-startup.kdl` line 1 — automount/power for removable media. **`[not in setup.sh]`** |
| `xdg-desktop-portal` | — | portals |
| `seatd` / `logind` | — | session mgmt (base) |
| `libinput`/`xf86-input-libinput` + `libwacom` | — | **[not in setup.sh]** tablet/stylus + proper input |

### 1.10 Images, media, files
| Package | Binary | Used by |
| --- | --- | --- |
| **`imagemagick`** | `magick`, `convert`, `identify` | `wallpaper.sh` (single pass + canvas colour), `swaylock-bg.sh` (lock image), `Launcher` FilesProvider thumbnails (`magick <path>[0]...`). **40 refs** — the heaviest single dep in the repo |
| **`yt-dlp`** | `yt-dlp` | `download-track.sh` (58 refs), NowPlaying download button |
| **`mpv`** | `mpv` | `play-library.sh` (`--loop-playlist=inf --audio-display=no`), Music Library |
| **`playerctl`** | `playerctl` | MPRIS: `MediaService.qml`, NowPlaying, `lock-info.sh`, `download-track.sh` (no title → read the bus) |
| **`thunar`** + **`thunar-volman`** + **`gvfs`** + **`tumbler`** | `thunar`, `tumblerd` | file manager + volumes + thumbnails. **`tumblerd` is what serves the launcher's image thumbnails** |
| `xdg-user-dirs`, `xdg-utils` | `xdg-open` | help/custom-theme browser windows |
| `p7zip`, `unzip`, `file-roller` | — | archive handling |

### 1.11 Terminal, shell, prompt
| Package | Binary | Why |
| --- | --- | --- |
| **`alacritty`** | `alacritty` | tiled profile (`alacritty/default.toml`, generated from `default.toml.in`) + floating profile (`float.toml`, generated from `float.toml.in`) |
| **`tmux`** | `tmux` | live terminal multiplexer; `tmux/tmux.conf` (behaviour only) + **generated** `tmux/tmux.conf` fragment `theme.conf`; `tmux/cheatsheet.sh`. Requires **tmux 3.7** (`pane-colours[]`, `choose-tree -w`, `resize-pane -Z`) |
| `kitty` | `kitty` | `kitty/kitty.conf` (alternate terminal, same Nerd Font family) |
| **`starship`** | `starship` | prompt |
| `fzf` | `fzf` | optional shell fuzzy find |
| `zsh` / `fish` | — | optional alt shell |

### 1.12 Browser (needed by several workflows)
| Item | Why |
| --- | --- |
| **`brave`** (this machine: `/opt/brave-bin/brave`) | `Mod+Alt+H` help → `scripts/open-help.sh` opens `help/index.html` in a Brave `--app` window; `Mod+Alt+Shift+T` → `scripts/custom-theme.sh` opens `help/custom-theme.html` in a Brave `--app` window on `127.0.0.7`. Also the PWA host for WhatsApp/YouTube (`niri/rules.kdl`) |
| `firefox` | referenced in scripts as a fallback browser |
| `chromium`/`google-chrome` | works identically; only the app-id strings in `niri/rules.kdl` change |

**Brave window rules** (AGENTS.md, `niri/rules.kdl`): `brave-127.0.0.7__-Default` (custom theme
editor), `brave-127.0.0.1__-Default` (legacy volume popup, 400x440), and the installed-PWA
shape `-<a-p>{32}-Default`. PWAs must be launched with **`--app=URL`, never `--app-id=`** —
the latter brings back Chromium's client-side titlebar strip, which niri deliberately does not
draw.

### 1.13 Fonts
| Package | Why |
| --- | --- |
| **`ttf-jetbrains-mono-nerd`** | **mandatory.** `alacritty/{default,float}.toml.in`, all six `fuzzel/*.ini`, `dunst/dunstrc`, `kitty/kitty.conf`, `waybar/style.css`, and the **launcher glyph column** (`row.glyph` = `\uXXXX` PUA codepoints rendered as `Text`) |
| `otf-font-awesome` / `nerd-fonts-complete` | alt glyph source; the icon *set* is `quickshell/sunset/assets/icons/*.svg` (stroke SVGs, palette-substituted) |
| `noto-fonts-emoji` | `emoji` glyphs in the launcher / toasts |
| `ttf-dejavu` | base monospace fallback |

`fc-match "JetBrainsMono Nerd Font"` must resolve **before** you judge any icon, glyph or
tmux status bar — this box resolves it to `JetBrainsMonoNerdFont-Regular.ttf`.

### 1.14 System libraries (no CLI surface, but hard requirements)
| Item | Why |
| --- | --- |
| **`qt6-declarative`, `qt6-svg`, `qt6-base`, `qt6-wayland`** | the QML engine behind every quickshell component (`QtQuick.Shapes` ships inside `qt6-declarative`) |
| **`libadwaita`, `gtk3`, `gtk4`** | GNOME Settings / GTK apps |
| **`pipewire`, `libpulse`** | audio |
| **`seatd`** | session |
| `pango`, `fontconfig` | text shaping for GTK/Qt (`pangoft2` is a *library* inside `pango`, not a package) |
| `alsa-utils` (`amixer`) | only needed to fix the ALSA capture gain at **100% / +30 dB** (see §9) |

---

## 2. AUR packages
| Package | Why |
| --- | --- |
| **`gtk-nocsd-git`** | `LD_PRELOAD=~/.local/lib/libgtk-nocsd.so.0` strips the headerbar from every GTK app (AGENTS.md "GTK apps run headerless"). `prefer-no-csd` in `misc.kdl` does **not** work — libadwaita ignores it |
| **`flameshot-git`** | the screenshot backend behind `scripts/screenshot.sh` |
| `niri` | Arch-native but newer on AUR; check `pacman -Qi niri` before assuming |
| AUR helper itself | `setup.sh` **exits** without one of `paru` / `yay` / `aura` / `trizen` |

`gtk-nocsd` is listed in `setup.sh` but on this machine the `.so` was **built by hand** into
`~/.local/lib/` (setup.sh does not build it). So: install `gtk-nocsd-git` **or** run the
upstream build — do not assume `setup.sh` did it.

---

## 3. Python dependencies

All Python in this repo uses the **system** interpreter. Two third-party modules only:

| Module | Used by | Package |
| --- | --- | --- |
| **`gi` / PyGObject** | `waybar/modules/window_info.py`, `waybar/scripts/clipboard-pick.py` (waybar session legacy) | `python-gobject` |
| **`pywayland`** | `scripts/clip-path-watcher.py` | `python-pywayland` |

Everything else is stdlib: `argparse, colorsys, ctypes, hashlib, json, math, os, pathlib, re,
secrets, shutil, signal, stat, struct, subprocess, sys, tempfile, threading, time, unittest,
urllib, warnings, wave, http`.

Plus the vendored in-repo modules (no install): `scripts/colorlib.py`, `scripts/wallust-palette.py`.

```bash
sudo pacman -S --needed python-gobject python-pywayland
```

### 3.1 `whisrs` — dictation (installed via pipx, not pacman)
AGENTS.md: *"Voice dictation is `whisrs`, NOT hand-rolled here."* `Mod+Alt+D` → `whisrs toggle`.

| Item | Detail |
| --- | --- |
| Install | `pipx install whisrs` → `~/.local/bin/whisrs`, `~/.local/bin/whisrsd` |
| Config | `~/.config/whisrs/config.toml` — **`~` is NOT expanded**; use absolute `model_path` or the daemon warns `model file not found` while still starting |
| Models | `~/.local/share/whisrs/models/*.bin` → symlinks into `~/.local/share/niri-setup/dictation/models/`: `ggml-base.en-q5_1.bin` (59 MB, default, ~7s for ~20s of speech), `ggml-small.en-q5_1.bin` (accuracy), `ggml-silero-v5.1.2.bin` (VAD) |
| Backend | **local whisper.cpp, CPU-only** (`whisper_backend_init_gpu: no GPU found`) — fine, CPU vs Vulkan measured within noise |
| Unit | `whisrs.service` (`systemctl --user`). Needs **absolute `ExecStart=%h/.local/bin/whisrsd`** (systemd PATH has no `~/.local/bin`, else 203/EXEC) **and `PassEnvironment=NIRI_SOCKET`** or window tracking silently degrades to the noop tracker. Carries **`TimeoutStopSec=5`** (systemd's 90s default blocks rung 2 on exactly the wedged process the panic key exists for) |
| Panic key | `Mod+Alt+Escape` → `scripts/dictation-reset.sh` (socket cancel → `systemctl --user restart` → SIGTERM → SIGKILL → report mic holders). Never `pkill` |
| Binary name safety | every signal is gated on **`argv[0]` basename equality** (`whisrsd`\|`whisrs`), never a substring of the whole cmdline — verified with a decoy |

---

## 4. External binaries invoked by scripts

Grouped by what needs them. `[not in setup.sh]` = gap.

### 4.1 Core / always
`bash`, `timeout`, `sh`, `sleep`, `mkdir`, `rm`, `cp`, `mv`, `ln`, `touch`, `chmod`, `stat`,
`readlink`, `realpath`, `mktemp`, `base64`, `date`, `find`, `grep`, `sed`, `awk`, `cut`, `tr`,
`sort`, `uniq`, `head`, `tail`, `wc`, `cmp`, `diff`, `xargs`, `setsid`, `kill`, `pgrep`,
`pkill`, `ps`, `sleep`, `true` — all `coreutils` / `findutils` / `grep` / `sed` / `gawk` / `util-linux`.
`sudo` for `cpu-*.sh` and the polkit rule.

### 4.2 Theming pipeline
| Binary | Where |
| --- | --- |
| `python3` | `sync-external-theme.py`, `sync-fastfetch-theme.py`, `wallust-palette.py`, `clean-url.py`, `colorlib.py` |
| **`wallust`** | `scripts/wallust-theme.sh` (4 palette families, one throwaway config dir each) |
| `jq` | 22 refs across theme JSON reads |
| `curl` | weather + geocoding (from QML), 12 refs |
| `node` | 21 refs — **`scripts/test_icon_colors.py` runs the real `Theme.qml` derivation functions under `node`** and fails on any 8-bit disagreement with `colorlib.neutral_icon()`. Install `nodejs` |
| `fc-match` / `fc-list` | font resolution checks |

### 4.3 Wallpaper workflow
`magick` (`wallpaper.sh` fast path + canvas sample; `swaylock-bg.sh` lock image),
`swaybg` (backgrounded — its stdio must go to `.state/swaybg.log`, or `wallpaper.sh … | grep` hangs),
`gum` (interactive picker), `wal`? no.

Knobs live in `.state/wallpaper-process.conf` via `wallpaper-process.sh get|set|setmany|reset|validate`:
`INTERVAL DOWNSCALE FORMAT JPEG_QUALITY PNG_COMPRESSION CANVAS_COLOR WALLUST POST_CMD AUTOSTART`.

### 4.4 Screenshots / OCR / recording
`flameshot` (via `screenshot.sh`), `grim`, `slurp`, `ffmpeg`, `ffprobe`, `tesseract`,
`wf-recorder`, `wl-copy`, `notify-send`, `pkill`.

The contract (AGENTS.md): `screenshot.sh region|window|screen` → `screenshots open <path>`;
`scroll-screenshot.sh` (bare = start/stop); `record-screen.sh toggle`. The `Print` family
deliberately **bypasses** these — niri's built-ins stay fast and silent.

### 4.5 Media / downloads
`yt-dlp`, `mpv`, `playerctl`, `ffmpeg`, `ffprobe`, `curl`, `md5sum` (dedup signatures),
`python3` (`run-yt-dlp.py` → `PR_SET_PDEATHSIG`), `pkill -f "mpv --force-window=no --audio-display=no"`.

### 4.6 Clipboard
`wl-copy`, `wl-paste`, `cliphist`, `python3` (`clipboard-offer.py`, `clip-path-watcher.py`),
`notify-send`, `xdg-open`, `magick` (image previews).

### 4.7 Power / CPU tuning
`powerprofilesctl`, `brightnessctl`, `sudo`, `systemctl --user`, plus plain
coreutils (`grep`, `awk`, `sed`). **No `cpupower`** — `cpu-performance.sh` / `cpu-permanent.sh`
write `/sys/devices/system/cpu/cpu*/cpufreq/scaling_governor` and
`.../energy_performance_preference` directly.
Plus `scripts/sudoers-cpu` → `/etc/sudoers.d/cpu-freq` (chmod 440) and
`scripts/50-cpu-freq.rules` → `/etc/polkit-1/rules.d/` — `setup.sh` installs both.

### 4.8 Session switching / rollback
`quickshell`, `qs`, `pkill quickshell`, `waybar`, `dunst`, `wlogout`, `swayidle`, `niri msg`,
`systemctl --user import-environment`.

### 4.9 Misc referenced
`iw`, `upower`, `acpi`, `lspci`, `lsusb`, `nvidia-smi`, `gdbus`, `busctl`, `dbus-send`,
`ip`, `ping`, `journalctl`, `systemctl`, `gnome-control-center`, `xdg-open`, `xdg-desktop-portal`,
`pacman`, `paru`/`yay`/`aura`/`trizen` (update checks), `cargo`, `git`, `wget`, `bat`, `nautilus`,
`notify-send`, `pavucontrol`, `pwvucontrol`, `sushi` (`scripts/sushi-preview.sh` — OCR preview),
`firefox`, `brave`, `btop` (Perf pill → floating Alacritty), `alacritty`, `fastfetch`,
`ripgrep`/`fd`/`bat`/`zoxide`/`exa` (optional shell tooling).

---

## 5. External binaries invoked from QML

`Process { command: [...] }` across `quickshell/sunset/`:

`bash`, `cat`, `mkdir`, `nmcli` (×6 — radio/dev/conn/list/rescan/up/down/delete),
`bluetoothctl` (held `scan on`), `brightnessctl` (get/max/set/-m),
`powerprofilesctl set`, `cliphist list`, `wl-paste -t text --no-newline`,
`curl` (open-meteo forecast + geocoding), `magick` (thumbnails), `pkill swayidle`,
`python3` (`sync-external-theme.py --palette`, `sync-fastfetch-theme.py`),
`sh` (`command -v sushi`), plus every `scripts/*.sh` invoked by path
(`perf-stats.sh`, `record-screen.sh`, `screenshot.sh`, `auto-wallpaper.sh`,
`manage-wallpaper.sh`, `music-lib.sh`, `download-track.sh`).

Two process-contract traps: the music-library `command` uses `root.stepScript` /
`root.setScript`, and `screenshot.sh capture <name>` is the `CaptureBar` entry point.

---

## 6. QML imports

```
QtQuick, QtQuick.Controls, QtQuick.Layouts, QtQuick.Shapes,
QtQuick.Pdf, Qt.labs.folderlistmodel,
Quickshell, Quickshell.Io, Quickshell.Wayland, Quickshell.Widgets,
Quickshell.Bluetooth,
Quickshell.Services.Mpris, Quickshell.Services.Notifications,
Quickshell.Services.Pipewire, Quickshell.Services.UPower,
qs.components, qs.services   (local)
```

| Import | Needs |
| --- | --- |
| `QtQuick.Pdf` | **`poppler-qt6`** at runtime — **`[not in setup.sh]`** (launcher `PdfPreview.qml` / `PreviewPane.qml`) |
| `Quickshell.Bluetooth` | `bluez` running + a working adapter |
| `Quickshell.Services.UPower` | `upower` daemon |
| `Quickshell.Services.Pipewire` | `pipewire` + `wireplumber` |
| `Quickshell.Wayland` | `qt6-wayland` (quickshell bundles its own protocol XML) |
| `Qt.labs.folderlistmodel` | core Qt |

`Quickshell` singletons used: `Quickshell.env`, `Quickshell.execDetached`,
`Quickshell.iconPath`.

**QML load order trap:** a single syntax error anywhere in `shell.qml` or its children makes
quickshell refuse to start **with no useful log line**. Validate with
`quickshell -c sunset` in a terminal after any edit.

---

## 7. Files / paths that must exist

### 7.1 Generated (do NOT create by hand)
| Path | Produced by |
| --- | --- |
| `alacritty/default.toml`, `alacritty/float.toml` | `scripts/sync-external-theme.py` from `alacritty/*.toml.in`. **gitignored.** `setup.sh` symlinks `~/.config/alacritty/alacritty.toml` → `default.toml` |
| `tmux/theme.conf` | same script. `tmux/tmux.conf` `source-file -q`s it |
| `niri/layout.kdl` | rewritten **in place** in both repo + live copy (focus ring, tab indicator) |
| `help/theme.css` | same script |
| `quickshell/sunset/assets/icons/theme/<fp>/` | palette-substituted SVG copies |
| `~/.local/share/niri-setup/icon-dir.txt` | icon directory pointer — **must be written IN PLACE**, never staged+renamed |
| `~/.local/share/niri-setup/active-theme.json` | `Theme.qml` publishes the live palette |
| `~/.config/fastfetch/config.jsonc` | `scripts/sync-fastfetch-theme.py` |
| `niri/wallpapers.kdl`, `wallpapers/workspace.*` | runtime, gitignored |
| `~/.config/quickshell/sunset` → `<repo>/quickshell/sunset` | **symlink, done manually — `setup.sh` does NOT do it** |

### 7.2 Runtime state
`~/.local/share/niri-setup/` (active-theme.json, icon-dir.txt, weather-location.json,
dictation/models/, fastfetch-config.jsonc) · `~/.cache/niri-setup/music-index.tsv` ·
`.state/` in-repo (wallpaper-process.conf, current_wallpaper.fp, swaybg.log, auto-wallpaper
pid/queue/history/log).

### 7.3 Live niri config is a **COPY**, not symlinks
`~/.config/niri/*.kdl` are separate files. After editing repo `niri/`:
```bash
cp niri/rules.kdl ~/.config/niri/rules.kdl
niri validate && niri msg action load-config-file
```

### 7.4 systemd user units
| Unit | Why |
| --- | --- |
| `whisrs.service` | dictation (absolute `ExecStart`, `PassEnvironment=NIRI_SOCKET`, `TimeoutStopSec=5`) |
| `cpu-performance.service` | referenced by `scripts/cpu-performance.service` |
| `sddm` | live display manager |
| `polkit-gnome-authentication-agent-1` | spawned from `spawn-at-startup.kdl` at `/usr/lib/polkit-gnome/` |

### 7.5 D-Bus names
`org.freedesktop.Notifications` (owned by quickshell `Toasts` — **exactly one owner**),
`org.freedesktop.UPower`, `org.bluez`, `org.mpris.MediaPlayer2.*`,
`sunset-desktop` (the desktop input plane), `qs` (quickshell IPC).

---

## 8. Setup / verification order

```bash
# 1. packages (§1–2), fonts (§1.13), python (§3), whisrs (§3.1)
fc-match "JetBrainsMono Nerd Font"          # must resolve
python3 -c "import gi, pywayland"           # must import
ls /usr/lib/polkit-gnome/                   # must exist

# 2. the setup script
./setup.sh --skip-install      # symlinks + generated artefacts only

# 3. the one symlink setup.sh never makes
mkdir -p ~/.config/quickshell
ln -sfn "$PWD/quickshell/sunset" ~/.config/quickshell/sunset

# 4. copy live niri config + reload
cp niri/*.kdl ~/.config/niri/ 2>/dev/null; niri validate
niri msg action load-config-file

# 5. start
pkill quickshell; QT_QPA_PLATFORM=wayland NIRI_SETUP_HOME="$PWD" quickshell -c sunset &

# 6. verify
python3 -m unittest discover -s scripts -p 'test_*.py'
python3 scripts/sync-external-theme.py; echo "changed: $?"
bash scripts/palette.sh get            # 11 KEY=RRGGBB lines
tmux -L check -f ~/.config/tmux/tmux.conf new-session -d
Mod+Shift+Q                            # restart the shell
```

**Validation commands** (AGENTS.md):
```
niri validate
quickshell -c sunset                                    # restart
qs -c sunset ipc call <target> toggle                   # exercise a popup
qs -c sunset ipc call themes set <name>                 # switch palette
qs -c sunset ipc call themes autoToggle                 # wallpaper follow on/off
python3 scripts/sync-external-theme.py                  # prints "changed: <targets>"
bash scripts/palette.sh get
python3 -m unittest discover -s scripts -p 'test_*.py'
```

`sync-external-theme.py` printing `niri` in its `changed:` list is the shell's cue to
`niri msg action load-config-file`. Its absence means nothing moved and a reload is wasted.

---

## 9. Machine-specific assumptions (verify, don't assume)

| Assumption | Where | If wrong |
| --- | --- | --- |
| **ALSA capture gain at 100% / +30 dB** | this mic | pure room tone transcribes to `Thank you.` and **energy gating cannot fix it** — the noise floor never reads silence (zero `silence_start` at −20…−40 dBFS). Fix needs `sudo amixer` (root) or a USB headset |
| Brave at `/opt/brave-bin/brave` | `scripts/open-help.sh`, `custom-theme.sh`, desktop entries | rewrite the path |
| `niri-setup` at `/home/me/niri-setup` | many `scripts/*.sh`, `waybar/config`, `setup.sh` sed targets | `setup.sh` rewrites `$NIRICONF`, but **live `~/.config/niri/*.kdl` are copies** — re-copy after setup |
| `whisrsd` at `~/.local/bin/whisrsd` | `whisrs.service` | absolute `ExecStart` must match, else 203/EXEC |
| dictation models at `~/.local/share/niri-setup/dictation/models/` | `~/.config/whisrs/config.toml` symlinks | absolute paths, no `~` |
| loopback `127.0.0.7` for the custom-theme editor | `scripts/custom-theme-server.py` | `niri/rules.kdl` pins `brave-127.0.0.1__-Default` to 400x440; `127.0.0.7` is deliberate |
| CPU governor writable | `cpu-*.sh` | needs `/etc/sudoers.d/cpu-freq` (setup.sh) + `/etc/polkit-1/rules.d/50-cpu-freq.rules` |
| `alsa_capture.whisrsd` is the capture-client name | `MicWidget`/`MicService` dot | `friendlyName()` relabels `Lavf*` → `ffmpeg` |
| niri `26.04 (8ed0da4)` | AGENTS.md (whisrs window tracking) | upstream support assumed at this build |
| single `amdgpu` GPU | `scripts/perf-stats.sh` | `nvidia-smi` fallback exists |

---

## 10. Known gaps — referenced but NOT installed by `setup.sh`

`setup.sh`'s `pkgs=()` predates the quickshell migration. These are **required by the live
shell** and will not install themselves:

| Missing | Impact if absent |
| --- | --- |
| **`qt6-wayland`** | quickshell will not start / no layer-shell popups map |
| **`udiskie`** | automount at startup (`spawn-at-startup.kdl`) |
| **`poppler-qt6`** (for `QtQuick.Pdf`) | the launcher's PDF preview (`launcher/PdfPreview.qml`, `PreviewPane.qml`) |
| **`bluez` + `bluez-utils`** | `BluetoothPopup` scan/pair |
| **`nodejs`** | `test_icon_colors.py` (runs `Theme.qml`'s icon derivation under `node`) |
| **`wallust`** | auto-theming — `wallust-theme.sh` produces the 4 wallpaper palettes |
| **`lm_sensors`** (`sensors`) | `PerfWidget` GPU/CPU temperature segments |
| **`libwacom`** / `xf86-input-libinput` | tablet + stylus |
| `~/.config/quickshell/sunset` symlink | `setup.sh` never creates it — **do it by hand** |
| `whisrs` + models | dictation (`pipx`, plus models by hand) |
| `~/.local/lib/libgtk-nocsd.so.0` | GTK apps keep their headerbar — **built by hand here**, not by setup.sh |

Also note: `swaylock-effects` (not upstream `swaylock`), `tmux ≥ 3.7`, and
`ttf-jetbrains-mono-nerd` (not plain `jetbrains-mono`) are hard requirements that a
generic `paru -S swaylock tmux jetbrains-mono` would get wrong.