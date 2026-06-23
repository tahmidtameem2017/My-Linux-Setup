# CPU Performance Fix

## Problem
CPU was throttling down to 500 MHz on battery power, causing poor performance.

## Solution
The fix forces the CPU to run at a minimum of 2.4 GHz even on battery power by:
1. Setting the CPU governor to `performance` mode
2. Setting the minimum frequency to 2.4 GHz (2400000 kHz)
3. Setting energy performance preference to `performance`

## Installation

### Option 1: Run setup script (Recommended)
```bash
./setup.sh
```
This will automatically install the sudoers rule and polkit rule.

### Option 2: Manual installation
```bash
# Install sudoers rule
sudo cp scripts/sudoers-cpu /etc/sudoers.d/cpu-freq
sudo chmod 440 /etc/sudoers.d/cpu-freq

# Install polkit rule
sudo mkdir -p /etc/polkit-1/rules.d
sudo cp scripts/50-cpu-freq.rules /etc/polkit-1/rules.d/50-cpu-freq.rules
```

## Verification

After installation, restart niri or run manually:
```bash
sudo /home/me/niri-setup/scripts/cpu-permanent.sh
```

Check the current frequency:
```bash
cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq
```

All values should show `2400000` or higher (in kHz).

## Files Modified

- `niri/spawn-at-startup.kdl` - Runs the script at niri startup with sudo
- `scripts/cpu-permanent.sh` - Main script that sets CPU frequency
- `scripts/sudoers-cpu` - Sudoers rule for passwordless execution
- `scripts/50-cpu-freq.rules` - Polkit rule for authorization
