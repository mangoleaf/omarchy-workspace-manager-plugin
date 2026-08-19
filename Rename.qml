import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons

// Rename the active workspace. The number is its fixed identity and is not
// editable here — only the name is, and clearing it leaves the workspace
// showing its number alone.
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

  function openNow() {
    var active = Hyprland.focusedWorkspace
    if (!active) return

    // Number and name are stored apart, so take them as they are rather than
    // splitting a composed label — which the spacing setting can render
    // without a separator anyway.
    win.workspaceId = active.id
    var row = widget ? widget.rowById(active.id) : null
    win.base = row ? String(row.prefix === undefined ? "" : row.prefix) : String(active.id)
    input.text = row ? String(row.label === undefined ? "" : row.label) : ""

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
    var name = input.text.trim()
    if (name.indexOf("|") !== -1) return  // reserved as the config separator

    if (widget) widget.writeName(win.workspaceId, name)
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
