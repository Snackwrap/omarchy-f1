import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "tracks.js" as Tracks
import "teams.js" as Teams

// Fetches the next F1 race, standings, grid and last-race results from the
// Jolpica (Ergast-compatible) API, exposes a `label`/`tooltip` for the bar pill,
// and renders a tabbed popup with a circuit-outline hero. Configurable via the
// manifest settings schema (time format, countdown target, favorites, etc.).
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

  // Which popup tab is showing: schedule | grid | results | drivers | constructors.
  property string view: "schedule"
  property bool viewInitialized: false

  // Next race.
  property var race: null
  property bool loading: false
  property string lastError: ""

  // Lazy-loaded datasets.
  property var driverRows: []
  property var constructorRows: []
  property var gridRows: []
  property var resultsRows: []
  property bool driversLoaded: false
  property bool constructorsLoaded: false
  property bool gridLoaded: false
  property bool resultsLoaded: false
  property string resultsRaceName: ""

  // Notification bookkeeping.
  property int notifiedRound: -1

  // Live timing (OpenF1). Only polled while near a scheduled session.
  property var driversMap: ({})
  property bool driversMapLoaded: false
  property var livePosRows: []
  property double liveLatestMs: 0
  property string liveFlag: ""

  readonly property string base: "https://api.jolpi.ca/ergast/f1/"
  readonly property string openf1: "https://api.openf1.org/v1/"
  readonly property string ua: "omarchy-f1/0.11"

  // ---- Settings ---------------------------------------------------------
  readonly property string timeFormat: String(setting("timeFormat", "24h"))
  readonly property string dtPattern: timeFormat === "12h" ? "ddd h:mm AP" : "ddd HH:mm"
  readonly property string longPattern: timeFormat === "12h" ? "ddd d MMM, h:mm AP" : "ddd d MMM, HH:mm"
  readonly property string favDriver: String(setting("favoriteDriver", "")).toUpperCase().trim()
  readonly property string favTeam: String(setting("favoriteTeam", "")).toLowerCase().trim()
  // Wikipedia links come from the Ergast payload, so they are remote data. Hand the
  // string to Qt.openUrlExternally rather than a shell, and only for an https URL, so
  // a hostile `url` field cannot become anything but a rejected link.
  // These links come out of the Ergast payload, so the destination is remote
  // data. A scheme check alone still lets the API send a reader anywhere on the
  // web, so the host is checked against the ones this data is documented to
  // reference and everything else is dropped.
  readonly property var linkHosts: ["en.wikipedia.org", "www.wikipedia.org", "wikipedia.org"]

  function openLink(u) {
    var raw = String(u || "")
    if (raw.indexOf("https://") !== 0) return
    var rest = raw.slice(8)
    var slash = rest.indexOf("/")
    var host = (slash < 0 ? rest : rest.slice(0, slash)).toLowerCase()
    // Strip any userinfo and port so "en.wikipedia.org@evil.test" cannot pass.
    if (host.indexOf("@") >= 0) return
    if (host.indexOf(":") >= 0) host = host.slice(0, host.indexOf(":"))
    if (linkHosts.indexOf(host) < 0) return
    if (raw.length > 400) return
    Qt.openUrlExternally(raw)
  }

  // ---- Remote data hygiene ----------------------------------------------
  // Everything fetched below lands in a Text element or a notification. Two
  // ceilings rather than one: curl refuses to download more than
  // maxResponseBytes, and parseBounded rejects anything that got past it —
  // a chunked response has no Content-Length for curl to check.
  readonly property int maxResponseBytes: 524288
  readonly property int maxFieldChars: 72

  function fetchArgs(seconds, url) {
    return ["curl", "-fsS", "-A", ua,
            "--proto", "=https",                 // refuse anything but https
            "--max-time", String(seconds),
            "--max-filesize", String(maxResponseBytes),
            url]
  }

  function parseBounded(raw) {
    var text = String(raw || "")
    if (text.length === 0 || text.length > maxResponseBytes) return null
    return JSON.parse(text)
  }

  // Qt's Text defaults to AutoText, which renders a string as *rich* text when
  // it looks like markup. Every remote value is therefore forced through here:
  // control characters out, length clamped, and the Text elements that show
  // them are pinned to PlainText besides.
  // For the bar pill and its tooltip: those render in Text elements the shell
  // owns, so `textFormat` is not ours to set and the markup has to come out of
  // the string instead of being neutralised at the sink.
  function safeBare(v, limit) {
    return safe(v, limit).replace(/[<>&]/g, " ")
  }

  function safe(v, limit) {
    var text = String(v === null || v === undefined ? "" : v)
    text = text.replace(/[\u0000-\u001F\u007F]+/g, " ").replace(/^\s+|\s+$/g, "")
    var cap = limit || maxFieldChars
    return text.length > cap ? text.slice(0, cap) + "\u2026" : text
  }

  // An array from a remote payload is capped before anything walks it, so a
  // hostile or broken response cannot turn into tens of thousands of delegates.
  function boundedList(v, cap) {
    if (!v || !v.length) return []
    return v.length > cap ? v.slice(0, cap) : v
  }

  function boolSetting(name, dflt) { var v = setting(name, dflt); return v === true || v === "true" || v === 1 }
  readonly property bool teamColorsOn: boolSetting("teamColors", true)
  readonly property bool notifyOn: boolSetting("notifyRace", false)
  // One switch for both flourishes: the circuit's Mode 7 flip-in and the start
  // lights. Off leaves the panel completely still.
  readonly property bool animOn: boolSetting("raceAnimations", true)
  readonly property int notifyLead: parseInt(String(setting("notifyLeadMin", 10)), 10) || 0
  // Debug: force Grid & Live tabs to render using last-race data, so they can be
  // previewed outside a live session window.
  readonly property bool debug: boolSetting("debugForceTabs", false)

  function openFromHotkey() { open() }

  // Every request is stamped with the generation that made it, and a completion
  // whose stamp no longer matches is discarded rather than assigned to whatever
  // is selected by the time it lands.
  property int fetchGen: 0
  property var procGen: [0, 0, 0, 0, 0, 0, 0, 0]

  function stamp(i, proc) {
    var g = procGen
    g[i] = fetchGen
    procGen = g
    proc.running = true
  }

  function fresh(i) { return procGen[i] === fetchGen }

  function invalidate() {
    fetchGen += 1
    for (var i = 0; i < guardedProcs.length; i++) {
      if (guardedProcs[i].running) guardedProcs[i].running = false
    }
    loading = false
  }

  function refresh() {
    if (!fetchProc.running) { root.loading = true; stamp(0, fetchProc) }
  }

  Component.onCompleted: refresh()

  // With debugForceTabs on, defaultTab may name *any* tab and the choice is
  // pinned against the auto-switches below, so tools/capture-preview.sh can
  // shoot every tab without waiting for a live race weekend. This is derived
  // rather than latched in onSettingsChanged because `settings` is injected
  // before its values are populated — a latch reads the default and sticks.
  readonly property string pinnedView: debug ? String(setting("defaultTab", "schedule")) : ""
  onPinnedViewChanged: if (pinnedView !== "") view = pinnedView

  onSettingsChanged: {
    if (!viewInitialized && settings) {
      viewInitialized = true
      if (!gridApplicable) {
        var t = String(setting("defaultTab", "schedule"))
        if (t === "drivers" || t === "constructors") view = t
      }
    }
  }

  // ---- Circuit outline data (bundled JS module) -------------------------
  readonly property string circuitId: (race && race.Circuit) ? (race.Circuit.circuitId || "") : ""
  readonly property var trackPoints: (circuitId && Tracks.TRACKS[circuitId]) ? Tracks.TRACKS[circuitId] : []

  // ---- Networking -------------------------------------------------------
  Process {
    id: fetchProc
    command: root.fetchArgs(10, root.base + "current/next.json")
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (!root.fresh(0)) return      // superseded by a newer request
        root.loading = false
        var raw = String(text || "").trim()
        if (!raw) { root.lastError = "empty response"; return }
        try {
          var parsed = root.parseBounded(raw)
          if (!parsed) { root.loading = false; return }
          var races = parsed && parsed.MRData && parsed.MRData.RaceTable && parsed.MRData.RaceTable.Races
          if (races && races.length > 0) { root.race = races[0]; root.lastError = "" }
          else { root.race = null; root.lastError = "no upcoming race" }
        } catch (e) { root.lastError = "parse error" }
      }
    }
  }

  Process {
    id: driversProc
    command: root.fetchArgs(10, root.base + "current/driverStandings.json")
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (!root.fresh(1)) return      // superseded by a newer request
        try {
          var payload = root.parseBounded(text)
          if (!payload) return
          var lists = payload.MRData.StandingsTable.StandingsLists
          var arr = (lists && lists.length) ? lists[0].DriverStandings : []
          var leader = arr.length ? parseFloat(arr[0].points) : 0
          var out = []
          for (var i = 0; i < arr.length; i++) {
            var d = arr[i]
            var con = (d.Constructors && d.Constructors.length) ? d.Constructors[d.Constructors.length - 1] : null
            out.push({
              pos: d.position,
              code: (d.Driver && d.Driver.code) ? d.Driver.code : (d.Driver ? d.Driver.familyName.substring(0, 3).toUpperCase() : "?"),
              team: con ? con.name : "",
              teamId: con ? con.constructorId : "",
              pts: d.points,
              gap: i === 0 ? 0 : (leader - parseFloat(d.points)),
              url: (d.Driver && d.Driver.url) ? d.Driver.url : ""
            })
          }
          root.driverRows = root.boundedList(out, 30)
          root.driversLoaded = true
        } catch (e) { root.driversLoaded = true }
      }
    }
  }

  Process {
    id: constructorsProc
    command: root.fetchArgs(10, root.base + "current/constructorStandings.json")
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (!root.fresh(2)) return      // superseded by a newer request
        try {
          var payload = root.parseBounded(text)
          if (!payload) return
          var lists = payload.MRData.StandingsTable.StandingsLists
          var arr = (lists && lists.length) ? lists[0].ConstructorStandings : []
          var leader = arr.length ? parseFloat(arr[0].points) : 0
          var out = []
          for (var i = 0; i < arr.length; i++) {
            var c = arr[i]
            out.push({
              pos: c.position,
              name: c.Constructor ? c.Constructor.name : "",
              teamId: c.Constructor ? c.Constructor.constructorId : "",
              pts: c.points,
              gap: i === 0 ? 0 : (leader - parseFloat(c.points)),
              url: (c.Constructor && c.Constructor.url) ? c.Constructor.url : ""
            })
          }
          root.constructorRows = root.boundedList(out, 15)
          root.constructorsLoaded = true
        } catch (e) { root.constructorsLoaded = true }
      }
    }
  }

  Process {
    id: gridProc
    command: root.fetchArgs(10, root.debug
              ? (root.base + "current/last/qualifying.json")
              : (root.base + "current/" + (root.race ? root.race.round : "") + "/qualifying.json"))
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (!root.fresh(3)) return      // superseded by a newer request
        try {
          var payload = root.parseBounded(text)
          if (!payload) return
          var races = payload.MRData.RaceTable.Races
          var arr = (races && races.length) ? races[0].QualifyingResults : []
          var out = []
          for (var i = 0; i < arr.length; i++) {
            var q = arr[i]
            out.push({
              pos: q.position,
              code: (q.Driver && q.Driver.code) ? q.Driver.code : (q.Driver ? q.Driver.familyName.substring(0, 3).toUpperCase() : "?"),
              team: q.Constructor ? q.Constructor.name : "",
              teamId: q.Constructor ? q.Constructor.constructorId : "",
              detail: q.Q3 || q.Q2 || q.Q1 || "",
              url: (q.Driver && q.Driver.url) ? q.Driver.url : ""
            })
          }
          root.gridRows = root.boundedList(out, 30)
          root.gridLoaded = true
        } catch (e) { root.gridLoaded = true }
      }
    }
  }

  Process {
    id: resultsProc
    command: root.fetchArgs(10, root.base + "current/last/results.json")
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (!root.fresh(4)) return      // superseded by a newer request
        try {
          var payload = root.parseBounded(text)
          if (!payload) return
          var races = payload.MRData.RaceTable.Races
          var r0 = (races && races.length) ? races[0] : null
          var arr = r0 ? r0.Results : []
          root.resultsRaceName = r0 ? r0.raceName : ""
          var out = []
          for (var i = 0; i < arr.length; i++) {
            var r = arr[i]
            var detail = (r.Time && r.Time.time) ? r.Time.time : (r.status || "")
            out.push({
              pos: r.positionText,
              code: (r.Driver && r.Driver.code) ? r.Driver.code : (r.Driver ? r.Driver.familyName.substring(0, 3).toUpperCase() : "?"),
              team: r.Constructor ? r.Constructor.name : "",
              teamId: r.Constructor ? r.Constructor.constructorId : "",
              detail: detail,
              pts: r.points,
              url: (r.Driver && r.Driver.url) ? r.Driver.url : ""
            })
          }
          root.resultsRows = root.boundedList(out, 30)
          root.resultsLoaded = true
        } catch (e) { root.resultsLoaded = true }
      }
    }
  }

  Process { id: notifyProc; command: ["true"] }

  // ---- Live timing (OpenF1) ---------------------------------------------
  // Gated by nearSession (Jolpica schedule) so we never poll OpenF1 outside a
  // session window. Uses session_key=latest, which resolves to the current
  // session during that window; a freshness check guards against stale data.
  Process {
    id: ofDriversProc
    command: root.fetchArgs(10, root.openf1 + "drivers?session_key=latest")
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (!root.fresh(5)) return      // superseded by a newer request
        try {
          var arr = root.parseBounded(text)
          if (!arr) return
          var m = {}
          for (var i = 0; i < arr.length; i++) {
            var d = arr[i]
            m[d.driver_number] = {
              acr: d.name_acronym || ("#" + d.driver_number),
              color: d.team_colour ? ("#" + d.team_colour) : "",
              team: d.team_name || ""
            }
          }
          root.driversMap = m
          root.driversMapLoaded = true
        } catch (e) { root.driversMapLoaded = true }
      }
    }
  }

  Process {
    id: ofPosProc
    command: root.fetchArgs(12, root.openf1 + "position?session_key=latest")
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (!root.fresh(6)) return      // superseded by a newer request
        try {
          var arr = root.parseBounded(text)
          if (!arr) return
          var latest = {}
          for (var i = 0; i < arr.length; i++) {
            var r = arr[i]
            var n = r.driver_number
            if (!latest[n] || r.date > latest[n].date) latest[n] = { pos: r.position, date: r.date }
          }
          var rows = []
          var maxMs = 0
          for (var num in latest) {
            var t = new Date(latest[num].date).getTime()
            if (t > maxMs) maxMs = t
            var info = root.driversMap[num] || {}
            rows.push({ pos: latest[num].pos, code: info.acr || ("#" + num), color: info.color || "", team: info.team || "" })
          }
          rows.sort(function(a, b) { return a.pos - b.pos })
          root.livePosRows = root.boundedList(rows, 30)
          root.liveLatestMs = maxMs
        } catch (e) { /* keep last-good */ }
      }
    }
  }

  Process {
    id: ofFlagProc
    command: root.fetchArgs(10, root.openf1 + "race_control?session_key=latest")
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (!root.fresh(7)) return      // superseded by a newer request
        try {
          var arr = root.parseBounded(text)
          if (!arr) return
          var last = ""
          for (var i = 0; i < arr.length; i++)
            if (arr[i].category === "Flag" && arr[i].scope === "Track" && arr[i].flag) last = arr[i].flag
          root.liveFlag = last
        } catch (e) { /* ignore */ }
      }
    }
  }

  // Near a scheduled session? (15 min before start .. 3 h after) — the only
  // window in which we touch OpenF1 at all.
  readonly property bool nearSession: {
    for (var i = 0; i < sessions.length; i++) {
      var t = sessions[i].date.getTime()
      if (nowMs >= t - 15 * 60000 && nowMs <= t + 3 * 3600000) return true
    }
    return false
  }

  // Live only when near a session AND the position feed is genuinely fresh
  // (guards against session_key=latest resolving to a finished race).
  readonly property bool liveFresh: liveLatestMs > 0 && (nowMs - liveLatestMs) < 15 * 60000
  readonly property bool liveActive: livePosRows.length > 0 && (debug || (nearSession && liveFresh))
  readonly property string liveLeader: (liveActive && livePosRows.length) ? livePosRows[0].code : ""
  readonly property string liveLabelPrefix: ""  // live: flag glyph only; color signals live

  function pollLive() {
    if (!nearSession && !debug) return
    if (!driversMapLoaded && !ofDriversProc.running) stamp(5, ofDriversProc)
    if (!ofPosProc.running) stamp(6, ofPosProc)
    if (!ofFlagProc.running) stamp(7, ofFlagProc)
  }

  onNearSessionChanged: {
    if (nearSession) pollLive()
    else if (!debug) { driversMapLoaded = false; livePosRows = []; liveLatestMs = 0; liveFlag = "" }
  }

  onLiveActiveChanged: {
    if (pinnedView !== "") return
    if (liveActive) { if (view === "schedule" || view === "grid") view = "live" }
    else if (view === "live") view = "schedule"
  }

  // Poll live data every 15s while near a session (well under OpenF1's 30/min).
  Timer {
    interval: 15000
    running: root.nearSession || root.debug
    repeat: true
    triggeredOnStart: true
    onTriggered: root.pollLive()
  }

  function friendlyFlag(f) {
    if (!f) return ""
    var map = { "GREEN": "Green flag", "CLEAR": "Track clear", "YELLOW": "Yellow flag",
      "DOUBLE YELLOW": "Double yellow", "RED": "Red flag", "CHEQUERED": "Chequered flag",
      "BLUE": "Blue flag" }
    return map[f] || f
  }

  function ensureDrivers() { if (!driversLoaded && !driversProc.running) stamp(1, driversProc) }
  function ensureConstructors() { if (!constructorsLoaded && !constructorsProc.running) stamp(2, constructorsProc) }
  function ensureGrid() { if ((race || debug) && !gridLoaded && !gridProc.running) stamp(3, gridProc) }
  function ensureResults() { if (!resultsLoaded && !resultsProc.running) stamp(4, resultsProc) }

  onViewChanged: {
    if (view === "drivers") ensureDrivers()
    else if (view === "constructors") ensureConstructors()
    else if (view === "grid") ensureGrid()
    else if (view === "results") ensureResults()
    else if (view === "schedule" && opened) Qt.callLater(playIntro)
  }

  // Grid is available once qualifying has finished (+~1h buffer) and the race
  // hasn't started yet; it becomes the default view then (TRMNL-style).
  readonly property var qualiStart: race ? sessionDate(race.Qualifying) : null
  readonly property bool gridApplicable: {
    if (!qualiStart || !raceStart) return false
    return (nowMs >= qualiStart.getTime() + 60 * 60 * 1000) && (nowMs < raceMs)
  }

  onRaceChanged: invalidate()

  onGridApplicableChanged: {
    if (pinnedView !== "") return
    if (gridApplicable) {
      ensureGrid()
      if (view === "schedule") view = "grid"
    } else if (view === "grid") {
      view = "schedule"
    }
  }

  readonly property var tabs: {
    // Live is always visible (with an informative empty state when idle) so
    // users discover the feature before race day; it gains the ● when active.
    var t = [{ id: "schedule", label: "Schedule" }]
    if (gridApplicable || debug) t.push({ id: "grid", label: "Grid" })
    t.push({ id: "live", label: liveActive ? "● Live" : "Live" })
    t.push({ id: "results", label: "Last" })
    t.push({ id: "drivers", label: "Drivers" })
    t.push({ id: "constructors", label: "Teams" })
    return t
  }

  // curl's --max-time is curl's to honour, and it is the only clock the
  // subprocess has. This is an independent one: any fetch still alive past its
  // own limit plus a grace period is terminated from here, which also unsticks
  // `loading` if a process wedges without ever exiting.
  readonly property var guardedProcs: [fetchProc, driversProc, constructorsProc,
                                       gridProc, resultsProc,
                                       ofDriversProc, ofPosProc, ofFlagProc]
  readonly property var guardLimits: [10, 10, 10, 10, 10, 10, 12, 10]
  property var guardStarted: [0, 0, 0, 0, 0, 0, 0, 0]

  Timer {
    interval: 2000
    running: true
    repeat: true
    onTriggered: {
      var now = Date.now()
      var started = root.guardStarted
      for (var i = 0; i < root.guardedProcs.length; i++) {
        var proc = root.guardedProcs[i]
        if (!proc.running) { started[i] = 0; continue }
        if (!started[i]) { started[i] = now; continue }
        if (now - started[i] > (root.guardLimits[i] + 5) * 1000) {
          proc.running = false      // Quickshell terminates the child
          started[i] = 0
          root.loading = false
        }
      }
      root.guardStarted = started
    }
  }

  // Refetch the schedule every 6 hours.
  Timer { interval: 6 * 60 * 60 * 1000; running: true; repeat: true; onTriggered: root.refresh() }
  // One-second countdown tick + notification check.
  Timer {
    interval: 1000; running: true; repeat: true
    onTriggered: { root.nowMs = Date.now(); root.checkNotify() }
  }

  function checkNotify() {
    if (!notifyOn || !race || !raceStart) return
    var r = parseInt(race.round, 10)
    if (notifiedRound === r) return
    var lead = notifyLead * 60000
    if (nowMs >= raceMs - lead && nowMs < raceMs + 5 * 60000) {
      notifiedRound = r
      notifyProc.command = ["omarchy-notification-send", "-g", "\uf11e", "-u", "normal",
        safe(race.raceName || "Formula 1", 60), "Lights out " + fmtLong(raceMs - nowMs)]
      notifyProc.running = true
    }
  }

  // ---- Intro flourishes --------------------------------------------------
  // The gantry is only meaningful around the race itself: from three hours
  // before lights out until roughly the flag. Outside that it would be
  // decoration pretending to be a signal, so it is not drawn at all.
  readonly property bool raceDay: {
    if (debug) return true   // same escape hatch the Grid/Live tabs use
    if (!raceStart) return false
    return nowMs >= raceMs - 3 * 3600000 && nowMs < raceMs + 3 * 3600000
  }
  // Lights out *is* the start, so the sequence only ends dark once the race is
  // actually running; before that it holds on all five, which is the real
  // moment on the grid and the honest one here.
  readonly property bool raceUnderway: raceStart ? nowMs >= raceMs : false

  function playIntro() {
    if (!animOn || view !== "schedule") return
    if (trackHero && trackHero.hasTrack) trackHero.playIntro()
    if (raceDay && startLights) startLights.play()
  }

  onOpenedChanged: if (opened) Qt.callLater(playIntro)

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
    if (ms <= 0) return "live now"
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

  // First session still in the future (drives emphasis + optional pill target).
  readonly property var nextSession: {
    for (var i = 0; i < sessions.length; i++)
      if (sessions[i].date.getTime() > nowMs) return sessions[i]
    return null
  }

  readonly property double pillTargetMs: {
    if (String(setting("countdownTarget", "race")) === "session" && nextSession)
      return nextSession.date.getTime()
    return raceMs
  }

  readonly property string label: {
    if (liveActive) return liveLabelPrefix
    if (!race || !raceStart) return ""
    return " " + fmtShort(pillTargetMs - nowMs)  // nf-fa-flag_checkered
  }

  readonly property string tooltip: {
    if (liveActive) return "LIVE" + (liveLeader ? " · P1 " + safeBare(liveLeader, 4) : "")
                    + (liveFlag ? " · " + safeBare(friendlyFlag(liveFlag), 24) : "")
    if (!race) return "Formula 1"
    return safeBare(race.raceName || "Next race", 48)
           + (raceStart ? " — " + Qt.formatDateTime(raceStart, longPattern) : "")
  }

  function teamColor(teamId) { return Teams.colorFor(teamId, Color.muted) }
  function isFavRow(row) {
    return (favDriver !== "" && row.code === favDriver) || (favTeam !== "" && row.teamId === favTeam)
  }

  // ---- Popup ------------------------------------------------------------
  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    // Anchor under the bar icon by default; "center" setting centers on the bar.
    centerOnBar: String(root.setting("popupPosition", "icon")) === "center"
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(480))
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

        // Masthead: flag + wordmark on the left, round/season on the right.
        // (Custom wordmark, not the trademarked F1 logo.)
        Item {
          width: parent.width
          height: brandRow.implicitHeight
          Row {
            id: brandRow
            spacing: Style.space(7)
            anchors.left: parent.left
            Text {
              textFormat: Text.PlainText
              text: ""
              color: Color.accent
              font.family: Style.font.family
              font.pixelSize: Style.space(14)
              anchors.verticalCenter: parent.verticalCenter
            }
            Text {
              textFormat: Text.PlainText
              text: "FORMULA 1"
              color: Color.muted
              font.family: Style.font.family
              font.pixelSize: Style.space(11)
              font.bold: true
              font.letterSpacing: Style.space(3)
              anchors.verticalCenter: parent.verticalCenter
            }
          }
          Text {
            textFormat: Text.PlainText
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.race ? ("Round " + root.race.round + " · " + root.race.season) : ""
            color: Color.muted
            font.family: Style.font.family
            font.pixelSize: Style.space(11)
          }
        }

        PanelSeparator { foreground: Color.popups.text }

        // Race name
        Text {
          textFormat: Text.PlainText
          width: parent.width
          text: root.race ? root.safe(root.race.raceName, 48) : (root.loading ? "Loading…" : "No upcoming race")
          color: Color.popups.text
          font.family: Style.font.family
          font.pixelSize: Style.space(20)
          font.bold: true
          elide: Text.ElideRight
        }

        // Tab bar: the shell's segmented control, so tabs read as buttons and
        // pick up the theme's hover/selected chrome.
        ButtonGroup {
          options: {
            var o = []
            for (var i = 0; i < root.tabs.length; i++)
              o.push({ value: root.tabs[i].id, label: root.tabs[i].label })
            return o
          }
          value: root.view
          focusable: false
          foreground: Color.popups.text
          background: Color.popups.background
          accent: Color.accent
          fontSize: Style.space(12)
          onChanged: function(v) { root.view = v }
        }

        // ---- Live tab (OpenF1 running order) ----
        Column {
          visible: root.view === "live"
          width: parent.width
          spacing: Style.space(4)

          // Idle empty state: tells users what this tab does and when it wakes.
          Column {
            visible: !root.liveActive
            width: parent.width
            spacing: Style.space(4)
            PanelSectionHeader {
              text: "LIVE TIMING"
              foreground: Color.popups.text
              font.letterSpacing: Style.space(2)
            }
            Text {
              textFormat: Text.PlainText
              width: parent.width
              text: "No session running right now."
              color: Color.popups.text
              font.family: Style.font.family
              font.pixelSize: Style.space(13)
            }
            Text {
              textFormat: Text.PlainText
              width: parent.width
              text: "Live positions and track flags appear here automatically during practice, qualifying and the race."
              color: Color.muted
              wrapMode: Text.WordWrap
              font.family: Style.font.family
              font.pixelSize: Style.space(12)
            }
            Text {
              textFormat: Text.PlainText
              visible: !!root.nextSession
              width: parent.width
              topPadding: Style.space(4)
              text: root.nextSession ? ("Next: " + root.safe(root.nextSession.name, 24) + " · " + Qt.formatDateTime(root.nextSession.date, root.dtPattern)) : ""
              color: Color.accent
              font.family: Style.font.family
              font.pixelSize: Style.space(12)
              font.bold: true
            }
          }

          Row {
            visible: root.liveActive
            width: parent.width
            spacing: Style.space(8)
            bottomPadding: Style.space(2)
            Text {
              textFormat: Text.PlainText
              text: "● LIVE"
              color: Color.accent
              font.family: Style.font.family
              font.pixelSize: Style.space(12)
              font.bold: true
            }
            Text {
              textFormat: Text.PlainText
              visible: root.liveFlag !== ""
              text: root.safe(root.friendlyFlag(root.liveFlag), 24)
              color: Color.muted
              font.family: Style.font.family
              font.pixelSize: Style.space(12)
            }
          }
          Repeater {
            model: root.livePosRows.slice(0, 20)
            delegate: Row {
              width: content.width
              spacing: Style.space(8)
              Rectangle {
                width: Style.space(3); height: Style.space(15); radius: 1
                anchors.verticalCenter: parent.verticalCenter
                visible: root.teamColorsOn && modelData.color !== ""
                color: modelData.color !== "" ? modelData.color : Color.muted
              }
              Text {
                textFormat: Text.PlainText
                width: Style.space(22); text: modelData.pos
                color: (modelData.pos <= 3) ? Color.popups.text : Color.muted
                horizontalAlignment: Text.AlignRight
                font.family: Style.font.family; font.pixelSize: Style.space(13)
              }
              Text {
                textFormat: Text.PlainText
                width: Style.space(44); text: root.safe(modelData.code, 4)
                color: (root.favDriver !== "" && modelData.code === root.favDriver) ? Color.accent : Color.popups.text
                font.family: Style.font.family; font.pixelSize: Style.space(13); font.bold: true
              }
              Text {
                textFormat: Text.PlainText
                width: content.width - Style.space(3 + 22 + 44 + 24)
                text: root.safe(modelData.team, 32); color: Color.muted; elide: Text.ElideRight
                font.family: Style.font.family; font.pixelSize: Style.space(13)
              }
            }
          }
        }

        // ---- Schedule tab ----
        // The circuit outline is drawn as a large low-opacity watermark behind
        // the content (TRMNL-style) rather than a small boxed hero.
        Item {
          visible: root.view === "schedule" && !!root.race
          width: parent.width
          height: scheduleCol.implicitHeight

          TrackMap {
            id: trackHero
            animateIntro: root.animOn
            anchors.right: parent.right
            anchors.rightMargin: Style.space(6)
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(parent.width * 0.5, Style.space(240))
            height: Math.min(parent.height * 0.82, Style.space(220))
            points: root.trackPoints
            stroke: Color.popups.text
            strokeWidth: Math.max(2, Style.space(3))
            opacity: 0.22
          }

          Column {
            id: scheduleCol
            width: parent.width
            spacing: Style.space(10)

            Column {
              width: parent.width
              spacing: Style.space(2)
              Text {
                textFormat: Text.PlainText
                width: parent.width
                text: (root.race && root.race.Circuit) ? root.safe(root.race.Circuit.circuitName, 48) : ""
                color: Color.popups.text
                font.family: Style.font.family
                font.pixelSize: Style.space(14)
                elide: Text.ElideRight
              }
              Text {
                textFormat: Text.PlainText
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
            }

            Column {
              width: parent.width
              spacing: 0
              Row {
                spacing: Style.space(10)
                PanelSectionHeader {
                  text: "LIGHTS OUT"
                  foreground: Color.popups.text
                  font.letterSpacing: Style.space(2)
                  anchors.verticalCenter: parent.verticalCenter
                }
                StartLights {
                  id: startLights
                  visible: root.animOn && root.raceDay
                  releaseToBlackout: root.raceUnderway
                  cell: Style.space(9)
                  anchors.verticalCenter: parent.verticalCenter
                }
              }
              Text {
                textFormat: Text.PlainText
                width: parent.width
                text: root.raceStart ? root.fmtLong(root.raceMs - root.nowMs) : ""
                color: Color.accent
                font.family: Style.font.family
                font.pixelSize: Style.space(22)
                font.bold: true
              }
            }

          // Session schedule (local time), next session emphasized
          Column {
            visible: root.sessions.length > 0
            width: parent.width
            spacing: Style.space(4)
            PanelSectionHeader {
              text: "SESSIONS"
              foreground: Color.popups.text
              font.letterSpacing: Style.space(2)
            }
            Repeater {
              model: root.sessions
              delegate: Row {
                width: content.width
                spacing: Style.space(8)
                property bool past: modelData.date.getTime() <= root.nowMs
                property bool isNext: root.nextSession && modelData.date.getTime() === root.nextSession.date.getTime()
                Text {
                  textFormat: Text.PlainText
                  width: Style.space(104)
                  text: root.safe(modelData.name, 24)
                  color: isNext ? Color.accent : (past ? Color.muted : Color.popups.text)
                  font.family: Style.font.family
                  font.pixelSize: Style.space(13)
                  font.bold: isNext
                  elide: Text.ElideRight
                }
                Text {
                  textFormat: Text.PlainText
                  width: Style.space(120)
                  text: Qt.formatDateTime(modelData.date, root.dtPattern)
                  color: isNext ? Color.popups.text : Color.muted
                  font.family: Style.font.family
                  font.pixelSize: Style.space(13)
                }
              }
            }
          }
          }
        }

        // ---- Grid tab (starting grid = qualifying order) ----
        Column {
          visible: root.view === "grid"
          width: parent.width
          spacing: Style.space(4)
          Text {
            textFormat: Text.PlainText
            visible: root.gridRows.length === 0
            text: root.gridLoaded ? "No grid available" : "Loading…"
            color: Color.muted
            font.family: Style.font.family
            font.pixelSize: Style.space(13)
          }
          PanelSectionHeader {
            visible: root.gridRows.length > 0
            width: parent.width
            text: "STARTING GRID"
            foreground: Color.popups.text
            font.letterSpacing: Style.space(2)
          }
          Text {
            textFormat: Text.PlainText
            visible: root.gridRows.length > 0
            width: parent.width
            bottomPadding: Style.space(2)
            text: "Provisional — excludes penalties"
            color: Color.muted
            font.family: Style.font.family
            font.pixelSize: Style.space(11)
            elide: Text.ElideRight
          }
          Repeater {
            model: root.gridRows
            delegate: ResultRow {
              row: modelData
              rowWidth: content.width
              detailWidth: Style.space(76)
            }
          }
        }

        // ---- Last-race results tab ----
        Column {
          visible: root.view === "results"
          width: parent.width
          spacing: Style.space(4)
          Text {
            textFormat: Text.PlainText
            visible: root.resultsRows.length === 0
            text: root.resultsLoaded ? "No results yet" : "Loading…"
            color: Color.muted
            font.family: Style.font.family
            font.pixelSize: Style.space(13)
          }
          PanelSectionHeader {
            visible: root.resultsRows.length > 0 && root.resultsRaceName !== ""
            width: parent.width
            text: "LAST RACE · " + root.resultsRaceName.toUpperCase()
            foreground: Color.popups.text
            font.letterSpacing: Style.space(2)
            elide: Text.ElideRight
          }
          Repeater {
            model: root.resultsRows.slice(0, 12)
            delegate: ResultRow {
              row: modelData
              rowWidth: content.width
              detailWidth: Style.space(92)
              points: modelData.pts
            }
          }
        }

        // ---- Drivers tab ----
        Column {
          visible: root.view === "drivers"
          width: parent.width
          spacing: Style.space(4)
          Text {
            textFormat: Text.PlainText
            visible: root.driverRows.length === 0
            text: root.driversLoaded ? "No standings available" : "Loading…"
            color: Color.muted
            font.family: Style.font.family
            font.pixelSize: Style.space(13)
          }
          PanelSectionHeader {
            visible: root.driverRows.length > 0
            text: "DRIVER STANDINGS"
            foreground: Color.popups.text
            font.letterSpacing: Style.space(2)
          }
          Repeater {
            model: root.driverRows.slice(0, 12)
            delegate: StandingRow {
              row: modelData
              rowWidth: content.width
              primary: modelData.code
              secondary: modelData.team
            }
          }
        }

        // ---- Constructors tab ----
        Column {
          visible: root.view === "constructors"
          width: parent.width
          spacing: Style.space(4)
          Text {
            textFormat: Text.PlainText
            visible: root.constructorRows.length === 0
            text: root.constructorsLoaded ? "No standings available" : "Loading…"
            color: Color.muted
            font.family: Style.font.family
            font.pixelSize: Style.space(13)
          }
          PanelSectionHeader {
            visible: root.constructorRows.length > 0
            text: "CONSTRUCTOR STANDINGS"
            foreground: Color.popups.text
            font.letterSpacing: Style.space(2)
          }
          Repeater {
            model: root.constructorRows
            delegate: StandingRow {
              row: modelData
              rowWidth: content.width
              primary: modelData.name
              secondary: ""
            }
          }
        }

        // Error footer
        Text {
          textFormat: Text.PlainText
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

  // ---- Row components ---------------------------------------------------
  // A grid/results row: [team chip] pos · code · team · detail(time|status).
  component ResultRow: Rectangle {
    id: rr
    property var row: ({})
    property real rowWidth: 0
    property real detailWidth: Style.space(76)
    property string points: ""
    width: rowWidth
    height: rrRow.implicitHeight + Style.space(5)
    radius: Style.space(4)
    color: rrMouse.containsMouse ? Style.hoverFill : "transparent"

    MouseArea {
      id: rrMouse
      anchors.fill: parent
      hoverEnabled: !!rr.row.url
      cursorShape: rr.row.url ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: root.openLink(rr.row.url)
    }

    Row {
    id: rrRow
    width: parent.width
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(8)
    Rectangle {
      width: Style.space(3); height: Style.space(15); radius: 1
      anchors.verticalCenter: parent.verticalCenter
      visible: root.teamColorsOn
      color: root.teamColor(rr.row.teamId)
    }
    Text {
      textFormat: Text.PlainText
      width: Style.space(22); text: rr.row.pos
      color: (parseInt(rr.row.pos, 10) <= 3) ? Color.popups.text : Color.muted
      horizontalAlignment: Text.AlignRight
      font.family: Style.font.family; font.pixelSize: Style.space(13)
    }
    Text {
      textFormat: Text.PlainText
      width: Style.space(40); text: root.safe(rr.row.code, 4)
      color: root.isFavRow(rr.row) ? Color.accent : Color.popups.text
      font.family: Style.font.family; font.pixelSize: Style.space(13); font.bold: true
    }
    Text {
      textFormat: Text.PlainText
      width: Math.max(Style.space(40), rr.rowWidth - Style.space(3 + 22 + 40) - rr.detailWidth - (rr.points !== "" ? Style.space(32) : 0) - Style.space(40))
      text: root.safe(rr.row.team, 32); color: Color.muted; elide: Text.ElideRight
      font.family: Style.font.family; font.pixelSize: Style.space(13)
    }
    Text {
      textFormat: Text.PlainText
      width: rr.detailWidth; text: rr.row.detail
      color: Color.popups.text; horizontalAlignment: Text.AlignRight
      font.family: Style.font.family; font.pixelSize: Style.space(13); elide: Text.ElideLeft
    }
    Text {
      textFormat: Text.PlainText
      visible: rr.points !== ""
      width: Style.space(32); text: root.safe(rr.points, 6)
      color: Color.muted; horizontalAlignment: Text.AlignRight
      font.family: Style.font.family; font.pixelSize: Style.space(13)
    }
    }
  }

  // A standings row: [team chip] pos · primary · secondary · gap · points.
  component StandingRow: Rectangle {
    id: sr
    property var row: ({})
    property real rowWidth: 0
    property string primary: ""
    property string secondary: ""
    width: rowWidth
    height: srRow.implicitHeight + Style.space(5)
    radius: Style.space(4)
    color: srMouse.containsMouse ? Style.hoverFill : "transparent"

    MouseArea {
      id: srMouse
      anchors.fill: parent
      hoverEnabled: !!sr.row.url
      cursorShape: sr.row.url ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: root.openLink(sr.row.url)
    }

    Row {
    id: srRow
    width: parent.width
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(8)
    Rectangle {
      width: Style.space(3); height: Style.space(15); radius: 1
      anchors.verticalCenter: parent.verticalCenter
      visible: root.teamColorsOn
      color: root.teamColor(sr.row.teamId)
    }
    Text {
      textFormat: Text.PlainText
      width: Style.space(22); text: sr.row.pos
      color: (parseInt(sr.row.pos, 10) <= 3) ? Color.popups.text : Color.muted
      horizontalAlignment: Text.AlignRight
      font.family: Style.font.family; font.pixelSize: Style.space(13)
    }
    Text {
      textFormat: Text.PlainText
      width: Style.space(48); text: sr.primary
      color: root.isFavRow(sr.row) ? Color.accent : Color.popups.text
      font.family: Style.font.family; font.pixelSize: Style.space(13); font.bold: true
    }
    Text {
      textFormat: Text.PlainText
      width: Math.max(Style.space(20), sr.rowWidth - Style.space(3 + 22 + 48) - Style.space(44) - Style.space(52) - Style.space(48))
      text: sr.secondary; color: Color.muted; elide: Text.ElideRight
      font.family: Style.font.family; font.pixelSize: Style.space(13)
    }
    Text {
      textFormat: Text.PlainText
      width: Style.space(44)
      text: sr.row.gap > 0 ? ("-" + sr.row.gap) : ""
      color: Color.muted; horizontalAlignment: Text.AlignRight
      font.family: Style.font.family; font.pixelSize: Style.space(12)
    }
    Text {
      textFormat: Text.PlainText
      width: Style.space(52); text: sr.row.pts
      color: Color.popups.text; horizontalAlignment: Text.AlignRight
      font.family: Style.font.family; font.pixelSize: Style.space(13); font.bold: true
    }
    }
  }
}
