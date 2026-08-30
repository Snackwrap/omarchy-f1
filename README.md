# Formula 1 — Omarchy bar plugin

A checkered-flag pill for the [Omarchy](https://omarchy.org) (Quattro) bar that
counts down to the next Formula 1 race. Click it for a popup with the circuit
and the full weekend session schedule (practice, sprint, qualifying, race) in
your **local time**.

Data comes from the free [Jolpica-F1 API](https://github.com/jolpica/jolpica-f1)
(an Ergast-compatible mirror). No API key required.

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
