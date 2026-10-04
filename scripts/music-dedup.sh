#!/usr/bin/env bash
# music-dedup.sh <file> — is this file already in the music dir?
# Prints the path of the existing copy and exits 0 when it IS a duplicate;
# exits 1 when the file is unique. Prints nothing on unique.
#
# Why a cache: comparing against a few thousand tracks means a signature per
# track, and spawning head/md5sum per file on every download is wasteful. The
# index (content signature + normalised name + path per file) lives in
# $XDG_CACHE_HOME and is rebuilt only when the file COUNT moves — so a track
# dropped into ~/Music by Thunar is picked up on the next run, with no
# mtime chasing (mtimes change for unrelated reasons, e.g. a tag rewrite).
#
# Match order, cheapest first:
#   1. same name, case-insensitive         (yt-dlp's own skip, re-checked)
#   2. same normalised name (name with every
#      non-alphanumeric dropped)           ("Song (Official Video)" == "Song")
#   3. same content signature              (different name, same audio —
#      the case that actually happens: a lyric video vs an official one)
#   4. same size AND same title+artist tags (a re-upload under yet another
#      name; ffprobe runs only on same-size candidates, never per file)
set -u

script_dir=$(cd -- "$(dirname -- "$0")" && pwd)
cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/niri-setup"
index="$cache_dir/music-index.tsv"

[ -n "${1:-}" ] || exit 2
new_file=$1
[ -f "$new_file" ] || exit 2

mkdir -p "$cache_dir"

# name with the extension off, lowercased, alphanumerics only
norm_name() {
	printf '%s' "${1##*/}" | tr '[:upper:]' '[:lower:]' | sed 's/\.[^.]*$//; s/[^[:alnum:]]//g'
}

# size + md5 of the first and last 256KiB: cheap (no full decode) but exact
# for "same file, different name".
signature() {
	_size=$(stat -c %s "$1")
	_head=$(head -c 262144 "$1" | md5sum | cut -d' ' -f1)
	_tail=$(tail -c 262144 "$1" | md5sum | cut -d' ' -f1)
	printf '%s:%s:%s' "$_size" "$_head" "$_tail"
}

tags() {
	ffprobe -v quiet -show_entries format_tags=title,artist -of default=nw=1:nk=1 "$1" 2>/dev/null | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]' | paste -sd'' -
}

index_entry() {
	printf '%s\t%s\t%s\n' "$(signature "$1")" "$(norm_name "$1")" "$1"
}

build_index() {
	tmp=$(mktemp)
	sh "$script_dir/music-lib.sh" list | while IFS= read -r f; do
		index_entry "$f"
	done >"$tmp"
	mv -f "$tmp" "$index"
}

if [ ! -s "$index" ] || [ "$(wc -l <"$index")" -ne "$(sh "$script_dir/music-lib.sh" count)" ]; then
	build_index
fi

new_norm=$(norm_name "$new_file")
new_sig=$(signature "$new_file")
new_tags=$(tags "$new_file")

dup=""
while IFS=$'\t' read -r sig norm path; do
	[ -n "$path" ] || continue
	[ "$path" = "$new_file" ] && continue
	if [ "$norm" = "$new_norm" ] || [ "$sig" = "$new_sig" ]; then
		dup=$path
		break
	fi
	# Same size + same tags: a re-upload of the same track under another
	# name. ffprobe runs only for same-size candidates.
	if [ "${sig%%:*}" = "${new_sig%%:*}" ] && [ -n "$new_tags" ] && [ "$(tags "$path")" = "$new_tags" ]; then
		dup=$path
		break
	fi
done <"$index"

if [ -n "$dup" ]; then
	printf '%s\n' "$dup"
	exit 0
fi

# Unique: remember it, but never twice — the signature is the dedup key, so a
# blind append would make the index list the same file again after every
# download.
if ! cut -f1 "$index" | grep -qxF -- "$new_sig"; then
	index_entry "$new_file" >>"$index"
fi
exit 1