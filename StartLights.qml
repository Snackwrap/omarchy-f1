import QtQuick

// The five-light F1 starting gantry: five columns of two lights that
// illuminate one column at a time, the way they do on the grid.
//
// How the sequence ends depends on the race, which is the point of it. Before
// lights out the run stops with all five lit — the real moment of held breath,
// and honest, because the race has not started. Once the race is under way it
// finishes the way the real one does: everything goes dark, because lights out
// *is* the start.
Item {
  id: root

  property int columns: 5
  property int lit: 0                 // columns currently illuminated
  property bool blackout: false       // all out — race running
  property bool releaseToBlackout: false

  property color onColor: "#E10600"   // F1 red, as in teams.js: this is a
                                      // depiction of a physical signal, not a
                                      // palette choice, so it ignores the theme
  property color offColor: "#3A3F44"
  property color railColor: "#22262A"

  property real cell: 13
  property int stepMs: 620
  property int holdMs: 1100

  implicitWidth: columns * cell * 1.55
  implicitHeight: cell * 2.9

  function play() {
    stepTimer.stop()
    lit = 0
    blackout = false
    stepTimer.interval = stepMs
    stepTimer.start()
  }

  function reset() { stepTimer.stop(); lit = 0; blackout = false }

  Timer {
    id: stepTimer
    repeat: true
    onTriggered: {
      if (root.lit < root.columns) {
        root.lit++
        // Hold on the full gantry before the release, as the starter does.
        if (root.lit === root.columns) interval = root.holdMs
      } else if (root.releaseToBlackout) {
        root.blackout = true
        stop()
      } else {
        stop()
      }
    }
  }

  Rectangle {
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.top: parent.top
    width: parent.width
    height: Math.max(1, root.cell * 0.16)
    color: root.railColor
    radius: height / 2
  }

  // One lamp. Declared as a component rather than a second nested Repeater so
  // `on` is passed down explicitly instead of reached for up a parent chain.
  component Lamp: Rectangle {
    required property bool on
    property real size: 10
    property color litColor: "#E10600"
    property color darkColor: "#3A3F44"

    width: size
    height: size
    radius: width / 2
    color: on ? litColor : darkColor
    opacity: on ? 1 : 0.55
    Behavior on color { ColorAnimation { duration: 90 } }
    Behavior on opacity { NumberAnimation { duration: 90 } }

    // A soft halo, so a lit pair reads as emitting rather than merely filled.
    Rectangle {
      anchors.centerIn: parent
      width: parent.width * 1.9
      height: width
      radius: width / 2
      color: parent.litColor
      opacity: parent.on ? 0.16 : 0
      z: -1
      Behavior on opacity { NumberAnimation { duration: 140 } }
    }
  }

  Row {
    anchors.centerIn: parent
    spacing: root.cell * 0.55

    Repeater {
      model: root.columns

      Column {
        id: col
        required property int index
        spacing: root.cell * 0.28

        readonly property bool on: !root.blackout && root.lit > index

        Lamp { on: col.on; size: root.cell; litColor: root.onColor; darkColor: root.offColor }
        Lamp { on: col.on; size: root.cell; litColor: root.onColor; darkColor: root.offColor }
      }
    }
  }
}
