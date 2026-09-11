# AGENTS.md — niri-setup

## Quick start

```bash
./setup.sh                  # full install (Arch + AUR helper required)
./setup.sh --skip-install   # symlink configs only, skip packages
```

`$NIRICONF` is a placeholder replaced at install time by `setup.sh`. All paths below are written in the "after install" form.

## Repo structure

```
niri/               # niri compositor config (KDL format)
  config.kdl        # entry point, includes *.kdl files below
  binds.kdl         # keyboard shortcuts (Mod = Super)
  layout.kdl        # gaps, column widths, focus ring
  rules.kdl         # window opacity, floating, corner radius
  spawn-at-startup.kdl  # daemons: waybar, dunst, swayidle, cpu, wallpaper
  wallpapers.kdl    # swaybg + swww backdrop (gitignored, generated)
waybar/             # bar config + styles + custom modules/scripts
  config            # JSON, reload_style_on_change: true → live CSS edits
  style.css         # "Sunset Orange AMOLED" theme (see taste.md)
  modules/          # window_info.py, media-player.py, install-updates.sh, etc.
  scripts/          # calendar.sh, volume.sh, wallpaper-gallery.sh, power-menu.sh, etc.
  calendar/         # calendar.html (self-contained popup page)
  volume/           # volume.html + volume-server.py (mixer backend)
  wallpaper/        # wallpaper.html + wallpaper-server.py (gallery backend)
  power/            # power.html + power-server.py (fixed allowlist actions)
taste.md            # design-taste guide: theme tokens, popup conventions
scripts/            # standalone scripts (not waybar-specific)
  auto-wallpaper.sh # wallpaper rotation daemon (shuffles $HOME/Pictures/Wallpapers)
  wallpaper.sh      # set wallpaper + generate blurred backdrop + persist
  change-wallpaper.sh  # gum-based interactive wallpaper picker
  set-wallpaper.sh  # simple random/next/prev wallpaper switcher
fuzzel/             # multiple .ini configs: fuzzel, clipboard, idle-time, power-profile
alacritty/          # default.toml (tiled) + float.toml (floating: updater, nmtui, wallpaper selector)
wlogout/            # layout + style.css + icons/
wallpapers/         # workspace.jpg (active), backdrop.webp (overview) — gitignored, generated at runtime
.state/             # auto-wallpaper daemon: history, queue, log, pid
```

## Key facts an agent would miss

- **niri config is modular KDL**: `config.kdl` includes all other `*.kdl` files via `include`. Add a new file → add `include "file.kdl"` in `config.kdl`.
- **Wallpapers are gitignored**: `wallpapers/` and `niri/wallpapers.kdl` are in `.gitignore`. They are generated at runtime. The active wallpaper is always `wallpapers/workspace.{jpg,png,webp}`.
- **Two wallpaper engines**: `swaybg` renders the workspace wallpaper; `swww` provides the blurred backdrop for overview mode.
- **`scripts/change-wallpaper.sh` edits `niri/config.kdl` directly** (via sed on lines containing `swaybg` and `swww`), not `niri/wallpapers.kdl`. This is a quirk — the `wallpapers.kdl` file is only used at initial spawn.
- **Alacritty has two profiles**: `default.toml` (tiled windows) and `float.toml` (floating for updater, nmtui, wallpaper selector, Dropdown scratchpad). `~/.config/alacritty/alacritty.toml` is a symlink to `default.toml` (covers bare `alacritty` invocations).
- **Dropdown scratchpad** (`scripts/dropdown-terminal.sh`, `Mod+Grave`): zero-dependency, parks the terminal on the persistent `workspace "scratch"` (declared in `niri/config.kdl`) via niri IPC. Test the full cycle (spawn → park → show → park) and leave it parked.
- **Fuzzel has 4 configs**: `fuzzel.ini` (app launcher), `clipboard.ini`, `idle-time.ini`, `power-profile.ini`.
- **`$NIRICONF`** paths appear in `binds.kdl`, `spawn-at-startup.kdl`, `waybar/config`, `waybar/style.css`, and 8 `scripts/*.sh` files. `setup.sh` replaces it via sed.
- **Auto-wallpaper daemon** (`scripts/auto-wallpaper.sh`) manages its state in `.state/` (PID, queue, history, log). Supports `--stop`, `--status`, `--oneshot`, `--next`.
- **Waybar auto-reloads CSS**: `reload_style_on_change: true` in config — edit `style.css` and changes appear immediately without restart.
- **Waybar config changes need a restart**: `pkill waybar; waybar -c ~/niri-setup/waybar/config -s ~/niri-setup/waybar/style.css &`
- **Live niri config is a COPY**: `~/.config/niri/*.kdl` are separate files, not symlinks. After editing repo `niri/`, copy the file over and hot-reload: `cp niri/rules.kdl ~/.config/niri/rules.kdl && niri validate && niri msg action load-config-file`.
- **HTML popup system**: bar icons open themed pages via `brave --app` (dedicated profile each). Launcher scripts toggle (re-click closes). See `taste.md` for the pattern.
  | Popup    | Launcher | Page/server | URL host → Brave app-id | Size |
  | -------- | -------- | ----------- | ----------------------- | ---- |
  | calendar | `waybar/scripts/calendar.sh` | `waybar/calendar/calendar.html` + `waybar/clock/timer-server.py` (calendar+pomodoro+timer; server persists so timers run with window closed) | `127.0.0.4` → `brave-127.0.0.4__-Default` | 400×490 |
  | volume   | `waybar/scripts/volume.sh` | `waybar/volume/` | `127.0.0.1` → `brave-127.0.0.1__-Default` | 400×440 |
  | wallpaper| `waybar/scripts/wallpaper-gallery.sh` | `waybar/wallpaper/` | `localhost` → `brave-localhost__-Default` | 760×560 |
  | power    | `waybar/scripts/power-menu.sh` | `waybar/power/` | `127.0.0.2` → `brave-127.0.0.2__-Default` | 360×440 |
- **Match popups by open-time app-id, never title**: niri evaluates `open-floating` once at window-open, before Brave sets the document title. Get the real id via `niri msg windows` while the popup is open. Popup rules also set `open-maximized-to-edges false` + fixed size.
- **Waybar clock actions use underscores**: valid names are `mode`, `shift_up`, `shift_down` (dashes don't exist). Shell commands go on top-level `on-click`, never inside `actions` (no `exec` action in waybar 0.15).
- **Volume conventions**: cap 100% (`scripts/set-volume.sh`); bar left opens mixer, right mutes, middle opens pavucontrol.
- **Wallpaper set is slow**: `scripts/wallpaper.sh` regenerates the blurred backdrop with magick (can take 1–2 min on huge files); server timeout is 300s. Fuzzel "Pick..." opens the visual gallery.
- **wlogout**: `layout` lock action must point at `scripts/swaylock.sh` (hyprlock isn't installed); `style.css` icon URLs must be absolute (relative `./icons/` breaks when CWD differs).

## Validation

```bash
niri validate
```

## Window rule conventions

Match by `app-id` (lowercase, e.g. `org.gnome.Nautilus`). Common rules in `rules.kdl`:
- `opacity 0.85` for all windows + specific app overrides
- `open-maximized-to-edges true` for browsers, editors, Discord, Spotify, Telegram
- `open-floating true` for calculators, pwvucontrol, Alacritty float windows, file chooser dialogs
- `geometry-corner-radius 10` + `clip-to-geometry true` (global)

## Adding features

1. **Keybinding**: `niri/binds.kdl`
2. **Auto-start**: `niri/spawn-at-startup.kdl`
3. **Window rule**: `niri/rules.kdl`
4. **Waybar module**: `waybar/config` + `waybar/style.css`
