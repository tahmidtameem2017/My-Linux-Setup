# GEMINI.md - Niri Setup Context

This file provides instructional context for Gemini when working within this repository.

## Project Overview

**niri-setup** is a comprehensive, visually-driven configuration for the [niri](https://github.com/YaLTeR/niri) Wayland compositor, specifically tailored for Arch Linux. It aims to provide a complete desktop experience out-of-the-box.

### Key Components
- **Compositor:** `niri` (scrollable tiling compositor).
- **Bar:** `Waybar` with custom CSS (macOS-inspired and default) and scripts.
- **Launcher:** `Fuzzel` for applications, clipboard, and power menus.
- **Notifications:** `Dunst`.
- **Terminal:** `Alacritty`.
- **Scripts:** A collection of Bash scripts in `scripts/` managing wallpapers, volume, idle time, and CPU performance.
- **Idle/Lock:** `swayidle` and `swaylock-effects`.

### Architecture
- **Configuration:** `niri/` directory uses the KDL format. `config.kdl` acts as the entry point, including specialized files like `binds.kdl`, `rules.kdl`, and `layout.kdl`.
- **Automation:** `setup.sh` handles dependency installation (via AUR helpers) and environment-specific path replacement (using `$NIRICONF`).
- **Assets:** Wallpapers and icons are stored in `wallpapers/` and `wlogout/icons/`.

## Setup and Maintenance

### Installation
To install or update the setup:
```bash
./setup.sh
```
*Note: Requires Arch Linux and an AUR helper (paru, yay, etc.).*

### Key Files
- `niri/config.kdl`: Main entry point for niri settings.
- `niri/binds.kdl`: All keyboard shortcuts.
- `niri/rules.kdl`: Window management rules (transparency, floating, etc.).
- `waybar/config` & `waybar/style.css`: Panel configuration and styling.
- `scripts/`: Critical automation scripts.

## Development Conventions

### Paths and Placeholders
- The string `$NIRICONF` is used as a placeholder in configuration files. The `setup.sh` script replaces this with the absolute path to the repository root.
- When adding new scripts or config paths, ensure they are added to the `sed` replacement list in `setup.sh`.

### Coding Style
- **Scripts:** Use Bash (`#!/bin/bash`). Ensure scripts are executable.
- **Config:** Follow KDL syntax for `niri`.
- **CSS:** Use modular CSS for Waybar, following the existing color variables and class structures.

### Adding New Features
1. **Keybindings:** Add to `niri/binds.kdl`.
2. **Auto-start:** Add to `niri/spawn-at-startup.kdl`.
3. **Window Rules:** Match by `app-id` in `niri/rules.kdl`.

## Common Tasks for Gemini

### Debugging Config
If niri fails to start, use:
```bash
niri validate
```

### Modifying Keybindings
Edit `niri/binds.kdl`. Common modifiers: `Mod` (Super), `Ctrl`, `Shift`, `Alt`.

### Updating Waybar
Waybar styles are located in `waybar/`. The project uses `reload_style_on_change: true` in `waybar/config`, so CSS changes should reflect immediately if Waybar is running.
