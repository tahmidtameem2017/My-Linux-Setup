# GEMINI.md - Niri Setup Context

This file provides instructional context for Gemini when working within this repository.

## Project Overview

**niri-setup** is a comprehensive, visually-driven configuration for the [niri](https://github.com/YaLTeR/niri) Wayland compositor, specifically tailored for Arch Linux. It aims to provide a complete desktop experience out-of-the-box.

### Key Components
- **Compositor:** `niri` (scrollable tiling compositor).
- **Shell:** `Quickshell` 0.3.1 (`quickshell -c sunset`, repo `quickshell/sunset/`) — native QML bar, popups, launcher, and toasts. Replaces Waybar + dunst + Brave HTML popups.
- **Launcher:** Quickshell `Launcher.qml` — app search + pinned Controls section (Quick Settings, Wallpaper, Power, Volume, Clipboard, Calendar, DND) on `Alt+Space` / `Mod+Ctrl+Return`. Fuzzel configs and walker stay on disk, unbound (rollback only).
- **Notifications:** Quickshell `Toasts` (own `org.freedesktop.Notifications`). `dunst` runs only in the legacy waybar session.
- **Terminal:** `Alacritty`.
- **Scripts:** A collection of Bash scripts in `scripts/` managing wallpapers, volume, idle time, and CPU performance. `switch-shell.sh` / `rollback-to-waybar.sh` flip between the quickshell and legacy waybar sessions.
- **Idle/Lock:** `swayidle` and `swaylock-effects`.

### Architecture
- **Configuration:** `niri/` directory uses the KDL format. `config.kdl` acts as the entry point, including specialized files like `binds.kdl`, `rules.kdl`, and `layout.kdl`. Live session adds `binds-quickshell.kdl` (IPC toggles) and spawns `QT_QPA_PLATFORM=wayland NIRI_SETUP_HOME=<repo> quickshell -c sunset` instead of waybar+dunst.
- **Quickshell:** `quickshell/sunset/shell.qml` is the entry point (`Bar` + native QML popups + `Launcher` + `Toasts`). `services/` holds `Theme.qml` (Sunset Orange AMOLED tokens, see `taste.md`), plus `Niri` (pure-QML `NIRI_SOCKET` EventStream, no plugin), `Audio`, `Media`, `Wallpaper`, and `Notification` services. Popups toggle via `qs -c sunset ipc call <calendar|clipboard|launcher|power|settings|volume|wallpaper|wallpaper-menu|notifications> toggle`. `~/.config/quickshell/sunset` is a symlink to the repo dir, so QML edits go live on quickshell restart — no niri reload needed.
- **Legacy:** `waybar/` + Brave `--app` HTML popups are rollback gold only (`niri/spawn-waybar.kdl`, `scripts/rollback-to-waybar.sh`).
- **Automation:** `setup.sh` handles dependency installation (via AUR helpers) and environment-specific path replacement (using `$NIRICONF`). NOTE: it predates the migration — it still installs the waybar stack and does not install quickshell or link `~/.config/quickshell/sunset`.
- **Assets:** Wallpapers and icons are stored in `wallpapers/` and `wlogout/icons/`. Bar icons live in `quickshell/sunset/assets/icons/`.

## Setup and Maintenance

### Installation
To install or update the setup:
```bash
./setup.sh
```
*Note: Requires Arch Linux and an AUR helper (paru, yay, etc.).*

### Key Files
- `niri/config.kdl`: Main entry point for niri settings.
- `niri/binds.kdl`: All keyboard shortcuts (`binds-quickshell.kdl` adds quickshell IPC toggles).
- `niri/rules.kdl`: Window management rules (transparency, floating, etc.).
- `niri/spawn-at-startup.kdl`: Live session spawn list (quickshell variant; `spawn-waybar.kdl` is the rollback gold).
- `quickshell/sunset/shell.qml` + `components/` + `services/`: Panel, popup, and data-layer code.
- `waybar/config` & `waybar/style.css`: Legacy panel configuration and styling (rollback only).
- `scripts/`: Critical automation scripts.

## Development Conventions

### Paths and Placeholders
- The string `$NIRICONF` is used as a placeholder in configuration files. The `setup.sh` script replaces this with the absolute path to the repository root.
- When adding new scripts or config paths, ensure they are added to the `sed` replacement list in `setup.sh`.

### Coding Style
- **Scripts:** Use Bash (`#!/bin/bash`). Ensure scripts are executable.
- **Config:** Follow KDL syntax for `niri`.
- **QML:** Native Quickshell components in `quickshell/sunset/`. Colors/fonts/radius come from `services/Theme.qml` only — never hardcode hex. Toggle popups via `IpcHandler` targets.
- **CSS (legacy):** Waybar CSS lives in `waybar/` and is rollback-only.

### Adding New Features
1. **Keybindings:** Add to `niri/binds.kdl`.
2. **Auto-start:** Add to `niri/spawn-at-startup.kdl`.
3. **Window Rules:** Match by `app-id` in `niri/rules.kdl` (regular windows only — native QML popups need no rules).
4. **Bar/popup widget:** Add to `quickshell/sunset/components/` with data from `services/`.

## Common Tasks for Gemini

### Debugging Config
If niri fails to start, use:
```bash
niri validate
```

### Modifying Keybindings
Edit `niri/binds.kdl`. Common modifiers: `Mod` (Super), `Ctrl`, `Shift`, `Alt`.

### Updating the shell (Quickshell sunset)
Quickshell code lives in `quickshell/sunset/`, symlinked from `~/.config/quickshell/sunset`. Restart the shell to apply QML changes (`Mod+Shift+Q`, or `pkill quickshell; quickshell -c sunset &`). Exercise a popup headlessly with `qs -c sunset ipc call <target> toggle`. Theme tokens are in `services/Theme.qml` (Sunset Orange AMOLED, see `taste.md`).

### Legacy Waybar (rollback session only)
Waybar styles are located in `waybar/`. `reload_style_on_change: true` in `waybar/config` live-reloads CSS only when the waybar session is running — it is not running in the live quickshell session. Roll back with `scripts/rollback-to-waybar.sh` if needed.
