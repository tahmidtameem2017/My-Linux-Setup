#!/bin/bash
# Set volume with 100% cap

ACTION="$1"
CURRENT=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ | awk '{print int($2 * 100)}')

case "$ACTION" in
    up)
        NEW=$((CURRENT + 2))
        ;;
    down)
        NEW=$((CURRENT - 2))
        ;;
    *)
        exit 1
        ;;
esac

# Cap at 100%
if [ "$NEW" -gt 100 ]; then
    NEW=100
fi

# Ensure not below 0
if [ "$NEW" -lt 0 ]; then
    NEW=0
fi

wpctl set-volume @DEFAULT_AUDIO_SINK@ "${NEW}%"
