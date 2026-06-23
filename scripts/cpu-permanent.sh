#!/bin/bash
# Set CPU to performance mode (2.4GHz+) permanently
# Run at startup via niri config

# Set governor to performance for all CPUs
for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
    echo "performance" > "$cpu" 2>/dev/null
done

# Set energy performance preference to performance (for Intel P-states)
for ep in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do
    echo "performance" > "$ep" 2>/dev/null
done

# Set minimum frequency to 2.4GHz (2400000 kHz = 2.4GHz)
# This prevents throttling down to 500MHz on battery
for freq in /sys/devices/system/cpu/cpu*/cpufreq/scaling_min_freq; do
    echo "2400000" > "$freq" 2>/dev/null
done

echo "✓ CPU locked at 2.4GHz+ performance mode"
