#!/usr/bin/env bash
# wallust-theme.sh <image-path>
#
# Re-theme the sunset bar + menus to match a wallpaper ("Wallpaper Match"
# + 3 wallpaper-derived variants).
#
# Pipeline (×4 variants, same image, DIFFERENT wallust palettes):
#   image -> `wallust run` (repo template wallust/templates/sunset.json,
#   throwaway per-variant config dir, wallust cache reused) -> raw palette JSON
#   -> python3 token map -> ~/.local/share/niri-setup/theme-wallpaper*.json
#   (flat object, EXACTLY the 11 Theme.qml keys). Theme.qml watches those
#   files live via FileView, so the bar + menus follow without a restart.
#
# Each variant asks wallust for its own palette family, which is where the hue
# diversity comes from:
#   wallpaper         -> Wallpaper Match:  dark      vivid base tone
#   wallpaper-vibrant -> Wallpaper Vibrant: darkcomp  complementary, most
#                                                 hue-distinct from `dark`
#   wallpaper-muted   -> Wallpaper Muted:  softdark  soft/desaturated pastel
#   wallpaper-soft    -> Wallpaper Soft:   light     lightest tint, surfaces
#                                                 stay dark (the mapper forces
#                                                 the bg down, keeping only hue)
#
# Measured on /tmp/test_wallpaper.jpg = workspace.jpg 1920x1080:
#   dark     : bg #010000 fg #F8F3E4 accent #964230 h11  s0.68 (baseline vivid)
#   darkcomp : bg #010000 fg #F8F3E4 accent #228196 h191 s0.77 dh180 ds+9
#   softdark : bg #4B7A58 fg #E2E2E1 accent #964230 bgdiff 284 (sage muted)
#   light    : bg #D3D3D1 fg #6A6350 accent #964230 bgdiff 630 text dark
#   harddark : bg #1F2621 bgdiff 101 (less distinct than darkcomp, so darkcomp
#              is the vibrant slot and harddark is unused)
#   -> the 3 most distinct from dark are darkcomp (hue), softdark (weight),
#      light (inverted/light). wallust-palette.py's VARIANT_TONE then nudges
#      each one further apart in saturation/lightness so they stay
#      distinguishable even on a low-colour wallpaper.
#
#   Also tested backends (full, resized, wal, thumb, kmeans) and colorspaces
#   (lab, lch, salience) — they also produce distinct accents (e.g. dark/lch
#   #704636 vs dark/salience #A52D1C vs fastresize #964230) and could be
#   swapped in if more hue diversity is wanted, but palette family already
#   provides the diversity without extra complexity. Using wallust's built-in
#   palettes keeps the mapping stable across any wallpaper.
#
# wallust-palette -> sunset-token mapping is documented in
# scripts/wallust-palette.py's header.
#
# Contracts:
#   * FAST: one 4-way parallel `wallust run` is ~0.005-0.25s per variant
#     (fastresize backend, lab colorspace default); python map is milliseconds.
#     Each variant gets its OWN config dir, which is what makes running them
#     concurrently safe — a shared wallust.toml made them race, which is why
#     this used to be sequential and why only `dark` was ever extracted.
#   * NEVER FAILS: exit 0 always. Every step is guarded (|| true), so
#     scripts/wallpaper.sh can fire-and-forget this in the background.
#   * SILENT: wallust runs with -s (no terminal color sequences) and -q,
#     against throwaway -d config dirs (never reads/writes ~/.config/wallust,
#     never sends hooks/sequences anywhere).
#   * WATCHER-SAFE: the output files are rewritten in place (same inode) so
#     the QML FileView watches survive updates.

# Separate process from the caller; still, never propagate a failure.
set -uo pipefail || true

IMG="${1:-}"
OUT_DIR="${HOME}/.local/share/niri-setup"
OUT_FILE="${OUT_DIR}/theme-wallpaper.json"
OUT_FILE_VIBRANT="${OUT_DIR}/theme-wallpaper-vibrant.json"
OUT_FILE_MUTED="${OUT_DIR}/theme-wallpaper-muted.json"
OUT_FILE_SOFT="${OUT_DIR}/theme-wallpaper-soft.json"
NIKI_HOME="${NIRI_SETUP_HOME:-$HOME/niri-setup}"
REPO_TEMPLATE="${NIKI_HOME}/wallust/templates/sunset.json"
LOG_FILE="${NIKI_HOME}/.state/wallust-theme.log"

# The one and only exit path: success from the caller's point of view.
finish() { exit 0; }
trap finish EXIT

[[ -n "${IMG}" ]] || exit 0
[[ -f "${IMG}" ]] || exit 0
command -v wallust >/dev/null 2>&1 || exit 0
command -v python3 >/dev/null 2>&1 || exit 0

# Absolute path (wallust cache-keys on it; harmless either way).
IMG_ABS="$(realpath -m "${IMG}" 2>/dev/null || printf '%s' "${IMG}")"

mkdir -p "${OUT_DIR}" "${NIKI_HOME}/.state" || exit 0
CFG_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/wallust-sunset.XXXXXX" 2>/dev/null)" || exit 0
trap 'rm -rf "${CFG_ROOT}" >/dev/null 2>&1; finish' EXIT

START="${SECONDS:-0}"

# wallust variant -> (wallust palette family, output file).
SPECS=(
  "dark:${OUT_FILE}"
  "darkcomp:${OUT_FILE_VIBRANT}"
  "softdark:${OUT_FILE_MUTED}"
  "light:${OUT_FILE_SOFT}"
)

# Emit one throwaway wallust config dir with its own copy of the template.
write_cfg() {
  local dir="$1" raw="$2"
  mkdir -p "${dir}/templates" || return 1
  if [[ -f "${REPO_TEMPLATE}" ]]; then
    cp -f "${REPO_TEMPLATE}" "${dir}/templates/sunset.json" || return 1
  else
    # Minimal embedded fallback so a missing template can never break the
    # pipeline.
    {
      printf '{\n  "background": "{{background}}",\n  "foreground": "{{foreground}}",\n'
      printf '  "color0": "{{color0}}",\n  "color1": "{{color1}}",\n  "color2": "{{color2}}",\n'
      printf '  "color3": "{{color3}}",\n  "color4": "{{color4}}",\n  "color5": "{{color5}}",\n'
      printf '  "color6": "{{color6}}",\n  "color8": "{{color8}}"\n}\n'
    } >"${dir}/templates/sunset.json" || return 1
  fi
  printf '[templates]\nsunset = { template = "sunset.json", target = "%s" }\n' \
    "${raw}" >"${dir}/wallust.toml" || return 1
}

# Phase 1: extract all four raw palettes concurrently. Separate config dirs, so
# no shared-state race (this is what let the other three families be extracted
# at all — sharing one wallust.toml made concurrent runs clobber each other).
RAW_DIRS=()
for spec in "${SPECS[@]}"; do
  variant="${spec%%:*}"
  dir="${CFG_ROOT}/${variant}"
  raw="${CFG_ROOT}/${variant}.raw.json"
  write_cfg "${dir}" "${raw}" || exit 0
  RAW_DIRS+=("${variant}:${dir}:${raw}")
done

for entry in "${RAW_DIRS[@]}"; do
  IFS=: read -r variant dir raw <<<"${entry}"
  wallust run -d "${dir}" -s -q -p "${variant}" "${IMG_ABS}" >/dev/null 2>&1 &
done
wait

# Phase 2: map raw palette -> the 11 tokens, in file order. Sequential: these
# are milliseconds each, and serialising keeps the four writes deterministic.
VARIANT_OUT=""
VARIANT_FAILED=""
for spec in "${SPECS[@]}"; do
  variant="${spec%%:*}"
  output="${spec#*:}"
  raw="${CFG_ROOT}/${variant}.raw.json"
  # A failed variant must leave its output file ALONE. It used to be truncated
  # first (`: >"$output"`), so one wallust hiccup replaced a good palette with a
  # zero-byte file while the log still said OK — and a zero-byte file is worse
  # than a stale one: Theme.qml rejects it and keeps the previous palette, so
  # the picker showed a variant that no longer existed. map_palette() computes
  # the whole dict before touching the file, so simply not writing is enough.
  if [[ ! -s "${raw}" ]]; then
    VARIANT_FAILED+=" ${variant}:no-raw"
    continue
  fi
  mapped="$(python3 "${NIKI_HOME}/scripts/wallust-palette.py" "${variant}" "${raw}" "${output}" 2>/dev/null)" \
    || { VARIANT_FAILED+=" ${variant}:map-failed"; continue; }
  if [[ ! -s "${output}" ]]; then
    VARIANT_FAILED+=" ${variant}:empty"
    continue
  fi
  VARIANT_OUT+=" ${variant}:${mapped}"
done

# At least the main (Wallpaper Match) file must exist, otherwise there is no
# palette for auto-theming to follow.
[[ -s "${OUT_FILE}" ]] || exit 0

ELAPSED=$(( ${SECONDS:-0} - START ))
# Say PARTIAL when a variant did not make it. Reporting OK while listing three
# of four families is how a stale palette survives a failed extraction without
# anybody noticing.
if [[ -n "${VARIANT_FAILED}" ]]; then
  STATUS="PARTIAL"
else
  STATUS="OK"
fi
{ printf '[%s] %s img=%s %ss ok:%s failed:%s\n' "$(date '+%F %T')" "${STATUS}" \
    "$(basename "${IMG_ABS}")" "${ELAPSED}" "${VARIANT_OUT:- none}" \
    "${VARIANT_FAILED:- none}"; } >>"${LOG_FILE}" 2>&1 || true

exit 0