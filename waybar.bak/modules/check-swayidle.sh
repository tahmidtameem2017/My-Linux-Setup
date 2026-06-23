#!/bin/bash
mode="$(cat $HOME/.local/state/idle-time)"
case $mode in
  "5 minutes")
    printf '{"text": "", "alt": "swayidle enabled", "tooltip": "Idle: 5m"}'
    ;;
  "10 minutes")
    printf '{"text": "", "alt": "swayidle enabled", "tooltip": "Idle: 10m"}'
    ;;
  "20 minutes")
    printf '{"text": "", "alt": "swayidle enabled", "tooltip": "Idle: 20m"}'
    ;;
  "30 minutes")
    printf '{"text": "", "alt": "swayidle enabled", "tooltip": "Idle: 30m"}'
    ;;
  "infinity")
    printf '{"text": "", "alt": "swayidle disabled", "tooltip": "Idle: disabled"}'
    ;;
  *)
    printf '{"text": "", "alt": "idle-time not found", "tooltip": "Idle: error"}'
    ;;
esac
