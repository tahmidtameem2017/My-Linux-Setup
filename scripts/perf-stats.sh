#!/usr/bin/env bash
# perf-stats.sh — one-shot system snapshot for the bar's on-demand
# performance pill (quickshell services/PerfService.qml). Prints one
# line of integer key=value pairs:
#   cpu=<0-100> gpu=<MHz|0> gpuBusy=<0-100|-1> memUsed=<MiB>
#   memTotal=<MiB> batPct=<0-100|-1> batCharging=<0|1>
# 0 / -1 mean "no sensor": the pill hides that segment.
#
# Costs ~0.5s (the CPU sample window). PerfService runs it every 2s
# and only while the pill is on, so the sample window is fine.
set -u

sum() { local s=0 v; for v in "$@"; do s=$((s + v)); done; echo "$s"; }

# --- CPU: busy share of the total /proc/stat delta over 0.5s ---
# Fields after the "cpu" label: user nice system idle iowait ...
# idle_all = idle + iowait; everything else is work.
read -r -a prev < <(grep -m1 '^cpu ' /proc/stat)
sleep 0.5
read -r -a now < <(grep -m1 '^cpu ' /proc/stat)
prev_idle=$(( ${prev[4]} + ${prev[5]} ))
now_idle=$(( ${now[4]} + ${now[5]} ))
prev_tot=$(sum "${prev[@]:1}")
now_tot=$(sum "${now[@]:1}")
d_idle=$(( now_idle - prev_idle ))
d_tot=$(( now_tot - prev_tot ))
cpu=0
if (( d_tot > 0 )); then
    cpu=$(( 100 * (d_tot - d_idle) / d_tot ))
fi

# --- GPU: AMD/Intel sysfs counters first, nvidia-smi fallback.
# gpu_busy_percent only exists on newer amdgpu kernels, so busy% is
# reported when available and the pill falls back to MHz.
gpu=0
gpu_busy=-1
for f in /sys/class/drm/card*/gt_cur_freq_mhz; do
    [[ -r $f ]] && { gpu=$(<"$f"); break; }
done
for f in /sys/class/drm/card*/gpu_busy_percent; do
    [[ -r $f ]] && { gpu_busy=$(<"$f"); break; }
done
if (( gpu == 0 )) && command -v nvidia-smi >/dev/null 2>&1; then
    IFS=', ' read -r g u < <(nvidia-smi --query-gpu=clocks.current.graphics,utilization.gpu \
        --format=csv,noheader,nounits 2>/dev/null | head -n1)
    gpu=${g:-0}
    gpu_busy=${u:--1}
fi

# --- Memory (MiB) ---
mem_total=$(awk '/^MemTotal:/ {printf "%d", $2/1024}' /proc/meminfo)
mem_avail=$(awk '/^MemAvailable:/ {printf "%d", $2/1024}' /proc/meminfo)
mem_used=$(( mem_total - mem_avail ))

# --- Battery: sysfs capacity first (laptops), upower fallback. ---
bat_pct=-1
bat_charging=0
for d in /sys/class/power_supply/BAT*; do
    [[ -d $d ]] || continue
    cap=$(cat "$d/capacity" 2>/dev/null) || continue
    st=$(cat "$d/status" 2>/dev/null)
    bat_pct=$(( 10#$cap ))
    [[ $st == Charging ]] && bat_charging=1
    break
done
if (( bat_pct < 0 )) && command -v upower >/dev/null 2>&1; then
    dev=$(upower -e 2>/dev/null | grep -m1 -E 'BAT|battery')
    if [[ -n $dev ]]; then
        info=$(upower -i "$dev" 2>/dev/null)
        pct=$(awk '/percentage:/ {printf "%d", $2}' <<<"$info")
        state=$(awk '/state:/ {print $2}' <<<"$info")
        [[ -n $pct ]] && bat_pct=$pct
        [[ $state == charging ]] && bat_charging=1
    fi
fi

echo "cpu=$cpu gpu=$gpu gpuBusy=$gpu_busy memUsed=$mem_used memTotal=$mem_total batPct=$bat_pct batCharging=$bat_charging"
