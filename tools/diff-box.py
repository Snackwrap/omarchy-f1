#!/usr/bin/env python3
"""Print the ImageMagick crop geometry of the region where two screenshots differ.

The popup lives inside a fullscreen layer surface, so the compositor cannot tell
us where it is. Shooting the screen with it open and closed and diffing the two
locates it exactly. The bar strip along the top is ignored: the widget's own
pill changes when the popup opens, and the clock can tick between the shots.
"""
import subprocess, sys
import numpy as np

BAR_STRIP = 50      # device pixels of bar to ignore along the top
THRESHOLD = 60      # 0-255 per-pixel difference that counts as a change
DENSITY   = 0.35    # share of a column's peak change density to count as popup
MIN_SIDE  = 120     # anything smaller than this is noise, not a popup
MAX_SHARE = 0.55    # a popup never covers this much of the screen; the desktop does


def gray(path):
    out = subprocess.run(
        ["magick", path, "-colorspace", "Gray", "-depth", "8", "pgm:-"],
        check=True, capture_output=True).stdout
    # Parse the binary PGM header: P5 <w> <h> <maxval>, whitespace separated.
    fields, pos = [], 2
    while len(fields) < 3:
        while out[pos:pos + 1].isspace():
            pos += 1
        if out[pos:pos + 1] == b"#":
            while out[pos:pos + 1] != b"\n":
                pos += 1
            continue
        start = pos
        while not out[pos:pos + 1].isspace():
            pos += 1
        fields.append(int(out[start:pos]))
    w, h, _ = fields
    return np.frombuffer(out[pos + 1:], dtype=np.uint8).reshape(h, w).astype(np.int16)


def extent(profile, floor):
    """Full reach of the rows that changed at all, from the first to the last.

    Used down the vertical axis only, where density genuinely varies: a
    masthead row is sparse and a standings row is dense, so the longest-run
    rule below would clip the popup's header off the top.
    """
    hits = np.where(profile > floor)[0]
    return (hits[0], hits[-1]) if len(hits) else None


def longest_run(profile):
    """The longest run where the change is *dense*, not merely present.

    Taking the first and last dense index would stretch the box across any
    unrelated redraw elsewhere on screen. The popup is one solid block, so the
    longest contiguous run of dense lines is the popup and stray activity forms
    its own shorter runs.
    """
    dense = profile > profile.max() * DENSITY
    best = run = None
    for i, on in enumerate(dense):
        if on:
            run = (run[0], i) if run else (i, i)
            if best is None or (run[1] - run[0]) > (best[1] - best[0]):
                best = run
        else:
            run = None
    return best


a, b = gray(sys.argv[1]), gray(sys.argv[2])
if a.shape != b.shape:
    sys.exit("screenshots differ in size")

changed = np.abs(a - b) > THRESHOLD
changed[:BAR_STRIP, :] = False
if not changed.any():
    sys.exit(1)

# Opening the popup also dims the whole desktop behind it, so "any pixel that
# changed" is the entire screen. The popup is the region where a large share of
# the pixels in a column changed, which the density profile isolates cleanly.
cols = longest_run(changed.mean(axis=0))
if cols is None:
    sys.exit(1)
rows = extent(changed[:, cols[0]:cols[1] + 1].mean(axis=1), 0.02)
if rows is None:
    sys.exit(1)

w, h = cols[1] - cols[0] + 1, rows[1] - rows[0] + 1
if w < MIN_SIDE or h < MIN_SIDE:
    sys.exit(1)
# A box spanning most of the screen means something behind the popup redrew
# between the two shots and the caller should take them again.
if w > a.shape[1] * MAX_SHARE and h > a.shape[0] * MAX_SHARE:
    sys.exit(1)

print(f"{w}x{h}+{cols[0]}+{rows[0]}")
