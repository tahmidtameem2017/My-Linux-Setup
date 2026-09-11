#!/usr/bin/env bash
set -euo pipefail

WALL_DIR="${WALL_DIR:-$HOME/Pictures/Wallpapers}"
COUNT="${1:-10}"
API_KEY_FILE="${API_KEY_FILE:-$HOME/.config/wallhaven/api_key}"

# --- Dependency check ---
for cmd in curl jq gum; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "[ERROR] missing dependency: $cmd"
        exit 1
    fi
done

mkdir -p "$WALL_DIR"

# --- Optional API key for higher rate limits ---
API_KEY=""
RATE_DELAY=1.5
if [[ -f "$API_KEY_FILE" ]]; then
    API_KEY=$(cat "$API_KEY_FILE")
    RATE_DELAY=0.4
fi

# --- URL-encode a string for safe API requests ---
urlencode() {
    local str="$1"
    local encoded=""
    local c
    for (( i = 0; i < ${#str}; i++ )); do
        c="${str:$i:1}"
        case "$c" in
            [a-zA-Z0-9.~_-]) encoded+="$c" ;;
            *) printf -v encoded '%s%%%02X' "$encoded" "'$c'" ;;
        esac
    done
    echo "$encoded"
}

# --- Rate-limited fetch with retry on 429 ---
fetch_json() {
    local url="$1"
    sleep "$RATE_DELAY"
    local resp
    resp=$(curl -s -w "\n%{http_code}" "$url" 2>/dev/null || true)
    local http_code
    http_code=$(echo "$resp" | tail -1)
    local body
    body=$(echo "$resp" | sed '$d')

    if [[ "$http_code" == "429" ]]; then
        echo "[WARN] Rate limited (429). Waiting 10s..." >&2
        sleep 10
        resp=$(curl -s -w "\n%{http_code}" "$url" 2>/dev/null || true)
        http_code=$(echo "$resp" | tail -1)
        body=$(echo "$resp" | sed '$d')
    fi

    if [[ "$http_code" != "200" ]]; then
        echo "[ERROR] HTTP $http_code from Wallhaven" >&2
        echo '{"error":"http_error"}'
        return
    fi
    echo "$body"
}

download_file() {
    local url="$1"
    local dest="$2"
    sleep "$RATE_DELAY"
    local code
    code=$(curl -sL -o "$dest" "$url" -w "%{http_code}" 2>/dev/null || echo "000")
    echo "$code"
}

# --- Category picker ---
categories=(
    "landscape:Mountains, forests, oceans, horizons"
    "nature:Wildlife, plants, natural details"
    "space:Galaxies, nebulas, planets, stars"
    "city:Urban skylines, streets, nightlife"
    "architecture:Buildings, structures, interiors, bridges"
    "car:Vehicles, automotive, racing"
    "abstract:Artistic, patterns, gradients, minimal"
    "custom:Enter your own search query"
)

choice=$(printf "%s\n" "${categories[@]}" | gum choose --header "Pick a wallpaper category:" --height 12)
[[ -z "$choice" ]] && exit 1

query="${choice%%:*}"
[[ "$query" == "custom" ]] && query=$(gum input --placeholder "e.g. cyberpunk city rain" --header "Enter search query:")
[[ -z "$query" ]] && exit 1

# --- Fetch from Wallhaven ---
echo "Fetching \"$query\" wallpapers..."
encoded_query=$(urlencode "$query")
api_url="https://wallhaven.cc/api/v1/search?q=${encoded_query}&sorting=random&categories=100&purity=100&ratios=16x9"
[[ -n "$API_KEY" ]] && api_url="${api_url}&apikey=${API_KEY}"

response=$(fetch_json "$api_url")

# --- Detect API errors ---
if echo "$response" | jq -e '.error' >/dev/null 2>&1; then
    echo "[ERROR] Wallhaven API: $(echo "$response" | jq -r '.error')"
    exit 1
fi

if ! echo "$response" | jq -e '.data' >/dev/null 2>&1; then
    echo "[ERROR] Invalid API response. The query may have no results."
    exit 1
fi

# --- Download ---
downloaded=0
while read -r url; do
    [[ -z "$url" ]] && continue
    [[ $downloaded -ge "$COUNT" ]] && break

    filename=$(basename "$url")
    [[ -f "$WALL_DIR/$filename" ]] && continue

    echo -n "Downloading $filename ... "
    code=$(download_file "$url" "$WALL_DIR/$filename")
    if [[ "$code" == "200" ]]; then
        echo "OK"
        downloaded=$((downloaded + 1))
    elif [[ "$code" == "429" ]]; then
        echo "rate limited, waiting..."
        sleep 10
        code=$(download_file "$url" "$WALL_DIR/$filename")
        if [[ "$code" == "200" ]]; then
            echo "Retry OK"
            downloaded=$((downloaded + 1))
        else
            echo "Retry failed (HTTP $code), skipping"
        fi
    else
        echo "failed (HTTP $code), skipping"
    fi
done < <(echo "$response" | jq -r '.data[].path' 2>/dev/null | head -n "$((COUNT * 3))")

echo ""
if [[ $downloaded -gt 0 ]]; then
    echo "Downloaded $downloaded wallpaper(s) to $WALL_DIR"
else
    echo "No new wallpapers downloaded."
    echo "  - All matching images may already exist in $WALL_DIR"
    echo "  - Try a different category"
fi
