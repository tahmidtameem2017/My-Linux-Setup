#!/bin/bash
# Limit volume to 100% - run this after each volume change

VOLUME=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ | awk '{print int($2 * 100)}')

if [ "$VOLUME" -gt 100 ]; then
    wpctl set-volume @DEFAULT_AUDIO_SINK@ 100%
fi
