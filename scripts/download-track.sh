#!/usr/bin/env bash
# download-track.sh <audio|video> <quality> [title] [artist] [url] — fetch the
# now-playing track. With no url it searches YouTube for the first hit on
# "<artist> <title>"; with one it downloads that link instead (see
# scripts/clean-url.py, which canonicalises whatever was pasted).
#   audio: quality is 0 (VBR best) or a bitrate like 320K/128K -> MP3 in the
#          music dir, thumbnail embedded as album art.
#   video: quality is best or a height cap (1080/720/480) -> MP4 in the
#          videos dir, thumbnail embedded.
# Title/artist tags come from the MPRIS metadata, not the video's own — but
# only when we actually know the track is the one being downloaded. A pasted
# url means the user asked for THAT video, so the caller passes no title and
# the video keeps its own tags (overriding them with whatever happens to be
# playing would file it under the wrong song).
#
# With NEITHER a url NOR a title, "what is playing" is read off the MPRIS bus
# here rather than in the popup. The popup's link box being empty means
# "download the current track", and that rule used to live only in QML — so it
# held for a click and not for `qs ipc call now-playing downloadUrl audio 0`,
# and nothing outside quickshell could ask for it at all.
set -u

mode=${1:-}
quality=${2:-}
title=${3:-}
artist=${4:-}
raw_url=${5:-}

script_dir=$(cd -- "$(dirname -- "$0")" && pwd)
case "$mode" in audio | video) ;;
*) exit 2 ;;
esac

# Say WHY on stdout, machine-readably: the popup shows this line while a run is
# in flight and keeps it up for the error flash, which is the difference
# between "✕" and a fixable message. yt-dlp's own reasons ("Sign in to confirm
# you're not a bot", "Video unavailable", "No space left") are the whole
# content of a failure — the exit code is always 1.
fail() {
	printf 'STATUS failed %s\n' "$1"
	notify-send -u critical "Download failed" "$1" 2>/dev/null || true
	exit 1
}

# An explicit link wins over the search. A link that cannot be canonicalised is
# a HARD failure: silently falling back to the search would answer a different
# request than the one the user made, and they would only find out when the
# wrong track landed in ~/Music.
#
# "undefined"/"null" mean NO link, not a link: quickshell's IpcHandler coerces a
# missing argument to the declared parameter type, so an omitted url arrived
# here as that literal text and the download died on "unusable link:
# undefined" — the empty link box, which means "download what is playing",
# silently refusing to download. The popup drops it too; both layers agree so
# neither caller can be the reason a download fails.
case "$raw_url" in
undefined | null | NULL | Null) raw_url="" ;;
esac

target=""
if [ -n "$raw_url" ]; then
	if ! target=$(python3 "$script_dir/clean-url.py" "$raw_url" 2>/dev/null); then
		fail "unusable link: $raw_url"
	fi
fi

if [ -z "$target" ]; then
	# No link: fall back to the bus, so "empty field" is a real contract and
	# not a QML-only convention.
	if [ -z "$title" ] && command -v playerctl >/dev/null 2>&1; then
		title=$(playerctl metadata xesam:title 2>/dev/null | head -n 1)
		artist=$(playerctl metadata --format '{{artist}}' 2>/dev/null)
	fi
	[ -n "$title" ] || fail "nothing is playing"
	if [ -n "$artist" ]; then
		query="$artist $title"
	else
		query="$title"
	fi
	target="ytsearch1:$query"
fi

# yt-dlp shlex-splits --postprocessor-args, so each value needs single
# quotes (with the '\'' escape for literal apostrophes) or ffmpeg gets the
# words as separate arguments and fails with "Invalid argument".
sq() { printf "%s" "$1" | sed "s/'/'\\\\''/g"; }

pp_flag=()
if [ -n "$title" ]; then
	pp_args="-metadata title='$(sq "$title")'"
	if [ -n "$artist" ]; then
		pp_args="$pp_args -metadata artist='$(sq "$artist")'"
	fi
	# Only pass the flag when there is something to say: an empty namespace
	# ("ffmpeg:") is not worth handing ffmpeg just to keep the array tidy.
	pp_flag=(--postprocessor-args "ffmpeg:$pp_args")
fi

if [ "$mode" = audio ]; then
	out_dir="${XDG_MUSIC_DIR:-$HOME/Music}"
	mode_args=(-x --audio-format mp3 --audio-quality "$quality")
else
	out_dir="${XDG_VIDEOS_DIR:-$HOME/Videos}"
	if [ "$quality" = best ]; then
		fmt="bv*+ba/b"
	else
		fmt="bv*[height<=$quality]+ba/b[height<=$quality]/b"
	fi
	mode_args=(-f "$fmt" --merge-output-format mp4)
fi
mkdir -p "$out_dir"

# Progress is streamed on stdout as machine-readable lines the quickshell
# popup parses live:
#   STATUS fetching        (search resolve, before any bytes move)
#   DL <pct>%              (yt-dlp download progress-template)
#   PP <postprocessor>     (extract-audio / embed-thumbnail phase)
#   STATUS failed <why>    (the reason, so the error flash can say it)
# The final path goes to a temp file instead of stdout so it cannot get
# mixed into the progress stream.
path_tmp=$(mktemp)

# yt-dlp's own words are the only useful diagnosis of a failed download (bot
# check, unavailable video, no space…), and they arrive on stderr. Keep the
# last few ERROR lines so fail() can quote one instead of restating the URL.
err_tmp=$(mktemp)

echo "STATUS fetching"

# The popup's fetch watchdog SIGTERMs this script after a minute of silence
# (see dlFetchWatch in quickshell/sunset/components/NowPlayingPopup.qml).
# yt-dlp therefore runs BACKGROUNDED and reaped by pid, and it goes through
# scripts/run-yt-dlp.py so the kernel kills it if this script dies at all —
# see that file for why the trap alone was not enough.
dl_pid=""
# Signal the whole process group (yt-dlp runs in its own, so ffmpeg
# post-processors come with it), falling back to the bare pid if the group
# signal is refused.
kill_tree() {
	[ -n "${1:-}" ] || return 0
	kill "-$2" -- "-$1" 2>/dev/null || kill "-$2" "$1" 2>/dev/null || true
}
on_term() {
	local pgid=$dl_pid
	kill_tree "$pgid" TERM
	# A yt-dlp wedged in a network call may not act on TERM promptly, and this
	# handler is about to exit, so the escalation cannot be the trap's job.
	# (pgid is captured, not read back: dl_pid is cleared below.)
	( sleep 3; kill_tree "$pgid" KILL ) &
	echo "STATUS failed timed out"
	dl_pid=""
	rm -f "$path_tmp"
	exit 143
}
trap on_term TERM INT
trap 'rm -f "$path_tmp" "$err_tmp"' EXIT

python3 "$script_dir/run-yt-dlp.py" \
	"$target" \
	--no-playlist \
	--newline \
	--progress-template "download:DL %(progress._percent_str)s" \
	--progress-template "postprocess:PP %(postprocessor.name)s" \
	--embed-thumbnail \
	"${pp_flag[@]}" \
	"${mode_args[@]}" \
	-o "$out_dir/%(title)s.%(ext)s" \
	--print-to-file after_move:filepath "$path_tmp" 2> >(tee "$err_tmp" >&2) &
dl_pid=$!
if wait "$dl_pid"; then
	dl_pid=""
	file=$(tail -n 1 "$path_tmp")
	# Validation: never leave a second copy of the same track in the dir.
	# The dedup helper matches on name, then on content signature, then on
	# same-size + same title/artist tags; a match means we drop OUR new file
	# and keep the one that was already there.
	if dup=$(sh "$script_dir/music-dedup.sh" "$file"); then
		rm -f "$file"
		notify-send -i audio-x-generic "Already in Music" "$(basename "$dup") — duplicate download removed" 2>/dev/null || true
	else
		notify-send -i audio-x-generic "Download finished" "$file" 2>/dev/null || true
	fi
else
	dl_pid=""
	# yt-dlp's FIRST ERROR line is the diagnosis; the lines after it are
	# usually its usage hint ("Type yt-dlp --help to get a list of all
	# options."), which says nothing about this download.
	why=$(grep -m 1 -E '^(ERROR|error:)' "$err_tmp" 2>/dev/null | cut -c1-140)
	[ -n "$why" ] || why=$(tail -n 1 "$err_tmp" 2>/dev/null | cut -c1-140)
	[ -n "$why" ] || why="$target"
	fail "$why"
fi
