#!/bin/bash
# Set CPU governor to performance mode for all cores
# Run at startup to keep CPU at maximum frequency

for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
    echo "performance" > "$cpu" 2>/dev/null
done
