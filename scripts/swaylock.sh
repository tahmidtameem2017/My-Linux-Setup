#!/bin/bash
niri msg action do-screen-transition --delay-ms 300
swaylock \
  --clock \
  --screenshots \
  --daemonize \
  --fade-in 0.2 \
  --ignore-empty-password \
  --font "JetBrains Mono Bold" \
  --indicator \
  --indicator-radius 150 \
  --effect-scale 0.4 \
  --effect-vignette 0.2:0.5 \
  --effect-blur 4x2 \
  --datestr "%A, %b %d" \
  --timestr "%k:%M" \
  --key-hl-color e85d2ff2 \
  --ring-color e85d2ff2 \
  --text-color f7c7a1e6 \
  --inside-clear-color 0a0a0af2 \
  --ring-clear-color ff8b4af2 \
  --text-clear-color f7c7a1e6 \
  --inside-ver-color 0a0a0af2 \
  --ring-ver-color ff8b4af2 \
  --text-ver-color f7c7a1e6 \
  --bs-hl-color 7c8a6aff \
  --inside-wrong-color c30505ff \
  --ring-wrong-color c30505ff \
  --text-wrong-color ffffffff
