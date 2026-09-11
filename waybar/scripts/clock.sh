#!/bin/sh
# Deprecated: kept as fallback. Active bar uses waybar's native "clock"
# module (see waybar/config) with built-in themed calendar tooltip.
# GNU `date` uses %n for newline (not \n), and JSON needs \n escaped as \\n.
text=$(date +%H:%M)
tip_date=$(date '+%A, %d %B %Y')
tip_time=$(date +%H:%M:%S)
printf '{"text":"%s","tooltip":"%s\\n%s"}\n' "$text" "$tip_date" "$tip_time"
