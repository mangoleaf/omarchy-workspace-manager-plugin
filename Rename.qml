import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons

// Rename the active workspace. Names are "base: suffix" — the base is the
// workspace's fixed identity (its number or letter) and is never editable
// here; only the suffix is, and clearing it leaves the base alone.
PanelWindow {
  id: win

  property var widget: null
  property int workspaceId: -1
  property string base: ""

  visible: false
  anchors { top: true; bottom: true; left: true; right: true }
  color: "transparent"
  WlrLayershell.namespace: "omarchy-workspace-manager-rename"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

  readonly property color fg: Color.foreground
  readonly property color dim: Qt.rgba(fg.r, fg.g, fg.b, 0.55)
  readonly property color line: Qt.rgba(fg.r, fg.g, fg.b, 0.18)

  function labelFor(id) {
    var rows = widget ? widget.rows : []
    for (var i = 0; i < rows.length; i++) if (rows[i].id === id) return rows[i].label
    return ""
  }

  function openNow() {
    var active = Hyprland.focusedWorkspace
    if (!active) return

    win.workspaceId = active.id
    var label = win.labelFor(active.id)
    if (label === "") label = String(active.name || active.id)

    // Split on the first ": " — everything before it is the base.
    var at = label.indexOf(": ")
    win.base = at === -1 ? label : label.substring(0, at)
    input.text = at === -1 ? "" : label.substring(at + 2)

    var screens = Quickshell.screens
    var focusedName = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""
    for (var s = 0; s < screens.length; s++)
      if (screens[s].name === focusedName) win.screen = screens[s]
    win.openedOn = focusedName

    win.visible = true
    Qt.callLater(function() {
      if (!win.visible) return
      input.forceActiveFocus()
      input.selectAll()
    })
  }

  function close() { win.visible = false }

  // A click on another monitor moves Hyprland's focus there but never reaches
  // this surface, which only covers the screen it opened on — so watch for the
  // focus leaving and dismiss, the same as clicking the scrim.
  property string openedOn: ""

  Connections {
    target: Hyprland
    function onFocusedMonitorChanged() {
      if (!win.visible || win.openedOn === "") return
      var now = Hyprland.focusedMonitor ? String(Hyprland.focusedMonitor.name || "") : ""
      if (now !== "" && now !== win.openedOn) win.close()
    }
  }


  function apply() {
    var suffix = input.text.trim()
    if (suffix.indexOf("|") !== -1) return  // reserved as the config separator

    var label = suffix === "" ? win.base : win.base + ": " + suffix
    if (widget) widget.writeLabel(win.workspaceId, label)
    close()
  }

  Rectangle {
    anchors.fill: parent
    color: Qt.rgba(0, 0, 0, 0.5)
    MouseArea { anchors.fill: parent; onClicked: win.close() }
  }

  Rectangle {
    anchors.horizontalCenter: parent.horizontalCenter
    y: Math.round(parent.height * 0.28)
    width: 420
    height: content.implicitHeight + 28
    radius: 10
    color: Color.background
    border.color: win.line
    border.width: 1

    MouseArea { anchors.fill: parent }

    ColumnLayout {
      id: content
      anchors.fill: parent
      anchors.margins: 14
      spacing: 10

      Text {
        text: "Rename workspace " + win.base
        color: win.fg
        font.family: Style.font.family
        font.pixelSize: Style.font.body + 1
        font.bold: true
      }

      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 32
        radius: 6
        color: "transparent"
        border.color: input.text.indexOf("|") !== -1 ? Color.urgent : win.fg
        border.width: 1

        TextInput {
          id: input
          anchors.fill: parent
          anchors.leftMargin: 10
          anchors.rightMargin: 10
          verticalAlignment: TextInput.AlignVCenter
          color: win.fg
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          clip: true
          selectByMouse: true
          Keys.onEscapePressed: win.close()
          Keys.onReturnPressed: win.apply()
          Keys.onEnterPressed: win.apply()
        }

        Text {
          anchors.fill: input
          verticalAlignment: Text.AlignVCenter
          text: "(blank leaves just “" + win.base + "”)"
          color: win.dim
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          visible: input.text === ""
        }
      }

      Text {
        text: input.text.indexOf("|") !== -1
          ? "“|” is not allowed — it separates fields in the config"
          : "Enter saves · Esc cancels"
        color: input.text.indexOf("|") !== -1 ? Color.urgent : win.dim
        font.family: Style.font.family
        font.pixelSize: Style.font.body - 2
      }
    }
  }
}
