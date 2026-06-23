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
    alacritty
    brightnessctl
    btop
    cliphist
    dunst
    fuzzel
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
    starship
    swaybg
    swayidle
    swaylock-effects
    swww
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

if niri validate &>/dev/null; then
  echo "[INFO] niri setup all completed"
else
  echo "[ERROR] something went wrong. see the following output:"
  niri validate
fi
