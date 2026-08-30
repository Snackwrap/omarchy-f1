import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "tracks.js" as Tracks

// Fetches the next F1 race + championship standings from the Jolpica
// (Ergast-compatible) API, exposes a `label`/`tooltip` for the bar pill, and
// renders a popup with the circuit outline (hero), the weekend session schedule
// in local time, and driver/constructor standings tabs.
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

  // Which popup tab is showing: "schedule" | "drivers" | "constructors".
  property string view: "schedule"

  // Next race.
  property var race: null
  property bool loading: false
  property string lastError: ""

  // Standings (lazy-loaded on first tab switch).
  property var driverRows: []
  property var constructorRows: []
  property bool driversLoaded: false
  property bool constructorsLoaded: false

  readonly property string base: "https://api.jolpi.ca/ergast/f1/"

  function openFromHotkey() { open() }

  function refresh() {
    if (!fetchProc.running) { root.loading = true; fetchProc.running = true }
  }

  Component.onCompleted: refresh()

  // ---- Circuit outline data ---------------------------------------------
  // Bundled as a .pragma library JS module (tracks.js, built by tools/), so no
  // local-file XMLHttpRequest — Quickshell blocks that by default.
  readonly property string circuitId: (race && race.Circuit) ? (race.Circuit.circuitId || "") : ""
  readonly property var trackPoints: (circuitId && Tracks.TRACKS[circuitId]) ? Tracks.TRACKS[circuitId] : []

  // ---- Networking -------------------------------------------------------
  Process {
    id: fetchProc
    command: ["curl", "-fsS", "-A", "omarchy-f1/0.2", "--max-time", "10", root.base + "current/next.json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.loading = false
        var raw = String(text || "").trim()
        if (!raw) { root.lastError = "empty response"; return }
        try {
          var parsed = JSON.parse(raw)
          var races = parsed && parsed.MRData && parsed.MRData.RaceTable && parsed.MRData.RaceTable.Races
          if (races && races.length > 0) { root.race = races[0]; root.lastError = "" }
          else { root.race = null; root.lastError = "no upcoming race" }
        } catch (e) { root.lastError = "parse error" }
      }
    }
  }

  Process {
    id: driversProc
    command: ["curl", "-fsS", "-A", "omarchy-f1/0.2", "--max-time", "10", root.base + "current/driverStandings.json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var lists = JSON.parse(String(text || "")).MRData.StandingsTable.StandingsLists
          var arr = (lists && lists.length) ? lists[0].DriverStandings : []
          var out = []
          for (var i = 0; i < arr.length; i++) {
            var d = arr[i]
            out.push({
              pos: d.position,
              code: (d.Driver && d.Driver.code) ? d.Driver.code : (d.Driver ? d.Driver.familyName.substring(0, 3).toUpperCase() : "?"),
              name: d.Driver ? (d.Driver.givenName + " " + d.Driver.familyName) : "",
              team: (d.Constructors && d.Constructors.length) ? d.Constructors[d.Constructors.length - 1].name : "",
              pts: d.points
            })
          }
          root.driverRows = out
          root.driversLoaded = true
        } catch (e) { root.driversLoaded = true }
      }
    }
  }

  Process {
    id: constructorsProc
    command: ["curl", "-fsS", "-A", "omarchy-f1/0.2", "--max-time", "10", root.base + "current/constructorStandings.json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var lists = JSON.parse(String(text || "")).MRData.StandingsTable.StandingsLists
          var arr = (lists && lists.length) ? lists[0].ConstructorStandings : []
          var out = []
          for (var i = 0; i < arr.length; i++) {
            var c = arr[i]
            out.push({ pos: c.position, name: c.Constructor ? c.Constructor.name : "", pts: c.points })
          }
          root.constructorRows = out
          root.constructorsLoaded = true
        } catch (e) { root.constructorsLoaded = true }
      }
    }
  }

  function ensureDrivers() { if (!driversLoaded && !driversProc.running) driversProc.running = true }
  function ensureConstructors() { if (!constructorsLoaded && !constructorsProc.running) constructorsProc.running = true }

  onViewChanged: {
    if (view === "drivers") ensureDrivers()
    else if (view === "constructors") ensureConstructors()
  }

  // Refetch the schedule every 6 hours.
  Timer { interval: 6 * 60 * 60 * 1000; running: true; repeat: true; onTriggered: root.refresh() }
  // One-second countdown tick.
  Timer { interval: 1000; running: true; repeat: true; onTriggered: root.nowMs = Date.now() }

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

  readonly property string label: {
    if (!race || !raceStart) return ""
    return " " + fmtShort(raceMs - nowMs)  // nf-fa-flag_checkered
  }

  readonly property string tooltip: {
    if (!race) return "Formula 1"
    return (race.raceName || "Next race") + (raceStart ? " — " + Qt.formatDateTime(raceStart, "ddd d MMM, HH:mm") : "")
  }

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
    contentWidth: panel.fittedContentWidth(Style.space(440))
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

        // Tab bar
        Row {
          spacing: Style.space(16)
          Repeater {
            model: [
              { id: "schedule",     label: "Schedule" },
              { id: "drivers",      label: "Drivers" },
              { id: "constructors", label: "Constructors" }
            ]
            delegate: Text {
              text: modelData.label
              color: root.view === modelData.id ? Color.accent : Color.muted
              font.family: Style.font.family
              font.pixelSize: Style.space(13)
              font.bold: root.view === modelData.id
              MouseArea {
                anchors.fill: parent
                anchors.margins: -Style.space(4)
                cursorShape: Qt.PointingHandCursor
                onClicked: root.view = modelData.id
              }
            }
          }
        }

        // ---- Schedule tab ----
        Column {
          visible: root.view === "schedule" && !!root.race
          width: parent.width
          spacing: Style.space(10)

          Row {
            width: parent.width
            spacing: Style.space(14)

            TrackMap {
              width: Style.space(150)
              height: Style.space(112)
              points: root.trackPoints
              stroke: Color.popups.text
              strokeWidth: Math.max(1.5, Style.space(2))
            }

            Column {
              width: parent.width - Style.space(150) - Style.space(14)
              spacing: Style.space(3)
              Text {
                width: parent.width
                text: (root.race && root.race.Circuit) ? root.race.Circuit.circuitName : ""
                color: Color.popups.text
                font.family: Style.font.family
                font.pixelSize: Style.space(14)
                wrapMode: Text.WordWrap
                maximumLineCount: 2
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
          }

          // Session schedule (local time)
          Column {
            visible: root.sessions.length > 0
            width: parent.width
            spacing: Style.space(4)
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
        }

        // ---- Drivers tab ----
        Column {
          visible: root.view === "drivers"
          width: parent.width
          spacing: Style.space(4)
          Text {
            visible: root.driverRows.length === 0
            text: root.driversLoaded ? "No standings available" : "Loading…"
            color: Color.muted
            font.family: Style.font.family
            font.pixelSize: Style.space(13)
          }
          Repeater {
            model: root.driverRows.slice(0, 12)
            delegate: Row {
              width: content.width
              spacing: Style.space(8)
              Text {
                width: Style.space(22)
                text: modelData.pos
                color: Color.muted
                horizontalAlignment: Text.AlignRight
                font.family: Style.font.family
                font.pixelSize: Style.space(13)
              }
              Text {
                width: Style.space(40)
                text: modelData.code
                color: Color.popups.text
                font.family: Style.font.family
                font.pixelSize: Style.space(13)
                font.bold: true
              }
              Text {
                width: content.width - Style.space(22 + 40 + 52 + 24)
                text: modelData.team
                color: Color.muted
                elide: Text.ElideRight
                font.family: Style.font.family
                font.pixelSize: Style.space(13)
              }
              Text {
                width: Style.space(52)
                text: modelData.pts
                color: Color.popups.text
                horizontalAlignment: Text.AlignRight
                font.family: Style.font.family
                font.pixelSize: Style.space(13)
                font.bold: true
              }
            }
          }
        }

        // ---- Constructors tab ----
        Column {
          visible: root.view === "constructors"
          width: parent.width
          spacing: Style.space(4)
          Text {
            visible: root.constructorRows.length === 0
            text: root.constructorsLoaded ? "No standings available" : "Loading…"
            color: Color.muted
            font.family: Style.font.family
            font.pixelSize: Style.space(13)
          }
          Repeater {
            model: root.constructorRows
            delegate: Row {
              width: content.width
              spacing: Style.space(8)
              Text {
                width: Style.space(22)
                text: modelData.pos
                color: Color.muted
                horizontalAlignment: Text.AlignRight
                font.family: Style.font.family
                font.pixelSize: Style.space(13)
              }
              Text {
                width: content.width - Style.space(22 + 52 + 16)
                text: modelData.name
                color: Color.popups.text
                elide: Text.ElideRight
                font.family: Style.font.family
                font.pixelSize: Style.space(13)
              }
              Text {
                width: Style.space(52)
                text: modelData.pts
                color: Color.popups.text
                horizontalAlignment: Text.AlignRight
                font.family: Style.font.family
                font.pixelSize: Style.space(13)
                font.bold: true
              }
            }
          }
        }

        // Error footer
        Text {
          visible: root.lastError !== "" && !root.race
          width: parent.width
          text: "Couldn't load (" + root.lastError + ")"
          color: Color.muted
          font.family: Style.font.family
          font.pixelSize: Style.space(12)
          wrapMode: Text.WordWrap
        }
      }
    }
  }
}
