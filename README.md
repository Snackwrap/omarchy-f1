# Formula 1 — Omarchy bar plugin

A checkered-flag pill for the [Omarchy](https://omarchy.org) (Quattro) bar that
counts down to the next Formula 1 session. Click it for a popup with these tabs:

- **Schedule** — the circuit outline drawn as a theme-colored line-art hero,
  the countdown, and the full weekend session schedule (practice, sprint,
  qualifying, race) in your **local time**.
- **Live** — during a race weekend session, live running order (leader, positions, team colors) and track-flag status via the OpenF1 API; the pill shows a LIVE indicator and the tab auto-opens. Only polled while a session is on.
- **Grid** — appears once qualifying is done (and before the race starts): the
  provisional starting grid, and it becomes the default tab during that window.
- **Last** — the most recent race result (finishing order, gaps/status, points).
- **Drivers** / **Teams** — driver and constructor championship standings, with
  team-color chips, podium emphasis, and points-behind-leader gaps.

Team-color chips, a favorite driver/team highlight, 12/24-hour time, the bar
countdown target (next race vs next session), the default tab, and an optional
race-start desktop notification are all configurable in the widget's settings.

Data comes from the free [Jolpica-F1 API](https://github.com/jolpica/jolpica-f1)
(an Ergast-compatible mirror). No API key required. Circuit outlines are bundled
from [`bacinger/f1-circuits`](https://github.com/bacinger/f1-circuits) (MIT),
preprocessed into a `tracks.js` module by `tools/build-tracks.py` and drawn as
vector paths via QtQuick.Shapes — so they recolor to match your Omarchy theme.

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
omarchy restart shell                 # reload after each edit (rescanPlugins alone
                                      # won't reload changed QML — the shell caches it)
```

## Uninstall

```bash
omarchy plugin disable com.leafbox.f1
omarchy plugin remove com.leafbox.f1
omarchy restart shell
```

## Settings

Open the widget's settings from the Omarchy shell to configure: time format
(12/24-hour), bar countdown target (next race vs next session), default tab,
team-color chips on/off, a favorite driver (3-letter code) and team (id) to
highlight, and an optional pre-race desktop notification with lead time.

## Interaction

| Action | Result |
|---|---|
| Left click | Toggle the popup |
| Middle click | Force a data refresh |
| During a live session | The bar flag turns the theme accent color; the tooltip shows the leader/flag |

## How it works

- `BarWidget.qml` — the bar-slot button + popout-identity shim.
- `Panel.qml` — fetches `current/next.json` via `curl` (Quickshell `Process`),
  parses it, exposes `label`/`tooltip` to the pill, and renders the popup. A
  1-second timer advances the countdown; the schedule refetches every 6 hours.

## License

MIT (this plugin).

Bundled circuit geometry in `tracks.js` is derived from
[`bacinger/f1-circuits`](https://github.com/bacinger/f1-circuits),
Copyright (c) Tomo Bacinger, MIT License. Schedule/standings/results data © the
[Jolpica-F1](https://github.com/jolpica/jolpica-f1) project (Ergast-compatible
API); live timing © [OpenF1](https://openf1.org). No API keys required.
