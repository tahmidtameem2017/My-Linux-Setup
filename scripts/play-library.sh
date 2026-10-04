#!/usr/bin/env bash
# play-library.sh <file|RANDOM> — queue the whole music dir in mpv so the
# popup's Next/Prev walk the library, starting playback at the given track
# (or a shuffled order for RANDOM). File order matches the popup's Library
# list (find | sort) so the clicked row and the queue position agree.
set -u

music_dir="${XDG_MUSIC_DIR:-$HOME/Music}"
script_dir=$(cd -- "$(dirname -- "$0")" && pwd)
list=$(mktemp)
# music-lib.sh: same glob + sort as the popup's Library list, so the clicked
# row and the playlist index are the same position.
sh "$script_dir/music-lib.sh" list >"$list"
if [ ! -s "$list" ]; then
	rm -f "$list"
	exit 1
fi

# Kill earlier library instances first: each run is a new mpv process, and
# with loop-playlist a forgotten one would keep playing under the new one.
# Matches only OUR headless launches (the --audio-display=no signature), so
# an mpv the user opened by hand survives.
pkill -f "mpv --force-window=no --audio-display=no" 2>/dev/null || true

if [ "${1:-}" = RANDOM ]; then
	shuf -o "$list" "$list"
	exec mpv --force-window=no --audio-display=no --loop-playlist=inf --playlist="$list"
fi

start=0
i=0
while IFS= read -r line; do
	if [ "$line" = "${1:-}" ]; then
		start=$i
		break
	fi
	i=$((i + 1))
done <"$list"

exec mpv --force-window=no --audio-display=no --loop-playlist=inf --playlist="$list" --playlist-start="$start"
