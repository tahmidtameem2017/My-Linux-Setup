# taste.md — design taste for niri-setup

How things should look and feel. Match this; don't invent new styles.

## Theme: Sunset Orange AMOLED

Black backgrounds, orange accents, peach text. Warm glow on hover/active,
restraint at rest.

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

## Typography

- **JetBrainsMono Nerd Font everywhere**: bar, popups, lock screen, menus.
- Bar icons are minimalist stroke SVGs in `waybar/icons/`
  (24×24, 1.7px stroke, round caps, theme colors baked in),
  wired via `image#` modules — never emoji, never font glyphs.
  Dynamic states (volume/network/battery/media) resolve through
  `waybar/scripts/*-icon.sh`. Every `image` module needs an `interval`
  (waybar 0.15 won't paint it otherwise).

## Shape & glow

- Sharp rectangles. `border-radius: 0` on bar and popup cards.
- Resting shadow: `0 0 15px rgba(232, 93, 47, 0.15)`.
- Hover/active glow, e.g. text: `0 0 6px rgba(255,139,74,.9),
  0 0 18px rgba(255,139,74,.6), 0 0 35px rgba(232,93,47,.35)`.
- Selected/today: solid `--accent` fill with black text.

## HTML popups (calendar / volume / wallpaper / power)

All four follow one pattern — keep it:

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

## Don'ts

- No `yad`/`zenity` GTK dialogs — they can't match the theme.
- No Cancel/OK chrome on view popups; no window decorations needed.
- No blue/grey (`#b7d4ed`, `#61768F`) or Ubuntu fonts — that was the old
  Frosted Midnight theme, fully replaced.
- No full-screen or tiled popups: floating, compact, centered.
- No new accent colors. If white is needed (wrong-password), that's the
  only exception.
