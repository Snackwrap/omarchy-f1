import QtQuick
import QtQuick.Shapes

// Draws a circuit outline as a single stroked vector polyline. `points` is an
// array of [x, y] pairs in a unit box (as produced by tools/build-tracks.py);
// they're fit-to-box with uniform scale, centered, on every resize. An optional
// start/finish tick is drawn perpendicular to the first segment.
//
// `playIntro()` runs a one-shot Mode 7 flip: the outline swings up from nearly
// edge-on to flat plan view, the way a SNES racer's ground plane resolves out
// of the horizon. It is one-shot on purpose — the popup is open for a few
// seconds, so a continuous spin would only ever be seen mid-turn, and the plan
// view is the orientation that makes a circuit recognisable.
Item {
  id: root

  property var points: []
  property color stroke: "#cacccc"
  property real strokeWidth: 2
  property real pad: 6
  property bool showStart: true

  readonly property bool hasTrack: points && points.length > 1

  function fittedPoints() {
    var pts = root.points
    if (!pts || pts.length < 2) return []
    var minx = 1e9, miny = 1e9, maxx = -1e9, maxy = -1e9
    for (var i = 0; i < pts.length; i++) {
      var p = pts[i]
      if (p[0] < minx) minx = p[0]
      if (p[0] > maxx) maxx = p[0]
      if (p[1] < miny) miny = p[1]
      if (p[1] > maxy) maxy = p[1]
    }
    var bw = (maxx - minx) || 1
    var bh = (maxy - miny) || 1
    var availW = Math.max(1, width - 2 * pad)
    var availH = Math.max(1, height - 2 * pad)
    var s = Math.min(availW / bw, availH / bh)
    var offx = pad + (availW - bw * s) / 2
    var offy = pad + (availH - bh * s) / 2
    var out = []
    for (var j = 0; j < pts.length; j++) {
      var q = pts[j]
      out.push(Qt.point(offx + (q[0] - minx) * s, offy + (q[1] - miny) * s))
    }
    return out
  }

  // Two points for a short line across the track at the start/finish.
  function startTick() {
    var fp = fittedPoints()
    if (fp.length < 2) return []
    var a = fp[0], b = fp[1]
    var dx = b.x - a.x, dy = b.y - a.y
    var len = Math.hypot(dx, dy) || 1
    var nx = -dy / len, ny = dx / len
    var half = Math.max(4, Math.min(width, height) * 0.07)
    return [Qt.point(a.x - nx * half, a.y - ny * half), Qt.point(a.x + nx * half, a.y + ny * half)]
  }

  // Mode 7 tilt about the horizontal axis: 0 is flat plan view, 90 edge-on.
  property real tilt: 0
  readonly property real peakTilt: 78
  // Eye distance, as a multiple of the item's height. Around 1.4 the far edge
  // comes out a little over half the width of the near one, which is the
  // convergence a 16-bit racer's ground plane has; much larger and the tilt
  // just looks like a vertical squash.
  property real depthFactor: 1.4
  // The plane also shrinks while tilted, which keeps the fanned-out near edge
  // inside the item's box (otherwise it overhangs ~60px at peak tilt and the
  // popup edge clips it) and adds the sense of it rushing up towards you.
  property real tiltShrink: 0.24
  property real introFade: 1
  property bool animateIntro: true

  // T(c) . P . Rx(tilt) . S . T(-c): rotate about the item's centre, then
  // divide. Composing the recentre into the same matrix matters — Qt Quick
  // flattens the whole transform list into one matrix and divides once at the
  // end, so a Translate applied afterwards would be divided too and the pivot
  // would drift across the flip. At tilt 0 this is exactly the identity, so
  // nothing moves by a subpixel when the animation is switched off.
  readonly property matrix4x4 mode7: {
    var a = tilt * Math.PI / 180
    var c = Math.cos(a), s = Math.sin(a)
    var cx = width / 2, cy = height / 2
    var k = -1 / Math.max(1, height * depthFactor)
    var g = 1 - tiltShrink * Math.min(1, Math.abs(tilt) / peakTilt)
    return Qt.matrix4x4(1, 0, 0, cx, 0, 1, 0, cy, 0, 0, 1, 0, 0, 0, 0, 1)
      .times(Qt.matrix4x4(1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, k, 1))
      .times(Qt.matrix4x4(1, 0, 0, 0, 0, c, -s, 0, 0, s, c, 0, 0, 0, 0, 1))
      .times(Qt.matrix4x4(g, 0, 0, 0, 0, g, 0, 0, 0, 0, g, 0, 0, 0, 0, 1))
      .times(Qt.matrix4x4(1, 0, 0, -cx, 0, 1, 0, -cy, 0, 0, 1, 0, 0, 0, 0, 1))
  }

  transform: Matrix4x4 { matrix: root.mode7 }

  // Overshooting slightly past flat and settling back reads as weight; the
  // fade is much shorter than the flip so the shape is legible while it lands.
  ParallelAnimation {
    id: introAnim
    NumberAnimation {
      target: root; property: "tilt"; from: root.peakTilt; to: 0; duration: 560
      easing.type: Easing.OutBack; easing.overshoot: 0.7
    }
    NumberAnimation {
      target: root; property: "introFade"; from: 0; to: 1; duration: 240
      easing.type: Easing.OutCubic
    }
  }

  function playIntro() {
    if (!animateIntro || !hasTrack) { introAnim.stop(); tilt = 0; introFade = 1; return }
    introAnim.restart()
  }

  Shape {
    anchors.fill: parent
    opacity: root.introFade
    visible: root.hasTrack
    antialiasing: true

    ShapePath {
      strokeColor: root.stroke
      strokeWidth: root.strokeWidth
      fillColor: "transparent"
      capStyle: ShapePath.RoundCap
      joinStyle: ShapePath.RoundJoin
      PathPolyline {
        // Re-evaluates on width/height/points changes (all read inside).
        path: root.fittedPoints()
      }
    }

    ShapePath {
      strokeColor: root.stroke
      strokeWidth: root.strokeWidth * 1.8
      fillColor: "transparent"
      capStyle: ShapePath.FlatCap
      PathPolyline {
        path: root.showStart ? root.startTick() : []
      }
    }
  }
}
