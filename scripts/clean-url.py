#!/usr/bin/env python3
"""Turn whatever the user pasted into one canonical, download-ready URL.

Used by scripts/download-track.sh when the Now Playing popup is handed an
explicit link instead of (or as well as) the "<artist> <title>" search. A
pasted YouTube link is almost never the clean `watch?v=ID` form yt-dlp is
happiest with — it carries a start offset, a playlist, a share id, and often
surrounding prose:

    "watch this https://youtu.be/dQw4w9WgXcQ?t=43&si=AbC-123 amazing"

so the job here is threefold, in order:

  1. EXTRACT the first http(s) URL out of whatever text was given.
  2. CANONICALISE YouTube: every shape (watch / youtu.be / shorts / embed /
     live / v / nocookie / m. / music. / attribution_link) collapses to
     `https://www.youtube.com/watch?v=<id>`, with the id shape-checked.
  3. STRIP tracking from anything else (`si`, `utm_*`, `fbclid`, ...) while
     keeping params that change the media (`v`, `list` is dropped for
     YouTube only, ...).

Pure and dependency-free, so both the shell script and any test can call it:

    clean-url.py '<paste>'   -> prints one canonical URL, exit 0
                              -> prints why on stderr, exit 1 if unusable
"""

import re
import sys
from urllib.parse import parse_qs, parse_qsl, urlencode, urlsplit, urlunsplit

# A YouTube video id is exactly 11 chars of URL-safe base64. Shape-checking it
# is what keeps `watch?v=playlist` or a truncated paste from being handed to
# yt-dlp as if it were a video (it would "succeed" and fetch something else).
YT_ID = re.compile(r"^[A-Za-z0-9_-]{11}$")

# Hosts that are YouTube wearing a different hat.
YT_HOSTS = {
    "youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com",
    "gaming.youtube.com", "youtube-nocookie.com", "www.youtube-nocookie.com",
    "youtu.be", "www.youtu.be",
}

# Path prefixes that carry the id as the segment right after them.
YT_PATH_ID = ("shorts", "embed", "live", "v", "e")

# Query params that never change which media you get. `t`/`start`/`time_continue`
# are deliberately NOT here for non-YouTube hosts: a `?t=` on a VOD host is a
# legitimate seek hint, and yt-dlp honours it.
TRACKING = {
    "si", "feature", "feature_share", "fbclid", "gclid", "igshid", "pp",
    "ref", "ref_src", "ref_url", "source", "ved", "usqp", "spm_id_from",
}

# First http(s) run in a blob of text. Trailing junk that is not part of a URL
# is trimmed later by dropping the fragment / re-encoding the query.
URL_IN_TEXT = re.compile(r"https?://[^\s<>\"'\\]+", re.I)


class Bad(Exception):
    """Raised with a human-readable reason; the CLI turns it into exit 1."""


def extract(text: str) -> str:
    """First http(s) URL in `text`, or the text itself if it is bare."""
    found = URL_IN_TEXT.search(text)
    if not found:
        return text.strip()
    # The run stops at whitespace, not at the end of the URL: a paste wrapped
    # in brackets or ended with a comma hands over `...dQw4w9WgXcQ)` and the id
    # shape check would reject the lot.
    return found.group(0).rstrip(")]}>.,;:!?\"'")


def canonical_youtube(parts) -> str:
    """Collapse any YouTube shape to `https://www.youtube.com/watch?v=<id>`."""
    params = parse_qs(parts.query)
    segs = [s for s in parts.path.split("/") if s]

    vid = ""
    if parts.netloc.lower() in ("youtu.be", "www.youtu.be") and segs:
        vid = segs[0]
    elif len(segs) >= 2 and segs[0] in YT_PATH_ID:
        vid = segs[1]
    elif len(segs) >= 1 and segs[0] == "watch":
        vid = (params.get("v") or [""])[0]
    elif segs and segs[0] == "attribution_link":
        # ?u=%2Fwatch%3Fv%3DID%26... — a one-click wrapper around the real link.
        inner = (params.get("u") or [""])[0]
        vid = parse_qs(urlsplit(inner).query).get("v", [""])[0]
    if not vid:
        # Last resort: the only 11-char token on the URL.
        for seg in segs:
            if YT_ID.match(seg):
                vid = seg
                break

    if not YT_ID.match(vid):
        raise Bad(f"no YouTube video id in {parts.geturl()}")

    return f"https://www.youtube.com/watch?v={vid}"


def clean(text: str) -> str:
    """Return one canonical http(s) URL, or raise `Bad` with the reason."""
    raw = extract(text or "")
    if not raw:
        raise Bad("empty")

    # A bare host/path with no scheme is the commonest paste mistake.
    if not re.match(r"^[a-z][a-z0-9+.-]*://", raw, re.I):
        if re.match(r"^[a-z][a-z0-9+.-]*:", raw, re.I):
            raise Bad(f"unsupported scheme in {raw}")
        raw = "https://" + raw.lstrip("/")

    parts = urlsplit(raw)
    scheme = parts.scheme.lower()
    if scheme not in ("http", "https"):
        raise Bad(f"unsupported scheme '{parts.scheme}'")

    host = parts.netloc.split("@")[-1].split(":")[0].lower()
    if not host or "." not in host:
        raise Bad(f"no host in {raw}")

    if host in YT_HOSTS:
        return canonical_youtube(parts)

    # Everything else: keep the query's meaning, lose the fingerprint.
    # keep_blank_values so `?t=` is not silently reinvented as `t=`-less.
    params = [(k, v) for k, v in parse_qsl(parts.query, keep_blank_values=True)
              if k not in TRACKING and not k.lower().startswith("utm_")]
    query = urlencode(params) if params else ""
    path = parts.path or "/"
    return urlunsplit((scheme, host, path, query, ""))


def main(argv: list) -> int:
    if len(argv) != 2:
        print("usage: clean-url.py <url-or-pasted-text>", file=sys.stderr)
        return 2
    try:
        print(clean(argv[1]))
    except Bad as e:
        print(f"unusable link: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))