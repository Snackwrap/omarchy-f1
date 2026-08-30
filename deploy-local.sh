#!/usr/bin/env bash
# Symlink this repo into the Omarchy plugins dir for live development, then
# validate it. Editing files here updates the running shell after a rescan.
set -euo pipefail

ID="com.leafbox.f1"
SRC="$(cd "$(dirname "$0")" && pwd)"
DEST="$HOME/.config/omarchy/plugins/$ID"

if [[ -e "$DEST" && ! -L "$DEST" ]]; then
  echo "Refusing to overwrite $DEST (exists and is not a symlink)." >&2
  exit 1
fi

ln -sfn "$SRC" "$DEST"
echo "Linked $DEST -> $SRC"

omarchy plugin validate "$SRC" || true

cat <<EOF

Next steps:
  omarchy plugin enable $ID right     # add to the right bar section
  omarchy-shell shell rescanPlugins   # hot-reload after edits

Remove with:
  omarchy plugin disable $ID
  rm "$DEST"
EOF
