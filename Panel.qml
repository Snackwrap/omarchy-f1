import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Fetches the next F1 race from the Jolpica (Ergast-compatible) API, exposes a
// `label`/`tooltip` for the bar pill, and renders a popup with the circuit and
// the full weekend session schedule in the user's local time.
Panel {
  id: root
  moduleName: "com.leafbox.f1"
  ipcTarget: "com.leafbox.f1"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  // Live clock tick so the countdown advances without refetching.
  property double nowMs: Date.now()

  // Parsed "next race" object, or null while loading / on error.
  property var race: null
  property bool loading: false
  property string lastError: ""

  readonly property string apiUrl: "https://api.jolpi.ca/ergast/f1/current/next.json"

  function openFromHotkey() { open() }

  function refresh() {
    if (fetchProc.running) return
    root.loading = true
    fetchProc.running = true
  }

  Component.onCompleted: refresh()

  Process {
    id: fetchProc
    command: ["curl", "-fsS", "--max-time", "10", root.apiUrl]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.loading = false
        var raw = String(text || "").trim()
        if (!raw) { root.lastError = "empty response"; return }
        try {
          var parsed = JSON.parse(raw)
          var races = parsed && parsed.MRData && parsed.MRData.RaceTable && parsed.MRData.RaceTable.Races
          if (races && races.length > 0) {
            root.race = races[0]
            root.lastError = ""
          } else {
            root.race = null
            root.lastError = "no upcoming race"
          }
        } catch (e) {
          root.lastError = "parse error"
        }
      }
    }
  }

  // The calendar rarely changes; a few refetches a day is plenty.
  Timer {
    interval: 6 * 60 * 60 * 1000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  // One-second tick for the countdown display.
  Timer {
    interval: 1000
    running: true
    repeat: true
    onTriggered: root.nowMs = Date.now()
  }

  // ---- Derived values ---------------------------------------------------
  function sessionDate(s) {
    if (!s || !s.date) return null
    var t = (s.time && s.time.length) ? s.time : "00:00:00Z"
    var d = new Date(s.date + "T" + t)
    return isNaN(d.getTime()) ? null : d
  }

  readonly property var raceStart: race ? sessionDate({ date: race.date, time: race.time }) : null
  readonly property double raceMs: raceStart ? raceStart.getTime() : 0

  function fmtShort(ms) {
    if (ms <= 0) return "live"
    var s = Math.floor(ms / 1000)
    var d = Math.floor(s / 86400); s -= d * 86400
    var h = Math.floor(s / 3600); s -= h * 3600
    var m = Math.floor(s / 60)
    if (d > 0) return d + "d"
    if (h > 0) return h + "h"
    if (m > 0) return m + "m"
    return "<1m"
  }

  function fmtLong(ms) {
    if (ms <= 0) return "Race is live"
    var s = Math.floor(ms / 1000)
    var d = Math.floor(s / 86400); s -= d * 86400
    var h = Math.floor(s / 3600); s -= h * 3600
    var m = Math.floor(s / 60)
    var parts = []
    if (d > 0) parts.push(d + "d")
    if (h > 0) parts.push(h + "h")
    parts.push(m + "m")
    return "in " + parts.join(" ")
  }

  // Bar pill: checkered flag glyph + short countdown.
  readonly property string label: {
    if (!race || !raceStart) return ""
    return " " + fmtShort(raceMs - nowMs)  // nf-fa-flag_checkered
  }

  readonly property string tooltip: {
    if (!race) return "Formula 1"
    return (race.raceName || "Next race") + (raceStart ? " — " + Qt.formatDateTime(raceStart, "ddd d MMM, HH:mm") : "")
  }

  // Weekend sessions that exist, sorted chronologically (handles sprint layouts).
  readonly property var sessions: {
    if (!race) return []
    var raw = [
      { name: "Practice 1",   s: race.FirstPractice },
      { name: "Practice 2",   s: race.SecondPractice },
      { name: "Practice 3",   s: race.ThirdPractice },
      { name: "Sprint Quali", s: race.SprintQualifying },
      { name: "Sprint",       s: race.Sprint },
      { name: "Qualifying",   s: race.Qualifying },
      { name: "Race",         s: { date: race.date, time: race.time } }
    ]
    var out = []
    for (var i = 0; i < raw.length; i++) {
      var d = sessionDate(raw[i].s)
      if (d) out.push({ name: raw[i].name, date: d })
    }
    out.sort(function(a, b) { return a.date.getTime() - b.date.getTime() })
    return out
  }

  // ---- Popup ------------------------------------------------------------
  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: content
        width: parent.width
        spacing: Style.space(10)

        // Header
        Column {
          width: parent.width
          spacing: Style.space(2)
          Text {
            width: parent.width
            text: root.race ? root.race.raceName : (root.loading ? "Loading…" : "No upcoming race")
            color: Color.popups.text
            font.family: Style.font.family
            font.pixelSize: Style.space(20)
            font.bold: true
            elide: Text.ElideRight
          }
          Text {
            visible: !!root.race
            width: parent.width
            text: root.race ? ("Round " + root.race.round + " · " + root.race.season) : ""
            color: Color.muted
            font.family: Style.font.family
            font.pixelSize: Style.space(12)
            elide: Text.ElideRight
          }
        }

        // Circuit + big countdown
        Column {
          visible: !!root.race
          width: parent.width
          spacing: Style.space(2)
          Text {
            width: parent.width
            text: (root.race && root.race.Circuit) ? root.race.Circuit.circuitName : ""
            color: Color.popups.text
            font.family: Style.font.family
            font.pixelSize: Style.space(14)
            elide: Text.ElideRight
          }
          Text {
            width: parent.width
            text: {
              if (!root.race || !root.race.Circuit || !root.race.Circuit.Location) return ""
              var loc = root.race.Circuit.Location
              return (loc.locality || "") + ", " + (loc.country || "")
            }
            color: Color.muted
            font.family: Style.font.family
            font.pixelSize: Style.space(12)
            elide: Text.ElideRight
          }
          Text {
            width: parent.width
            topPadding: Style.space(6)
            text: root.raceStart ? root.fmtLong(root.raceMs - root.nowMs) : ""
            color: Color.accent
            font.family: Style.font.family
            font.pixelSize: Style.space(22)
            font.bold: true
          }
        }

        // Session schedule (local time)
        Column {
          visible: root.sessions.length > 0
          width: parent.width
          spacing: Style.space(4)
          topPadding: Style.space(4)
          Repeater {
            model: root.sessions
            delegate: Row {
              width: content.width
              spacing: Style.space(8)
              Text {
                width: Style.space(104)
                text: modelData.name
                color: Color.popups.text
                font.family: Style.font.family
                font.pixelSize: Style.space(13)
                elide: Text.ElideRight
              }
              Text {
                text: Qt.formatDateTime(modelData.date, "ddd HH:mm")
                color: Color.muted
                font.family: Style.font.family
                font.pixelSize: Style.space(13)
              }
            }
          }
        }

        // Error footer
        Text {
          visible: root.lastError !== "" && !root.race
          width: parent.width
          text: "Couldn't load schedule (" + root.lastError + ")"
          color: Color.muted
          font.family: Style.font.family
          font.pixelSize: Style.space(12)
          wrapMode: Text.WordWrap
        }
      }
    }
  }
}
