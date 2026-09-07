import QtQuick
import qs.Commons
import qs.Ui

// Bar pill: a checkered flag plus the short countdown to the next F1 race.
// All data + rendering of the popup lives in Panel.qml; this widget is just
// the bar-slot button and the popout-identity shim the bar expects.
BarWidget {
  id: root
  moduleName: "com.leafbox.f1"

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  function refresh() {
    if (panelLoader.item && panelLoader.item.refresh) panelLoader.item.refresh()
  }

  function togglePanel() {
    if (panelLoader.item && panelLoader.item.toggle) panelLoader.item.toggle()
  }

  // Shape contract for shell.summon/hide/toggle routing: the bar identifies a
  // panel by the widget mounted in its slot (this file), so open/close/opened
  // have to live here and forward to the nested Panel.
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() {
    if (panelLoader.item && panelLoader.item.openFromHotkey) panelLoader.item.openFromHotkey()
  }

  function close() {
    if (panelLoader.item && panelLoader.item.close) panelLoader.item.close()
  }

  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: panelLoader.item ? panelLoader.item.label : ""
    // The pill carries a countdown, not a single glyph, so the icon slot's
    // fixed width is a lie the bar believes: the text paints past it and the
    // next widget is laid out over the overflow. Claim the width the string
    // actually paints, padded the way the shell pads an icon inside its slot,
    // so the pill keeps the bar's rhythm instead of crowding its neighbours.
    // The floor keeps the bare flag glyph — the fallback, and the live-session
    // label — exactly the size of every other status icon.
    readonly property real slotPad: Math.max(0, (Style.bar.statusSlot - Style.bar.iconCanvas) / 2)
    slotSize: Math.max(Style.bar.statusSlot, button.glyphPaintedWidth + button.slotPad * 2)
    tooltipText: panelLoader.item ? panelLoader.item.tooltip : "Formula 1"
    // During a live session tint the flag with the theme's attention color
    // instead of widening the pill with LIVE text.
    foreground: (panelLoader.item && panelLoader.item.liveActive === true)
      ? Color.bar.active
      : (root.bar ? root.bar.barForeground : Color.foreground)

    onPressed: function(b) {
      if (!root.bar) return
      if (b === Qt.MiddleButton) root.refresh()
      else root.togglePanel()
    }
  }
}
