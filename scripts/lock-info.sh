#!/usr/bin/env bash
# lock-info.sh [section ...] — the lock screen's widget row, as plain text.
#
# The consumer bakes these lines into an image (see scripts/swaylock.sh), so the
# contract is the whole point of this file:
#   * one short line per line of stdout, nothing else — no word labels, no
#     prefixes; the one exception is the media line's leading Nerd Font glyph
#     (U+F001), which is a category marker rather than a label;
#   * always exit 0 — this runs while the user waits for the screen to lock, and
#     a missing reading must never turn into a failed lock screen;
#   * print nothing at all when there is nothing real to say. Never invent a
#     number and never write a diagnostic to stdout.
#
#   ./scripts/lock-info.sh                 # weather + media + battery
#   ./scripts/lock-info.sh media           # one section (any comma/space list)
#
# Sections: weather | media | battery | all (default).
#
# Why the cache exists: an open-meteo call costs ~1s here (DNS + TLS + payload)
# and the network is the one thing that can stall the lock. So the network is
# never on the hot path. quickshell's WeatherService only holds its reading in
# memory, so this script keeps its own cache at ~/.local/share/niri-setup/
# weather-lock.json (atomic write: temp file + mv) with a ~30 min TTL:
#
#   fresh, same place → print it, touch nothing;
#   stale, same place → print it, refresh in the background for the next lock;
#   place moved / file unreadable → print nothing, refresh (another city's
#                     temperature is worse than no line at all);
#   no cache at all  → one bounded foreground fetch (~1.3s cap), because there
#                     is nothing else to print; on failure, print nothing.
#
# The location comes from the shell's own weather-location.json (city/country/
# latitude/longitude, written by WeatherService.saveLocation()), so both read
# one source of truth, and it is the coordinates — not the city name — that
# decide whether a cached reading is still ours to show.
#
# Knobs (env, for testing and tuning):
#   LOCK_INFO_TTL=1800             cache lifetime, seconds
#   LOCK_INFO_FETCH_TIMEOUT=1.3    hard cap on the one foreground fetch, seconds
#   LOCK_INFO_REFRESH_TIMEOUT=10   budget for the background refresh, seconds
#   LOCK_INFO_RAIN_PCT=30          rain-hint threshold, %
#   LOCK_INFO_STATE_DIR=…          where the cache + weather-location.json live
#   LOCK_INFO_BAT_ROOT/BAT         sysfs power supply root / battery to read

set -Eeuo pipefail

# A trap, not careful coding, is what actually guarantees the exit-code promise:
# any command that slips through is a reason to stop quietly, not to fail.
trap 'exit 0' ERR

NIKI_HOME="${NIRI_SETUP_HOME:-$HOME/niri-setup}"
STATE_DIR="${LOCK_INFO_STATE_DIR:-$HOME/.local/share/niri-setup}"
CACHE="$STATE_DIR/weather-lock.json"
LOCATION="$STATE_DIR/weather-location.json"
# The background refresh logs here, next to the repo's other fire-and-forget
# jobs (swaybg.log, wallpaper-post.log) rather than in the state dir the shell
# and palette.sh read from.
LOG_DIR="$NIKI_HOME/.state"
LOG="$LOG_DIR/lock-info.log"
REFRESH_LOCK="$LOG_DIR/lock-info.lock"

TTL="${LOCK_INFO_TTL:-1800}"
# Two budgets on purpose: the one foreground fetch runs while the user is
# waiting, so it is capped hard; the background refresh has no audience and no
# deadline, so it gets room to actually succeed (measured here: ~1s, but only
# while the DNS/TLS cache is warm — a cold one can take several).
FETCH_TIMEOUT="${LOCK_INFO_FETCH_TIMEOUT:-1.3}"
REFRESH_TIMEOUT="${LOCK_INFO_REFRESH_TIMEOUT:-10}"
RAIN_PCT="${LOCK_INFO_RAIN_PCT:-30}"
BAT_ROOT="${LOCK_INFO_BAT_ROOT:-/sys/class/power_supply}"
BAT="${LOCK_INFO_BAT:-BAT0}"

# curl's stderr goes here. The foreground path is the lock screen and must stay
# silent; the background path has nobody to keep quiet for.
FETCH_STDERR=/dev/null

NOW="$(date +%s)"

# Same endpoints and parameters as quickshell/sunset/services/WeatherService.qml,
# plus hourly precipitation_probability for the "Rain 14:00" hint. One call, one
# process, no jq round trip per field.
WEATHER_URL="https://api.open-meteo.com/v1/forecast"
WEATHER_FIELDS_CURRENT="temperature_2m,relative_humidity_2m,apparent_temperature,is_day,precipitation,weather_code,wind_speed_10m"
WEATHER_FIELDS_DAILY="weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset"

# The cache holds {fetched_at, lat, lon, city, data}; `data` is the raw
# open-meteo response. Rendering is one jq program so a corrupt or half-written
# cache cannot produce a half-line, and so a missing optional field drops one
# line instead of the whole row.
#
# `condition` is a verbatim port of WeatherService.condition() — keep the two in
# step or the bar and the lock screen will disagree about the sky.
read -r -d '' RENDER_FILTER <<'JQ' || true
def condition:
    if . == 0 then "Clear sky"
    elif . == 1 then "Mainly clear"
    elif . == 2 then "Partly cloudy"
    elif . == 3 then "Overcast"
    elif . == 45 or . == 48 then "Fog"
    elif . >= 51 and . <= 57 then "Drizzle"
    elif . >= 61 and . <= 67 then "Rain"
    elif . >= 71 and . <= 77 then "Snow"
    elif . >= 80 and . <= 82 then "Rain showers"
    elif . >= 85 and . <= 86 then "Snow showers"
    elif . >= 95 then "Thunderstorm"
    else "Unknown conditions"
    end;

# " · Rain HH:MM" for the first of the next 12 hours that clears $pct, or ""
# (no hourly block, no chance of rain, or the cached day is already over).
# The hour window is counted in the *location's* local time (utc_offset_seconds
# applied to the epoch, then formatted as UTC), not the session's.
def rain_suffix($d; $now; $pct):
    ($d.hourly // {}) as $h
    | ([ ($h.time // []) | length, ($h.precipitation_probability // []) | length ] | min) as $n
    | (try (($now + ($d.utc_offset_seconds // 0)) | strftime("%Y-%m-%dT%H")) catch null) as $cur
    | if $cur == null then ""
      else
        ([ range(0; $n) as $i | { t: $h.time[$i], p: $h.precipitation_probability[$i] } ]
         | [.[] | select(.t >= $cur)][0:12]
         | ([.[] | select(.p >= $pct) | .t[11:16]] | .[0])) as $when
        | if $when == null then "" else " · Rain \($when)" end
      end;

.data as $d
| if ($d.current.temperature_2m // null) == null then empty
  else
    "\(($d.current.temperature_2m | round))°C · \($d.current.weather_code | condition)",
    ((($d.daily.temperature_2m_max // [])[0] // empty) as $hi
     | (($d.daily.temperature_2m_min // [])[0] // empty) as $lo
     | "H:\($hi | round)° L:\($lo | round)°" + rain_suffix($d; $now; $pct))
  end
JQ

say() {
    [[ -n "${1:-}" ]] || return 0
    printf '%s\n' "$1"
}

have() {
    command -v "$1" >/dev/null 2>&1
}

is_uint() {
    [[ "$1" =~ ^[0-9]+$ ]]
}

# --- weather ---------------------------------------------------------------

# City/lat/lon from the shell's saved location. Sets LAT/LON; returns 1 when
# there is no usable location, which is a normal state, not an error.
read_location() {
    LAT=""
    LON=""
    CITY=""
    [[ -s "$LOCATION" ]] || return 1
    local raw
    raw=$(jq -r '[ (.latitude // empty | tostring),
                   (.longitude // empty | tostring),
                   (.city    // empty | tostring) ] | @tsv' "$LOCATION" 2>/dev/null) || return 1
    local lat lon city
    IFS=$'\t' read -r lat lon city <<<"$raw"
    [[ "$lat" =~ ^-?[0-9]+(\.[0-9]+)?$ ]] || return 1
    [[ "$lon" =~ ^-?[0-9]+(\.[0-9]+)?$ ]] || return 1
    # Range-check the integer part: a corrupt file should not become a request
    # for a place on the other side of the planet.
    local lat_i="${lat%%.*}" lon_i="${lon%%.*}"
    if ((lat_i < -90 || lat_i > 90 || lon_i < -180 || lon_i > 180)); then
        return 1
    fi
    LAT="$lat"
    LON="$lon"
    CITY="${city//[$'\t\n\r']/ }"
    return 0
}

# fresh  — under TTL, same location: print it, nothing else to do.
# stale  — past the TTL but still ours: print it, refresh in the background.
# moved  — the saved location changed, so the cached reading is another city's.
# junk   — we cannot parse the cache. Only these two suppress output.
# none   — no cache at all.
cache_state() {
    if [[ ! -s "$CACHE" ]]; then
        printf 'none'
        return 0
    fi
    local info
    info=$(jq -r '[ (.fetched_at | tonumber? // 0), (.lat | tostring), (.lon | tostring) ] | @tsv' \
        "$CACHE" 2>/dev/null) || info=""
    if [[ -z "$info" ]]; then
        printf 'junk'
        return 0
    fi
    local fetched lat lon age
    IFS=$'\t' read -r fetched lat lon <<<"$info"
    if [[ -z "${LAT:-}" || "$lat" != "$LAT" || "$lon" != "$LON" ]]; then
        # A moved location makes the old reading wrong, not merely old — one
        # wrong city's temperature on the lock screen is worse than no line, so
        # this waits for the refresh like the junk case does.
        printf 'moved'
        return 0
    fi
    if ! is_uint "${fetched%%.*}"; then
        printf 'junk'
        return 0
    fi
    # A timestamp in the future (clock moved, cache copied between machines) is
    # not fresh either — a negative age would otherwise be "forever young".
    # The fraction is dropped before the arithmetic: jq may hand back "…610.5",
    # and bash arithmetic chokes on that.
    age=$((NOW - ${fetched%%.*}))
    if ((age >= 0 && age < TTL)); then
        printf 'fresh'
    else
        printf 'stale'
    fi
}

write_cache() {
    local payload="$1" tmp
    [[ -n "$LAT" && -n "$LON" ]] || return 1
    mkdir -p "$STATE_DIR" 2>/dev/null || return 1
    tmp="$CACHE.tmp.$$"
    # --argjson is also the validator: a truncated or non-JSON payload fails
    # here and never replaces a good cache.
    if jq -n --argjson at "$NOW" --argjson lat "$LAT" --argjson lon "$LON" \
        --arg city "$CITY" --argjson data "$payload" \
        '{fetched_at: $at, lat: $lat, lon: $lon, city: $city, data: $data}' \
        >"$tmp" 2>/dev/null; then
        # Only publish a payload that actually has a reading in it, so a valid-
        # looking but empty JSON never replaces the last good cache.
        if jq -e '.data.current.temperature_2m != null' "$tmp" >/dev/null 2>&1; then
            mv -f "$tmp" "$CACHE"
            return 0
        fi
    fi
    rm -f "$tmp"
    return 1
}

fetch_weather() {
    local timeout="${1:-$FETCH_TIMEOUT}" payload
    have curl || return 1
    payload=$(curl -fsS --max-time "$timeout" --connect-timeout "$timeout" -G "$WEATHER_URL" \
        --data-urlencode "latitude=$LAT" \
        --data-urlencode "longitude=$LON" \
        --data-urlencode "current=$WEATHER_FIELDS_CURRENT" \
        --data-urlencode "daily=$WEATHER_FIELDS_DAILY" \
        --data-urlencode 'hourly=precipitation_probability' \
        --data-urlencode 'timezone=auto' \
        --data-urlencode 'forecast_days=1' 2>>"$FETCH_STDERR") || return 1
    [[ -n "$payload" ]] || return 1
    write_cache "$payload"
}

# Detached, and fully detached: a backgrounded child that inherits stdout keeps
# the caller's pipe open, so `out=$(lock-info.sh)` would hang until curl exits
# (the swaybg trap, see scripts/wallpaper.sh). flock keeps a second lock screen
# from firing a second fetch while one is already in flight.
spawn_refresh() {
    [[ -n "${LAT:-}" && -n "${LON:-}" ]] || return 0
    mkdir -p "$LOG_DIR" 2>/dev/null || return 0
    {
        flock -n 9 || exit 0
        FETCH_STDERR="$LOG"
        fetch_weather "$REFRESH_TIMEOUT" || true
    } 9>"$REFRESH_LOCK" </dev/null >>"$LOG" 2>&1 &
    disown || true
    return 0
}

render_cache() {
    [[ -s "$CACHE" ]] || return 0
    jq -r --argjson now "$NOW" --argjson pct "$RAIN_PCT" "$RENDER_FILTER" "$CACHE" 2>/dev/null || true
    return 0
}

section_weather() {
    have jq || return 0
    have curl || return 0
    read_location || return 0

    case "$(cache_state)" in
    fresh)
        render_cache
        ;;
    none)
        # The only call that makes the user wait, and only until a cache exists.
        # Past that the lock screen never touches the network again. open-meteo
        # answered in 1.0s four times out of five here and 1.5-3s the rest, so
        # the cap really is a coin flip on a cold cache — which is exactly why
        # the failure branch only spawns the refresh and prints nothing.
        if fetch_weather; then
            render_cache
        else
            spawn_refresh
        fi
        ;;
    stale)
        # The everyday case: never make the user wait, but keep the cache honest
        # for the lock after this one.
        render_cache
        spawn_refresh
        ;;
    *)
        # moved or junk: there is nothing we can vouch for, so print nothing and
        # fix the cache for next time.
        spawn_refresh
        ;;
    esac
    return 0
}

# --- battery ---------------------------------------------------------------

# Estimated minutes left, or nothing. energy_now/power_now come from the same
# driver and so share a unit family (µWh over µW is hours straight off), which
# is why no capacity maths is needed here — only a driver reporting power_now 0
# or absurd numbers is filtered out, because "0m left" is worse than no line.
battery_left() {
    local dir="$1" status="$2" energy power mins
    case "$status" in
    charging | discharging) ;;
    *) return 0 ;;
    esac
    energy=$(cat "$dir/energy_now" 2>/dev/null) || return 0
    power=$(cat "$dir/power_now" 2>/dev/null) || return 0
    if ! is_uint "$energy" || ! is_uint "$power"; then
        return 0
    fi
    if ((power == 0)); then
        return 0
    fi
    mins=$((energy * 60 / power))
    if ((mins <= 0 || mins > 24 * 60)); then
        return 0
    fi
    if ((mins >= 60)); then
        printf '%dh %02dm' "$((mins / 60))" "$((mins % 60))"
    else
        printf '%dm' "$mins"
    fi
}

section_battery() {
    local dir="$BAT_ROOT/$BAT"
    local cap status line left
    cap=$(cat "$dir/capacity" 2>/dev/null) || return 0
    is_uint "$cap" || return 0
    status=$(cat "$dir/status" 2>/dev/null) || status=""
    status="${status,,}"

    line="$cap%"
    case "$status" in
    charging) line+=" · charging" ;;
    discharging) line+=" · discharging" ;;
    full) line+=" · full" ;;
    *) ;;
    esac
    left=$(battery_left "$dir" "$status") || left=""
    if [[ -n "$left" ]]; then
        if [[ "$status" == "charging" ]]; then
            line+=" · $left to full"
        else
            line+=" · $left left"
        fi
    fi
    say "$line"
    return 0
}

# --- media (now playing) ---------------------------------------------------
# One line, and only when something is genuinely PLAYING. This is the section
# that has to be silent by default: a lock screen that always shows a media row
# is either stale (paused 40 minutes ago) or lying. So the gate is the MPRIS
# status, checked per player, and anything other than "Playing" prints nothing.
#
# Why playerctl and not a direct D-Bus call: it is the same binary the bar's
# media widget drives (services/MediaService.qml), so the two can never disagree
# about which player is current or what the title is.
#
# Bounded on purpose. This runs inside the lock path — the user is watching a
# spinner — so the whole probe is one `timeout` around a subshell, and the
# per-player calls are bounded too. No network, so it is milliseconds in
# practice; the caps exist for a wedged MPRIS service, not for slow media.
MEDIA_TIMEOUT="${LOCK_INFO_MEDIA_TIMEOUT:-1.0}"
MEDIA_FALLBACK="${LOCK_INFO_MEDIA_FALLBACK:-}" # app name if the track has no title

section_media() {
    have playerctl || return 0
    command -v timeout >/dev/null 2>&1 || return 0

    local line
    line=$(timeout "$MEDIA_TIMEOUT" bash -c '
        set -u
        for p in $(playerctl --list-all 2>/dev/null); do
            st=$(playerctl -p "$p" status 2>/dev/null | head -1)
            [ "$st" = "Playing" ] || continue
            title=$(playerctl -p "$p" metadata title 2>/dev/null | head -1)
            artist=$(playerctl -p "$p" metadata artist 2>/dev/null | head -1)
            printf "%s\t%s" "$title" "$artist"
            exit 0
        done
    ' 2>/dev/null) || return 0
    [[ -n "$line" ]] || return 0

    local title artist out
    IFS=$'\t' read -r title artist <<<"$line"
    # Trim: playerctl prints an empty line rather than nothing for a missing tag.
    title="${title#"${title%%[![:space:]]*}"}"
    title="${title%"${title##*[![:space:]]}"}"
    artist="${artist#"${artist%%[![:space:]]*}"}"
    artist="${artist%"${artist##*[![:space:]]}"}"

    if [[ -n "$title" && -n "$artist" && "$title" != "$artist" ]]; then
        out="$artist — $title"
    elif [[ -n "$title" ]]; then
        out="$title"
    else
        # No title tag at all (some streams): the app name is better than nothing,
        # but only when one was supplied, since guessing a label is worse.
        out="$MEDIA_FALLBACK"
    fi
    [[ -n "$out" ]] || return 0

    # The U+F001 music note is the category marker, same idea as the lock glyph
    # in the lock screen's own hint. It is a glyph, not a word label, so the
    # "no labels" rule still holds.
    printf '\xEF\x80\x81 %s\n' "$out"
    return 0
}

# --- main ------------------------------------------------------------------

main() {
    local -a requested=()
    if [[ $# -eq 0 ]]; then
        requested=(weather media battery)
    else
        requested=("$@")
    fi

    local want_weather=0 want_media=0 want_battery=0 arg
    local -a parts=()
    for arg in "${requested[@]}"; do
        if [[ -z "${arg//[[:space:],]/}" ]]; then
            # An empty argument means "no filter" (e.g. an unset shell variable),
            # not "no sections" — the default set is the point of the no-arg call.
            want_weather=1
            want_media=1
            want_battery=1
            continue
        fi
        # "weather media" and "weather,media" both mean two sections.
        parts=()
        read -r -a parts <<<"${arg//,/ }" || true
        for arg in "${parts[@]}"; do
            case "${arg,,}" in
            all | default)
                want_weather=1
                want_media=1
                want_battery=1
                ;;
            weather) want_weather=1 ;;
            media | nowplaying | np | music) want_media=1 ;;
            battery | power) want_battery=1 ;;
            *)
                printf '[lock-info] ignoring unknown section: %s\n' "$arg" >&2
                ;;
            esac
        done
    done

    # Weather first: it is the line people look for. Then media, because it is
    # the only line here that appears and disappears — and then battery as the
    # footnote. A paused player prints nothing at all (see section_media), so
    # this ordering costs nothing when there is no music.
    if ((want_weather == 1)); then
        section_weather
    fi
    if ((want_media == 1)); then
        section_media
    fi
    if ((want_battery == 1)); then
        section_battery
    fi
    exit 0
}

main "$@"