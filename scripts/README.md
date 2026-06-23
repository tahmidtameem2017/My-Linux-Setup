# Wallpaper Changer

A simple script to change wallpapers in niri with support for random, next, and previous options.

## Setup

The alias is already added to `~/.bashrc`. Open a **new terminal** or run:

```bash
source ~/.bashrc
```

## Usage

### Random wallpaper (default)
```bash
wallpaper
# or
wallpaper random
# or use full path
/home/me/niri-setup/scripts/set-wallpaper.sh
```

### Next wallpaper in folder
```bash
wallpaper next
```

### Previous wallpaper
```bash
wallpaper prev
# or
wallpaper previous
```

## How It Works

- **random**: Picks a random wallpaper from `/home/me/Pictures/Wallpapers`
- **next**: Cycles to the next wallpaper (alphabetically sorted)
- **prev**: Returns to the previously displayed wallpaper

The script uses `swaybg` to set wallpapers in niri.
