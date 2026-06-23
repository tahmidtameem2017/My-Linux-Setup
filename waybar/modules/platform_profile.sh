#!/bin/bash
# Platform profile script for waybar

profile=$(power-profiles-daemon 2>/dev/null || echo "balanced")

case "$profile" in
  *performance*|*Performance*)
    echo '{"text": "", "tooltip": "Performance", "class": "performance"}'
    ;;
  *balanced*|*Balanced*|*default*)
    echo '{"text": "", "tooltip": "Balanced", "class": "balanced"}'
    ;;
  *power-saver*|*quiet*|*Quiet*)
    echo '{"text": "", "tooltip": "Power Saver", "class": "quiet"}'
    ;;
  *)
    echo '{"text": "", "tooltip": "Unknown", "class": "default"}'
    ;;
esac
