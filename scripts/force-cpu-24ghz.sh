#!/bin/bash
# Force CPU to run at 2.4GHz+ minimum on all cores
# This overrides power-saving that throttles to 500MHz

# Switch governor to performance (not schedutil)
for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
    echo "performance" > "$cpu" 2>/dev/null
done

# Set minimum frequency to 2.4GHz (2400000 kHz)
for freq in /sys/devices/system/cpu/cpu*/cpufreq/scaling_min_freq; do
    echo "2400000" > "$freq" 2>/dev/null
done

# Also set energy performance preference for Intel P-states
for ep in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do
    echo "performance" > "$ep" 2>/dev/null
done

# Disable intel_pstate no_turbo if you want turbo boost
# echo "0" > /sys/devices/system/cpu/intel_pstate/no_turbo 2>/dev/null

echo "CPU locked at 2.4GHz+ performance mode"
