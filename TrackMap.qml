import QtQuick
import QtQuick.Shapes

// Draws a circuit outline as a single stroked vector polyline. `points` is an
// array of [x, y] pairs in a unit box (as produced by tools/build-tracks.py);
// they're fit-to-box with uniform scale, centered, on every resize.
Item {
  id: root

  property var points: []
  property color stroke: "#cacccc"
  property real strokeWidth: 2
  property real pad: 4

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

  Shape {
    anchors.fill: parent
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
  }
}
