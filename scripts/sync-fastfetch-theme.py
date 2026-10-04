#!/usr/bin/env python3
import json
import os
import re
import sys
import tempfile
from pathlib import Path

KEYS = ("bg", "panel", "row", "border", "borderStrong", "accent", "accentHover", "text", "muted", "dim", "danger")
PLACEHOLDERS = {
    "ACCENT": "accent",
    "ACCENT_HOVER": "accentHover",
    "MUTED": "muted",
    "TEXT": "text",
}
DEFAULT_PALETTE = {
    "bg": "#000000",
    "panel": "#0A0A0A",
    "row": "#141010",
    "border": "#1A1210",
    "borderStrong": "#3D2B24",
    "accent": "#E85D2F",
    "accentHover": "#FF8B4A",
    "text": "#F7C7A1",
    "muted": "#7C8A6A",
    "dim": "#555555",
    "danger": "#C30505",
}


def render(template, palette):
    if any(not isinstance(palette.get(key), str) or not re.fullmatch(r"#[0-9a-fA-F]{6}", palette[key]) for key in KEYS):
        raise ValueError("palette must contain all 11 six-digit hex colors")
    output = template
    for placeholder, key in PLACEHOLDERS.items():
        output = output.replace("{{" + placeholder + "}}", palette[key].upper())
    if re.search(r"\{\{[A-Z_]+\}\}", output):
        raise ValueError("unresolved template placeholder")
    json.loads(output)
    return output


def main(argv):
    if len(argv) == 3:
        template_path = Path(argv[1])
        palette = DEFAULT_PALETTE
        output_path = Path(argv[2])
    elif len(argv) == 4:
        template_path = Path(argv[1])
        palette = json.loads(argv[2])
        output_path = Path(argv[3])
    else:
        raise SystemExit("usage: sync-fastfetch-theme.py <template> [palette-json] <output>")
    rendered = render(template_path.read_text(), palette)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=".fastfetch-theme-", dir=output_path.parent, text=True)
    try:
        with os.fdopen(fd, "w") as output:
            output.write(rendered)
            output.flush()
            os.fsync(output.fileno())
        os.replace(temporary, output_path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


if __name__ == "__main__":
    try:
        main(sys.argv)
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"Fastfetch theme sync failed: {error}", file=sys.stderr)
        raise SystemExit(1)
