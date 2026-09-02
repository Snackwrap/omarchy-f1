#!/usr/bin/env bash
# Capture the popup, one PNG per tab, for the marketplace listing assets.
#
# Two things make this awkward to do by hand, and this script works around both:
#
#   * Clicking a terminal closes the popup, so it has to be driven over IPC
#     (`omarchy-shell shell summon`) rather than opened with the mouse.
#   * The popup is drawn inside a fullscreen layer surface, so the compositor
#     cannot tell us its rectangle. We shoot the screen with the popup open and
#     again with it closed, and diff the two — the region that changed *is* the
#     popup, which crops it exactly with no drag-select.
#
# Tab selection uses the debug path: with `debugForceTabs` on, every conditional
# tab is present and `defaultTab` may name any of them, pinned against the
# usual auto-switching. That is the only way to shoot Grid and Live outside of
# a real race weekend.
#
# Usage:  tools/capture-preview.sh [tab ...]      (default: all of them)
set -euo pipefail

ID="com.leafbox.f1"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTDIR="$ROOT/assets/tabs"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

TABS=("$@")
[ ${#TABS[@]} -eq 0 ] && TABS=(schedule grid live results drivers constructors)

mkdir -p "$OUTDIR"

# Park the pointer in a corner once, up front. Whichever row it rests on picks
# up its hover fill and reads like a selection in the screenshot. It has to be
# done once rather than per tab: moving it switches focus under
# focus-follows-mouse, and that window's redraw is exactly the kind of change
# the diff below would mistake for the popup.
hyprctl dispatch 'hl.dsp.cursor.move({x=4,y=796})' >/dev/null 2>&1 \
  || hyprctl dispatch movecursor 4 796 >/dev/null 2>&1 || true
sleep 1.5

# There is no `omarchy bar get`, so read the current values straight out of the
# merged shell config in order to hand them back at the end.
read_setting() {
  python3 - "$1" <<'PYEOF'
import json, os, sys
try:
    cfg = json.load(open(os.path.expanduser("~/.config/omarchy/shell.json")))
except Exception:
    sys.exit()
for slot in cfg.get("bar", {}).get("layout", {}).values():
    for w in slot:
        if w.get("id") == "com.leafbox.f1" and sys.argv[1] in w:
            print(w[sys.argv[1]])
PYEOF
}

restore_debug=$(read_setting debugForceTabs)
restore_tab=$(read_setting defaultTab)
restore_anim=$(read_setting raceAnimations)

omarchy bar set "$ID" debugForceTabs true
# debugForceTabs also forces raceDay on, which would put the lit starting gantry
# beside a countdown reading days-away — a pairing the plugin never really shows.
# The circuit intro is a one-shot whose end state is the plan view anyway, so
# turning both flourishes off costs the captures nothing and keeps them honest.
omarchy bar set "$ID" raceAnimations false

for tab in "${TABS[@]}"; do
  omarchy bar set "$ID" defaultTab "$tab"
  omarchy restart shell
  sleep 4.0                      # the shell needs a beat to come back up

  # Closed and open shots go back to back with nothing printed between them, so
  # the popup is the only thing that differs and the diff crops it exactly. If
  # something else on screen redraws anyway the box comes back implausibly wide,
  # so take the shot again rather than shipping a screenshot of the desktop.
  box=""
  for attempt in 1 2 3; do
    omarchy-shell shell hide "$ID" 2>/dev/null || true
    sleep 0.7
    grim "$TMP/closed.png"
    omarchy-shell shell summon "$ID"
    sleep 4.0                    # let the fetch land and the panel settle
    grim "$TMP/open.png"
    omarchy-shell shell hide "$ID" 2>/dev/null || true

    box=$(python3 "$ROOT/tools/diff-box.py" "$TMP/open.png" "$TMP/closed.png") || box=""
    [ -n "$box" ] && break
    echo "   $tab: attempt $attempt caught the desktop, retrying" >&2
  done
  if [ -z "$box" ]; then
    echo "!! $tab: could not isolate the popup, skipping" >&2
    continue
  fi
  magick "$TMP/open.png" -crop "$box" +repage "$OUTDIR/$tab.png"
  echo "   $tab -> assets/tabs/$tab.png ($box)"
done

# Put the user's own settings back.
omarchy bar set "$ID" debugForceTabs "${restore_debug:-false}"
omarchy bar set "$ID" defaultTab "${restore_tab:-schedule}"
omarchy bar set "$ID" raceAnimations "${restore_anim:-true}"
omarchy restart shell
echo "Done. Now run tools/build-preview.sh to compose preview.png."
