#!/usr/bin/env bash
# Capture preview.png for the marketplace listing — fully self-driving.
#
# The popup normally closes the moment you click a terminal to run a command,
# which makes it impossible to screenshot by hand. This script drives the
# popup over IPC instead: it opens it, lets you drag-select the region, then
# RE-opens it (in case the selection click closed it) and captures.
set -euo pipefail

ID="com.leafbox.f1"
OUT="$(cd "$(dirname "$0")/.." && pwd)/preview.png"

omarchy-shell shell summon "$ID"
sleep 0.6

echo "Drag-select the popup region…"
region=$(slurp)

# Selecting may have closed the popup — reopen and give it a beat to render.
omarchy-shell shell summon "$ID"
sleep 0.8

grim -g "$region" "$OUT"
omarchy-shell shell hide "$ID"
echo "Saved $OUT"
