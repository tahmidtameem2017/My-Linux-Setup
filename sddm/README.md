# SDDM Sunset Orange AMOLED

Login theme for niri-setup — replaces stock blue (maya `#303F9F` / maldives light-blue) with Sunset AMOLED.

## Live status (recon)

- `cat /etc/sddm.conf` → `[Autologin] Session=plasma`, no `[Theme] Current=` → SDDM uses default alphabetical (elarun)
- `ls /usr/share/sddm/themes` → `elarun` `maldives` `maya`
- `systemctl is-enabled sddm` → `enabled`, `lightdm` → `disabled` → SDDM is live
- `/usr/share/sddm/themes/maya/theme.conf` → `primaryShade #303F9F` blue, `accentShade #FF4081` pink, `defaultBg #1e88e5` — source of blue gradient + grey card seen in image 2

## Files

- `sddm/sunset/Main.qml` — centered `hh:mm` (11:50 style) + date, sharp `radius:0`, JetBrainsMono Nerd Font, AMOLED `#000000`
- `sddm/sunset/theme.conf` — Sunset tokens + legacy maya keys mapped
- `sddm/sunset/metadata.desktop` — `Theme-API=2.0`, `Theme-Id=sunset`
- `sddm/sunset/images/background.png` — 1×1 `#000000` (solid, no gradient)
- `sddm/sunset/images/arrow-down.svg` — 24×24 1.7px stroke ` #3D2B24` (combo arrow)
- `sddm/sunset/screenshot.png` — placeholder
- `sddm/sunset.conf` / `sddm/sddm.conf.d/sunset.conf` — tracked snippet for `/etc/sddm.conf.d/sunset.conf`
- `sddm/install.sh` — sudo-guarded installer (dry-run to `/tmp/test-sunset` if no sudo)
- `lightdm/lightdm-gtk-greeter.conf` — fallback GTK greeter (black `#000000`, JetBrainsMono)

## Install

```bash
sudo ./sddm/install.sh
# or manually:
sudo mkdir -p /usr/share/sddm/themes/sunset && sudo cp -r sddm/sunset/* /usr/share/sddm/themes/sunset/
sudo mkdir -p /etc/sddm.conf.d && printf "[Theme]\nCurrent=sunset\n" | sudo tee /etc/sddm.conf.d/sunset.conf
# backup: /tmp/bak/sddm-sunset-*
# validate: qmlformat sddm/sunset/Main.qml >/dev/null; echo $?  # 0
# test greeter: sddm-greeter --test-mode --theme /usr/share/sddm/themes/sunset
# no pkill sddm, no reboot required — applies on next login
```

Revert: `sudo rm /etc/sddm.conf.d/sunset.conf` (falls back to elarun alphabetical)

## Why blue is gone

| Before (maya/elarun/maldives) | After (sunset) | Use |
|---|---|---|
| `primaryShade #303F9F` blue | `panel #0a0a0a` | header / card bg |
| `primaryDark #1A237E` indigo | `bg #000000` | page bg (was blue gradient) |
| `primaryHue1 #5965B2` | `row #141010` | input fields |
| `primaryHue3 #2C3998` border | `borderStrong #3D2B24` | card/input border (sharp 0) |
| `accentShade #FF4081` pink | `accent #E85D2F` orange | focus / login button |
| `accentLight #FF80AB` | `accentHover #FF8B4A` | hover glow |
| `normalText #ffffff` | `text #F7C7A1` peach | body |
| `failureText #e53935` | `danger #c30505` | wrong password |
| `defaultBg #1e88e5` light blue | `bg #000000` AMOLED | background fill |
| `OpenSans_CondLight` | `JetBrainsMono Nerd Font` | all text |
| rounded `radius 20` (SpButton) | `radius 0` sharp | cards/buttons |
| blue gradient + grey card | black `#000000` + orange glow `rgba(232,93,47,0.15)` | rest/hover shadow |

## Validation

```bash
qmlformat sddm/sunset/Main.qml >/dev/null; echo $?  # 0
qmllint sddm/sunset/Main.qml; echo $?               # 0
```
