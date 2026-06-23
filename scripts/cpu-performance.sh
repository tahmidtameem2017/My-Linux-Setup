#!/bin/bash
# Set CPU governor to performance mode for all cores
# This keeps CPU at maximum frequency even on battery

for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
    echo "performance" > "$cpu" 2>/dev/null
done

# Also set the energy_performance_preference to performance
for ep in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do
    echo "performance" > "$ep" 2>/dev/null
done
