#!/bin/bash
export GUM_CHOOSE_HEADER_FOREGROUND="$#d8dadd"
export GUM_CHOOSE_SELECTED_FOREGROUND="#758A9B"
export GUM_CHOOSE_CURSOR_FOREGROUND="#758A9B"

is_installed() {
  pacman -Qi "$1" &>/dev/null
}

SKIP_INSTALL=false
if [ "$1" == "--skip-install" ]; then
  SKIP_INSTALL=true
fi

if [ "$SKIP_INSTALL" = false ]; then
  if ! is_installed gum; then
    echo "[ERROR] missing dependency: gum"
    exit 1
  fi

  helper_options=(
    paru
    yay
    aura
    trizen
  )
  available_helpers=()
  for helper in "${helper_options[@]}"; do
    if is_installed "$helper"; then
      available_helpers+=("$helper")
    fi
  done
  if [ ${#available_helpers[@]} -eq 0 ]; then
    echo "[ERROR] no AUR helper available. please install one of {yay, paru, aura, trizen}."
    exit 1
  fi
  aur=$(gum choose "${available_helpers[@]}" --header "choose an AUR helper:" --select-if-one)

  pkgs=(
    fastfetch
    alacritty
    brightnessctl
    btop
    cliphist
    dunst
    flameshot-git
    tesseract
    tesseract-data-eng
    fuzzel
    gtk-nocsd-git
    hyprpicker
    jq
    niri
    niriswitcher
    networkmanager
    pamixer
    pavucontrol
    power-profiles-daemon
    polkit-gnome
    pwvucontrol
    python-pywayland
    starship
    sushi
    swaybg
    swayidle
    swaylock-effects
    swww
    thunar
    thunar-volman
    tmux
    tumbler
    gvfs
    xfce4-settings
    systemsettings
    waybar
    wl-clipboard
    wlogout
    xwayland-satellite
  )
  $aur -Syu --needed $(echo "${pkgs[*]}")
fi

config_folder=$(dirname "$(realpath "$0")")
if [ -d "$HOME/.config/niri" ]; then
  read -p "[WARN] niri config file exists. do you want to overwrite it? (Y/n): " overwrite
  overwrite=${overwrite:-Y}
  if [[ $overwrite =~ ^[Yy]$ ]]; then
    ln -sf $config_folder/niri/config.kdl $HOME/.config/niri/config.kdl
  else
    echo "[INFO] aborting"
    exit 1
  fi
fi

# tmux: beginner keybinds + a GENERATED theme fragment (tmux/ in this repo)
mkdir -p "$HOME/.config/tmux"
ln -sf $config_folder/tmux/tmux.conf "$HOME/.config/tmux/tmux.conf"
ln -sf $config_folder/tmux/cheatsheet.sh "$HOME/.config/tmux/cheatsheet.sh"
ln -sf $config_folder/tmux/theme.conf "$HOME/.config/tmux/theme.conf"
if [ ! -f "$HOME/.tmux.conf" ]; then
  echo "source-file ~/.config/tmux/tmux.conf" >"$HOME/.tmux.conf"
elif ! grep -q "config/tmux/tmux.conf" "$HOME/.tmux.conf"; then
  echo "[WARN] ~/.tmux.conf exists but does not source-file the repo config — merge it by hand."
fi

# Alacritty: both profiles are rendered from alacritty/*.toml.in so the terminal
# follows the same palette as the bar. Generated at the SAME paths the
# hand-written files used to occupy, so the ~/.config/alacritty/alacritty.toml
# symlink and every `--config-file .../float.toml` caller keep working.
mkdir -p "$HOME/.config/alacritty"
if [ ! -e "$HOME/.config/alacritty/alacritty.toml" ]; then
  ln -sf $config_folder/alacritty/default.toml "$HOME/.config/alacritty/alacritty.toml"
elif [ -e "$HOME/.config/alacritty/alacritty.toml" ] && [ ! -L "$HOME/.config/alacritty/alacritty.toml" ]; then
  cp -n "$HOME/.config/alacritty/alacritty.toml" "$HOME/.config/alacritty/alacritty.toml.pre-niri-setup"
  ln -sf $config_folder/alacritty/default.toml "$HOME/.config/alacritty/alacritty.toml"
fi

# Fastfetch: generate a theme-aware config and link it into place.
mkdir -p "$HOME/.config/fastfetch" "$HOME/.local/share/niri-setup"
fastfetch_config="$HOME/.config/fastfetch/config.jsonc"
fastfetch_target="$HOME/.local/share/niri-setup/fastfetch-config.jsonc"
fastfetch_install=true
if [ -e "$fastfetch_config" ] && [ ! -L "$fastfetch_config" ]; then
  fastfetch_backup="$fastfetch_config.pre-niri-setup"
  if [ ! -e "$fastfetch_backup" ]; then
    mv "$fastfetch_config" "$fastfetch_backup"
    echo "[INFO] existing Fastfetch config backed up to $fastfetch_backup"
  else
    echo "[WARN] preserving existing Fastfetch config; backup already exists at $fastfetch_backup"
    fastfetch_install=false
  fi
fi
python3 "$config_folder/scripts/sync-fastfetch-theme.py" "$config_folder/fastfetch/config.jsonc.in" "$fastfetch_target"
if [ "$fastfetch_install" = true ] && [ -e "$fastfetch_target" ]; then
  ln -sfn "$fastfetch_target" "$fastfetch_config"
fi

# Everything outside quickshell that renders theme colours: tmux/theme.conf,
# alacritty/{default,float}.toml, niri/layout.kdl and help/theme.css. Normally
# rewritten by services/Theme.qml on every palette change; running it here means
# a fresh install is themed correctly before quickshell has ever started.
python3 "$config_folder/scripts/sync-external-theme.py" --setup-home "$config_folder" || true

sed -i "s|\$NIRICONF|$config_folder|g" $(realpath "$config_folder/niri/spawn-at-startup.kdl")
sed -i "s|\$NIRICONF|$config_folder|g" $(realpath "$config_folder/niri/wallpapers.kdl")
sed -i "s|\$NIRICONF|$config_folder|g" $(realpath "$config_folder/niri/binds.kdl")
sed -i "s|\$NIRICONF|$config_folder|g" $(realpath "$config_folder/scripts/change-idle-time.sh")
sed -i "s|\$NIRICONF|$config_folder|g" $(realpath "$config_folder/scripts/change-power-profile.sh")
sed -i "s|\$NIRICONF|$config_folder|g" $(realpath "$config_folder/scripts/change-wallpaper.sh")
sed -i "s|\$NIRICONF|$config_folder|g" $(realpath "$config_folder/scripts/swayidle.sh")
sed -i "s|\$NIRICONF|$config_folder|g" $(realpath "$config_folder/scripts/toggle-waybar.sh")
sed -i "s|\$NIRICONF|$config_folder|g" $(realpath "$config_folder/scripts/wlogout.sh")
sed -i "s|\$NIRICONF|$config_folder|g" $(realpath "$config_folder/waybar/config")
sed -i "s|\$NIRICONF|$config_folder|g" $(realpath "$config_folder/waybar/style.css")
sed -i "s|\$NIRICONF|$config_folder|g" $(realpath "$config_folder/waybar/scripts/weather.sh")
sed -i "s|\$NIRICONF|$config_folder|g" $(realpath "$config_folder/waybar/scripts/colorpicker.sh")
sed -i "s|\$NIRICONF|$config_folder|g" $(realpath "$config_folder/waybar/scripts/powerdraw.sh")
sed -i "s|\$NIRICONF|$config_folder|g" $(realpath "$config_folder/waybar/style-macos.css")
sed -i "s|\$NIRICONF|$config_folder|g" $(realpath "$config_folder/scripts/set-volume.sh")
sed -i "s|\$NIRICONF|$config_folder|g" $(realpath "$config_folder/waybar/config")

# Install CPU performance sudoers rule
if [ -f "$config_folder/scripts/sudoers-cpu" ]; then
  echo "[INFO] installing CPU frequency sudoers rule..."
  sudo cp "$config_folder/scripts/sudoers-cpu" /etc/sudoers.d/cpu-freq
  sudo chmod 440 /etc/sudoers.d/cpu-freq
fi

# Install polkit rule for CPU frequency
if [ -f "$config_folder/scripts/50-cpu-freq.rules" ]; then
  echo "[INFO] installing CPU frequency polkit rule..."
  sudo mkdir -p /etc/polkit-1/rules.d
  sudo cp "$config_folder/scripts/50-cpu-freq.rules" /etc/polkit-1/rules.d/50-cpu-freq.rules
fi

# Sunset SDDM login theme (SDDM is live: systemctl is-enabled sddm == enabled)
if [ -d "$config_folder/sddm/sunset" ]; then
  echo "[INFO] Sunset SDDM theme available at $config_folder/sddm/sunset"
  echo "[HINT] to theme login screen: sudo $config_folder/sddm/install.sh"
  echo "[HINT] preview without reboot: sddm-greeter --test-mode --theme $config_folder/sddm/sunset"
fi

if niri validate &>/dev/null; then
  echo "[INFO] niri setup all completed"
  if tmux ls &>/dev/null; then
    echo "[HINT] tmux is running — reload it with: tmux source-file ~/.config/tmux/tmux.conf"
  fi
else
  echo "[ERROR] something went wrong. see the following output:"
  niri validate
fi
