#!/usr/bin/env python3
"""Shortens long "Finding…" waits in a recorded take.

    scripts/demo/trim-waits.py .build/demo/takes/zh-20260913-171233 [--max-wait 4] [--keep 2.5]

Reads <take>.mp4 and <take>.log (written by scripts/record-demo.sh). For every
hotkey press whose answer took longer than --max-wait seconds, the middle of the
wait is cut out so that about --keep seconds of spinner remain. Writes
<take>-trimmed.mp4 and prints what was cut. The original files are untouched.

The driver log counts seconds from the driver's start; the video starts a little
earlier. The offset is found by locating the first frame in which the title area
changes, which is the first typed character, and matching it to the first `type`
line in the log.
"""
import argparse
import pathlib
import re
import subprocess
import sys


def run(args):
    return subprocess.run(args, capture_output=True, text=True)


def first_change_in_video(mp4):
    """Seconds into the video at which the title line first changes."""
    probe = run(["ffprobe", "-v", "error", "-select_streams", "v:0",
                 "-show_entries", "stream=width,height", "-of", "csv=p=0", mp4])
    width, height = (int(v) for v in probe.stdout.strip().split(","))
    crop = f"crop={int(width * 0.6)}:{int(height * 0.16)}:0:{int(height * 0.11)}"
    out = run(["ffmpeg", "-hide_banner", "-i", mp4, "-vf",
               f"{crop},select='gt(scene,0.001)',showinfo", "-fps_mode", "vfr", "-f", "null", "-"])
    match = re.search(r"pts_time:([0-9.]+)", out.stderr)
    if not match:
        sys.exit("could not find the first keystroke in the video")
    return float(match.group(1))


def parse_log(log):
    """Returns (first_type_time, [(press_time, answer_time), ...])."""
    first_type = None
    presses = []
    pending = None
    for line in pathlib.Path(log).read_text().splitlines():
        m = re.match(r"\[\s*([0-9.]+)s\] (.*)", line)
        if not m:
            continue
        t, rest = float(m.group(1)), m.group(2)
        if first_type is None and rest.startswith("type "):
            first_type = t
        if rest.startswith("hotkey "):
            pending = t
        elif rest.startswith("HUD answered") and pending is not None:
            presses.append((pending, t))
            pending = None
    if first_type is None:
        sys.exit("no type line in the log")
    return first_type, presses


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("take", help="path without extension, e.g. .build/demo/takes/zh-20260913-171233")
    parser.add_argument("--max-wait", type=float, default=4.0, help="waits longer than this are shortened")
    parser.add_argument("--keep", type=float, default=2.5, help="seconds of spinner to keep")
    args = parser.parse_args()

    mp4 = args.take + ".mp4"
    log = args.take + ".log"
    out = args.take + "-trimmed.mp4"

    first_type, presses = parse_log(log)
    first_change = first_change_in_video(mp4)
    offset = first_change - first_type
    print(f"first keystroke: log {first_type:.2f}s, video {first_change:.2f}s, offset {offset:+.2f}s")

    cuts = []
    for press, answer in presses:
        wait = answer - press
        if wait <= args.max_wait:
            continue
        head = args.keep * 0.7
        tail = args.keep * 0.3
        start = press + head + offset
        end = answer - tail + offset
        if end > start:
            cuts.append((start, end))
            print(f"cut {start:.2f}s–{end:.2f}s  (wait was {wait:.1f}s)")
    if not cuts:
        print("nothing longer than the limit; no output written")
        return

    keep = "*".join(f"not(between(t,{a:.3f},{b:.3f}))" for a, b in cuts)
    result = run(["ffmpeg", "-y", "-loglevel", "error", "-i", mp4,
                  "-vf", f"select='{keep}',setpts=N/FRAME_RATE/TB",
                  "-c:v", "libx264", "-crf", "20", "-preset", "slow", "-movflags", "+faststart", "-an", out])
    if result.returncode != 0:
        sys.exit(result.stderr)
    removed = sum(b - a for a, b in cuts)
    print(f"removed {removed:.1f}s -> {out}")


if __name__ == "__main__":
    main()
