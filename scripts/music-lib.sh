#!/usr/bin/env bash
# music-lib.sh — the ONE definition of "the music library".
#
# Both the popup's Library list (NowPlayingPopup.qml) and the post-download
# duplicate check (music-dedup.sh) go through here, on purpose: the list is
# ordered by this file, and the dedup check resolves "where did I start this
# track" against the same order. A second copy of this glob would let the
# playlist offset and the popup's highlighted row disagree.
set -u

music_dir="${XDG_MUSIC_DIR:-$HOME/Music}"

# newline-separated absolute paths, sorted by name
list_music() {
	find "$music_dir" -maxdepth 1 -type f \( -iname '*.mp3' -o -iname '*.flac' -o -iname '*.ogg' -o -iname '*.opus' -o -iname '*.m4a' -o -iname '*.wav' \) | sort
}

count_music() {
	list_music | wc -l
}

case "${1:-}" in
list) list_music ;;
count) count_music ;;
*)
	printf 'usage: music-lib.sh list|count\n' >&2
	exit 2
	;;
esac