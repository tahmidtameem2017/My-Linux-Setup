<div align="center">

# 🌅 Sunset Niri

**A complete, animated macOS-style Wayland desktop — bar, launcher, popups, theming and all.**

*Scrollable-tiling [niri](https://github.com/YaLTeR/niri) compositor + a native
[Quickshell](https://quickshell.org/) QML shell, a dynamic wallpaper-aware theme engine,
and 16 lazy-loaded popups.*

[![niri](https://img.shields.io/badge/compositor-niri%2026.04-blue)](https://github.com/YaLTeR/niri)
[![quickshell](https://img.shields.io/badge/shell-quickshell%200.3.1-purple)](https://quickshell.org/)
[![license](https://img.shields.io/badge/license-GPL--3.0-green)](./LICENSE)

</div>

---

## 📸 Screenshots

| | | |
| :--: | :--: | :--: |
| ![Desktop](https://raw.githubusercontent.com/acaibowlz/niri-setup/refs/heads/main/.github/assets/screenshots/screenshot1.png) | ![Launcher](https://raw.githubusercontent.com/acaibowlz/niri-setup/refs/heads/main/.github/assets/screenshots/screenshot2.png) | ![Now Playing](https://raw.githubusercontent.com/acaibowlz/niri-setup/refs/heads/main/.github/assets/screenshots/screenshot3.png) |
| ![Wallpapers](https://raw.githubusercontent.com/acaibowlz/niri-setup/refs/heads/main/.github/assets/screenshots/screenshot4.png) | ![Power Menu](https://raw.githubusercontent.com/acaibowlz/niri-setup/refs/heads/main/.github/assets/screenshots/screenshot5.png) | ![Capture](https://raw.githubusercontent.com/acaibowlz/niri-setup/refs/heads/main/.github/assets/screenshots/screenshot6.png) |

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
git clone https://github.com/acaibowlz/niri-setup.git ~/niri-setup
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

### Step 4 — Log in

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
Repository: https://github.com/acaibowlz/niri-setup

You have permission to run shell commands, edit files, and manage packages. Work
AUTONOMOUSLY through every phase below. Verify each step by actually running the
verification command — never assume a command worked. When something fails, read the
error, find the ROOT CAUSE, fix it, and re-verify. Only interrupt me for (a) sudo
passwords, (b) a choice only I can make (city, timezone, wallpaper folder), or (c) a
destructive action.

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
  git clone https://github.com/acaibowlz/niri-setup.git ~/niri-setup
  cd ~/niri-setup && ./setup.sh
On Arch plain ./setup.sh is correct — it installs packages via the AUR helper too.
If prompted "niri config exists, overwrite? (Y/n)" answer Y. A failure from the
final `niri validate` inside setup.sh is EXPECTED until Phase 3 — continue.

PHASE 3 — CRITICAL FIXES (this repo is not a clean-install script; all four apply)
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

PHASE 4 — PRIVILEGED EXTRAS (ask before each sudo; all are OPTIONAL)
Offer these one at a time, explain the benefit, and let me decline:
  a) Login theme:  sudo ~/niri-setup/sddm/install.sh   (Sunset SDDM theme;
     preview first with: sddm-greeter --test-mode --theme ~/niri-setup/sddm/sunset)
  b) CPU governor: the repo ships scripts/sudoers-cpu and scripts/50-cpu-freq.rules
     but BOTH HARDCODE the username "me" and the path /home/me/niri-setup. Do NOT
     install them as-is. Instead generate correct copies for MY username and path:
       sed "s/^me ALL/$(whoami) ALL/; s|/home/me/niri-setup|$HOME/niri-setup|g" \
         ~/niri-setup/scripts/sudoers-cpu > /tmp/cpu-freq
       (then: sudo install -m 440 /tmp/cpu-freq /etc/sudoers.d/cpu-freq
             sudo visudo -c  # must parse cleanly)
     Same substitution for scripts/50-cpu-freq.rules into
     /etc/polkit-1/rules.d/50-cpu-freq.rules. ALWAYS run `sudo visudo -c`
     afterwards — a malformed sudoers file can lock me out. If it does not parse,
     remove the file immediately.
     Warn me: cpu-permanent.sh pins every core to performance/2.4GHz, which drains
     battery and generates heat. Only offer it on a desktop, never a laptop.
     Note it is also Intel-cpufreq specific; on AMD or a machine without
     /sys/.../cpufreq it silently does nothing.

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
  1. Wallpapers: ask where my wallpapers live (default ~/Pictures/Wallpapers), then
       ~/niri-setup/scripts/wallpaper.sh set <path>
     Enable auto-theming so the palette follows every wallpaper change:
       ~/niri-setup/scripts/wallpaper-process.sh set AUTOSTART true
       ~/niri-setup/scripts/auto-wallpaper.sh --oneshot
     Explain that this is what re-themes bar/terminal/menus live.
  2. Theme: list the palettes, let me pick a default, apply with
       qs -c sunset ipc call themes set <name>
     Show me the visual editor (Mod+Alt+Shift+T) and explain the 11 tokens
     (bg, panel, row, border, borderStrong, accent, accentHover, text, muted, dim,
     danger) — never hardcode a hex in a component.
  3. Identity + locale: ask my city/timezone for the clock, weather and lock screen.
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
Repository: https://github.com/acaibowlz/niri-setup

You have permission to run shell commands, edit files, and manage packages. Work
AUTONOMOUSLY through every phase below. Verify each step by actually running the
verification command — never assume a command worked. When something fails, read the
error, find the ROOT CAUSE, fix it, and re-verify. Only interrupt me for (a) sudo
passwords, (b) a choice only I can make (city, timezone, wallpaper folder), or (c) a
destructive action.

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
  git clone https://github.com/acaibowlz/niri-setup.git ~/niri-setup
  cd ~/niri-setup && ./setup.sh --skip-install

PHASE 3 — CRITICAL FIXES (all four apply)
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

PHASE 4 — FEDORA PATH FIX + PRIVILEGED EXTRAS
FIX 5 — the polkit agent. spawn-at-startup.kdl hardcodes the Arch-only path
  /usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1, and setup.sh rewrites
  only $NIRICONF, so password dialogs (mounting disks, suspend) never appear.
  Find the real binary and rewrite that line:
    P=$(command -v polkit-gnome-authentication-agent-1 || \
        ls /usr/libexec/polkit-gnome-authentication-agent-1 2>/dev/null)
    sed -i "s|/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1|$P|" \
      ~/.config/niri/spawn-at-startup.kdl
Then offer these OPTIONAL extras one at a time, letting me decline:
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
     Warn me this pins every core to performance/2.4GHz (heat, battery drain) and is
     Intel-cpufreq specific — never offer it on a laptop.

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
  1. Wallpapers: ask where mine live (default ~/Pictures/Wallpapers), then
       ~/niri-setup/scripts/wallpaper.sh set <path>
     Enable auto-theming:
       ~/niri-setup/scripts/wallpaper-process.sh set AUTOSTART true
       ~/niri-setup/scripts/auto-wallpaper.sh --oneshot
  2. Theme: list palettes, let me pick a default:
       qs -c sunset ipc call themes set <name>
     Show the visual editor (Mod+Alt+Shift+T); explain the 11 tokens and that
     components must never hardcode a hex.
  3. Identity + locale: ask my city/timezone for clock, weather and lock screen.
  4. Keybindings: ask for the 5 things I do most, add them to niri/binds.kdl or
     binds-quickshell.kdl, then
       cp ~/niri-setup/niri/*.kdl ~/.config/niri/
       niri validate && niri msg action load-config-file
  5. Startup apps: show me ~/.config/niri/spawn-at-startup.kdl, let me edit it.
  6. Rollback: document scripts/switch-shell.sh waybar (reverts to classic
     Waybar+dunst) and scripts/rollback-to-waybar.sh (emergency). Tell me how to
     start niri from a TTY (`niri-session`).

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
Repository: https://github.com/acaibowlz/niri-setup

You have permission to run shell commands, edit files, and manage packages. Work
AUTONOMOUSLY through every phase below. Verify each step by actually running the
verification command — never assume a command worked. When something fails, read the
error, find the ROOT CAUSE, fix it, and re-verify. Only interrupt me for (a) sudo
passwords, (b) a choice only I can make (city, timezone, wallpaper folder), or (c) a
destructive action.

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
  git clone https://github.com/acaibowlz/niri-setup.git ~/niri-setup
  cd ~/niri-setup && ./setup.sh --skip-install

PHASE 3 — CRITICAL FIXES (all four apply)
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

PHASE 4 — DEBIAN PATH FIX + PRIVILEGED EXTRAS
FIX 5 — the polkit agent. spawn-at-startup.kdl hardcodes the Arch-only path
  /usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1; on Debian it is usually
  under /usr/libexec. Find it and rewrite that line:
    P=$(command -v polkit-gnome-authentication-agent-1 || \
        ls /usr/libexec/polkit-gnome-authentication-agent-1 2>/dev/null)
    sed -i "s|/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1|$P|" \
      ~/.config/niri/spawn-at-startup.kdl
Then offer these OPTIONAL extras one at a time, letting me decline:
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
     Warn me this pins every core to performance/2.4GHz (heat, battery drain), is
     Intel-cpufreq specific, and should never be used on a laptop.

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
  1. Wallpapers: ask where mine live (default ~/Pictures/Wallpapers), then
       ~/niri-setup/scripts/wallpaper.sh set <path>
     Enable auto-theming:
       ~/niri-setup/scripts/wallpaper-process.sh set AUTOSTART true
       ~/niri-setup/scripts/auto-wallpaper.sh --oneshot
  2. Theme: list palettes, let me pick a default:
       qs -c sunset ipc call themes set <name>
     Show the visual editor (Mod+Alt+Shift+T); explain the 11 tokens and that
     components must never hardcode a hex.
  3. Identity + locale: ask my city/timezone for clock, weather and lock screen.
  4. Keybindings: ask for the 5 things I do most, add them to niri/binds.kdl or
     binds-quickshell.kdl, then
       cp ~/niri-setup/niri/*.kdl ~/.config/niri/
       niri validate && niri msg action load-config-file
  5. Startup apps: show me ~/.config/niri/spawn-at-startup.kdl, let me edit it.
  6. Rollback: document scripts/switch-shell.sh waybar (reverts to classic
     Waybar+dunst) and scripts/rollback-to-waybar.sh (emergency). Tell me how to
     start niri from a TTY (`niri-session`).

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
- **Offline voice dictation** with `whisrs` (whisper.cpp) — no cloud, no key.
- **Music**: download from a link, dedup, and play your whole library; MPRIS-aware.
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

This repo ships a **168-test suite** guarding the theming and export logic:

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
- **[acaibowlz](https://github.com/acaibowlz)** — creator of `niri-setup`, the original
  design this fork grew out of. This README and much of the layout descend from their
  work.
- **[@hengtseChou](https://github.com/hengtseChou)** *(same person as acaibowlz — hankthedev)* —
  the vast majority of the migration work: building the native Quickshell shell, the
  theme engine, wallpaper theming, and the cross-cutting scripts.
- **[tahmidtameem](https://github.com/tahmidtameem)** — contributions.

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