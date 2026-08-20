import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons

// A connector name like "DP-2" says nothing about which panel on the desk it
// is, and two identical monitors report identical makes and models — so the
// only reliable answer is to put the name on the glass and let the user look
// up. Every screen is labelled at once, the way display settings do it.
Item {
  id: root

  // Long enough to look up from the keyboard and across a desk, short enough
  // that it never feels like something to dismiss.
  property int seconds: 3

  property bool showing: false

  function flash() {
    root.showing = true
    hideTimer.restart()
  }

  Timer {
    id: hideTimer
    interval: root.seconds * 1000
    onTriggered: root.showing = false
  }

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: badge
      required property var modelData

      screen: modelData
      visible: root.showing
      color: "transparent"
      exclusionMode: ExclusionMode.Ignore
      anchors { top: true; bottom: true; left: true; right: true }
      WlrLayershell.namespace: "omarchy-workspace-manager-identify"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

      // Nothing here takes input — the editor underneath stays usable while
      // the labels are up.
      mask: Region {}

      readonly property string who: {
        var parts = []
        if (String(modelData.manufacturer || "") !== "") parts.push(String(modelData.manufacturer))
        if (String(modelData.model || "") !== "") parts.push(String(modelData.model))
        return parts.join(" ")
      }

      Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        // High on the screen, clear of the editor card below it.
        y: Math.round(parent.height * 0.08)
        width: stack.implicitWidth + 72
        height: stack.implicitHeight + 44
        radius: 12
        color: Color.background
        border.color: Color.accent
        border.width: 2

        Column {
          id: stack
          anchors.centerIn: parent
          spacing: 4

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: String(badge.modelData.name)
            color: Color.accent
            font.family: Style.font.family
            font.pixelSize: 72
            font.bold: true
          }

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: badge.modelData.width + "×" + badge.modelData.height
              + (badge.who === "" ? "" : "  ·  " + badge.who)
            color: Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }
        }
      }
    }
  }
}
