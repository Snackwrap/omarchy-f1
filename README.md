# Formula 1 — Omarchy bar plugin

A checkered-flag pill for the [Omarchy](https://omarchy.org) (Quattro) bar that
counts down to the next Formula 1 race. Click it for a popup with three tabs:

- **Schedule** — the circuit outline drawn as a theme-colored line-art hero,
  the countdown, and the full weekend session schedule (practice, sprint,
  qualifying, race) in your **local time**.
- **Drivers** — current driver championship standings.
- **Constructors** — current constructor championship standings.

Data comes from the free [Jolpica-F1 API](https://github.com/jolpica/jolpica-f1)
(an Ergast-compatible mirror). No API key required. Circuit outlines are bundled
from [`bacinger/f1-circuits`](https://github.com/bacinger/f1-circuits) (MIT),
preprocessed into `tracks.json` by `tools/build-tracks.py` and drawn as vector
paths via QtQuick.Shapes — so they recolor to match your Omarchy theme.

## Requirements

- Omarchy **Quattro (v4)** with `omarchy-shell` (Quickshell-based bar)
- `curl` on `PATH`
- A Nerd Font in the bar (Omarchy ships one) for the checkered-flag glyph

## Install

```bash
omarchy plugin add https://github.com/<you>/omarchy-f1.git --enable
omarchy bar move com.leafbox.f1 right
```

## Local development

```bash
git clone https://github.com/<you>/omarchy-f1.git
cd omarchy-f1
./deploy-local.sh                     # symlink into ~/.config/omarchy/plugins + validate
omarchy plugin enable com.leafbox.f1 right
omarchy-shell shell rescanPlugins     # reload after each edit
```

## Interaction

| Action | Result |
|---|---|
| Left click | Toggle the schedule popup |
| Middle click | Force a data refresh |

## How it works

- `BarWidget.qml` — the bar-slot button + popout-identity shim.
- `Panel.qml` — fetches `current/next.json` via `curl` (Quickshell `Process`),
  parses it, exposes `label`/`tooltip` to the pill, and renders the popup. A
  1-second timer advances the countdown; the schedule refetches every 6 hours.

## License

MIT
