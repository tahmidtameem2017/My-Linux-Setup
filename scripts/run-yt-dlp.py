#!/usr/bin/env python3
"""exec yt-dlp so that it can never outlive the script that started it.

download-track.sh backgrounds yt-dlp so it can forward the popup's SIGTERM to
it, and that works — right up until quickshell restarts. Tearing a QProcess
child down does NOT give bash a chance to run its TERM trap, so the trap never
fires and yt-dlp is reparented to init and keeps running: measured one sitting
there for 2h07m with ~/Music still open, long after the card showed the run as
finished. Nothing in the trap can prevent that, because the script is already
dead by the time it would have run.

So the guarantee is moved into the child, where the kernel enforces it:

  * os.setsid()             yt-dlp becomes its own session/process-group
                            leader, so the script can signal the WHOLE group
                            (ffmpeg post-processors too) with one kill.
  * PR_SET_PDEATHSIG=SIGKILL  the kernel SIGKILLs yt-dlp the moment its parent
                            — this script, by any cause, including SIGKILL —
                            goes away. No trap, no polling, no race.

Usage:  run-yt-dlp.py [yt-dlp args...]      (argv/stdin/stdout are inherited)
"""

import ctypes
import os
import signal
import sys

PR_SET_PDEATHSIG = 1

# setsid() fails with EPERM only when we are already a group leader, which
# cannot happen the way download-track.sh spawns us (a background child of a
# non-job-control bash shares its parent's group). Tolerate it anyway: the
# PDEATHSIG guarantee is the load-bearing half, the group kill is a bonus.
try:
    os.setsid()
except OSError:
    pass

try:
    ctypes.CDLL("libc.so.6", use_errno=True).prctl(PR_SET_PDEATHSIG, signal.SIGKILL, 0, 0, 0)
except OSError:
    # No prctl (not Linux): degrade to the trap-only behaviour rather than
    # refusing to download.
    pass

# argv[0] has to be put back. execvp() takes the WHOLE vector, and the obvious
# `sys.argv[1:]` silently eats the URL: argv[0] becomes "ytsearch1:…", and
# yt-dlp's wrapper hands `sys.argv[1:]` to its option parser — so the only URL
# in the command ends up where the program name belongs and every run fails
# with "You must provide at least one URL", no matter what was downloaded.
os.execvp("yt-dlp", ["yt-dlp"] + sys.argv[1:])