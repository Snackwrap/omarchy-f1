#!/usr/bin/env bash
# Capture preview.png for the marketplace listing.
# 1. Click the F1 pill so the popup is open (Schedule tab shows the track).
# 2. Run this script and drag-select the popup region.
set -euo pipefail

OUT="$(cd "$(dirname "$0")/.." && pwd)/preview.png"
echo "Drag-select the F1 popup region…"
grim -g "$(slurp)" "$OUT"
echo "Saved $OUT"
