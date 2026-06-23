# niri-setup - Context Guide

## Project Overview

This repository contains a complete **niri Wayland compositor configuration** with integrated desktop environment components. It provides a polished, minimalistic Linux desktop setup centered around the niri scrollable window manager.

**Primary Purpose:** Dotfiles/configuration repository for setting up a full-featured niri-based desktop environment on Arch Linux.

**Key Technologies:**
- **Window Manager:** niri (scrollable tiling Wayland compositor)
- **Launcher:** Fuzzel
- **Panel:** Waybar
- **Notifications:** dunst
- **Terminal:** Alacritty
- **Lock Screen:** swaylock
- **Wallpaper:** swaybg + swww
- **Idle Management:** swayidle
- **Logout Menu:** wlogout
- **Clipboard:** cliphist

## Directory Structure

```
niri-setup/
├── niri/              # niri compositor configuration (KDL files)
├── waybar/            # Waybar panel config and scripts
│   ├── config         # JSON configuration
│   ├── style.css      # Styling
│   ├── modules/       # Additional modules
│   └── scripts/       # Helper scripts (weather, colorpicker, powerdraw)
├── alacritty/         # Terminal emulator configuration
│   ├── default.toml   # Main terminal config
│   └── float.toml     # Floating window variant
├── fuzzel/            # Application launcher configuration
│   ├── fuzzel.ini     # Main launcher config
│   ├── clipboard.ini  # Clipboard menu config
│   ├── idle-time.ini  # Idle time menu config
│   └── power-profile.ini  # Power profile menu config
├── dunst/             # Notification daemon configuration
│   └── dunstrc        # Notification settings
├── wlogout/           # Logout screen configuration
│   ├── layout         # Button layout
│   ├── style.css      # Styling
│   └── icons/         # Icon assets
├── kitty/             # Alternative terminal configuration
├── niriswitcher/      # niriswitcher configuration
│   └── config.toml
├── scripts/           # Utility scripts
│   ├── change-wallpaper.sh
│   ├── change-idle-time.sh
│   ├── change-power-profile.sh
│   ├── swayidle.sh
│   ├── toggle-waybar.sh
│   ├── wlogout.sh
│   └── README.md      # Script usage documentation
├── wallpapers/        # Wallpaper images
├── setup.sh           # Installation script
├── COLOR_PALETTE.md   # "Frosted Midnight" color palette documentation
└── README.md          # Main documentation with keybindings
```

## Installation & Setup

**Requirements:**
- Arch Linux or Arch-based distribution
- AUR helper (yay, paru, aura, or trizen)
- `gum` package for interactive prompts

**Installation Commands:**
```bash
git clone https://github.com/acaibowlz/niri-setup.git
cd niri-setup
./setup.sh
```

**Installation Options:**
- `./setup.sh` - Full installation with package management
- `./setup.sh --skip-install` - Skip package installation, only symlink configs

**What the Setup Script Does:**
1. Validates AUR helper availability
2. Installs required packages via AUR
3. Symlinks configuration files to `~/.config/`
4. Replaces `$NIRICONF` placeholders with actual paths
5. Validates niri configuration

## Color Palette: "Frosted Midnight"

A curated color scheme applied consistently across all components:

| Color    | Hex       | RGB                  |
|----------|-----------|----------------------|
| Foreground | `#d8dadd` | `rgb(216, 218, 221)` |
| Background | `#0b0b0c` | `rgb(11, 11, 12)`    |
| Red      | `#61768F` | `rgb(97, 118, 143)`  |
| Green    | `#758A9B` | `rgb(117, 138, 155)` |
| Yellow   | `#949EA3` | `rgb(148, 158, 163)` |
| Blue     | `#B2BCC4` | `rgb(178, 188, 196)` |
| Magenta  | `#BCC2C6` | `rgb(188, 194, 198)` |
| Cyan     | `#B7D4ED` | `rgb(183, 212, 237)` |

## Key Features

- **Integrated Desktop Experience:** Complete setup with waybar, fuzzel, dunst, swaylock, and more
- **Custom Widgets:** Idle time and power profile picker available as waybar widgets and fuzzel menus
- **Dynamic Wallpapers:** Script supports random/next/previous wallpaper switching with blurred overview backdrop
- **Curated Aesthetics:** Consistent "Frosted Midnight" color palette across all components
- **Clean UI:** Minimalistic design optimized for daily driving

## Configuration Notes

- **niri version:** Compatible with niri v25.11+
- **Font Requirements:**
  - Ubuntu Mono Nerd Font (UI)
  - Noto Sans Mono CJK TC (CJK text support)
  - JetBrains Mono Nerd Font (Terminal)
- **GTK Theme:** Colloid-gtk-theme
- **Icon Theme:** Colloid-icon-theme
- **Cursor:** Adwaita

## Related Dotfiles

The following configurations are maintained in a separate [dotfiles repository](https://github.com/acaibowlz/dotfiles):
- `fastfetch`
- `fontconfig`
- `spicetify`
- `starship`
- `zsh`

## Development & Maintenance

**File Format:** niri uses KDL (Keyed Data Language) for configuration - a human-readable, hierarchical format similar to YAML but with better type support.

**Path Placeholders:** Configuration files use `$NIRICONF` as a placeholder that gets replaced with the actual installation path during setup.

**Validation:** Run `niri validate` to check configuration syntax after changes.
