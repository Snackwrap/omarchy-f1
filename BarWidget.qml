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

  // BarIconButton is a *fixed-width* slot sized for a single glyph, and the
  // glyph inside it is drawn centred with no clipping — so a pill carrying text
  // as well ("\uf11e 4d 21h") silently overhangs its neighbours on both sides.
  // Measure the actual string and widen the slot to match.
  TextMetrics {
    id: pillMetrics
    font.family: root.bar ? root.bar.fontFamily : Style.font.family
    font.pixelSize: Style.bar.iconFont
    text: button.text
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: panelLoader.item ? panelLoader.item.label : ""
    slotSize: Math.max(Style.bar.statusSlot,
                       Math.ceil(pillMetrics.width) + Style.space(9))
    // The glyph canvas has to grow with the slot too, or the text is centred
    // inside a 16px box in the middle of a much wider button.
    opticalSize: slotSize
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
