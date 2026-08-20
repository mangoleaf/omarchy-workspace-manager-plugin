import QtQuick
import Quickshell.Hyprland
import qs.Commons

// Click-to-capture hotkey box: click it, press the desired combination, and
// the binding is captured (Esc cancels). With stripSuper the stored value is
// SUPER-relative — press the keys without holding SUPER (workspace rows),
// since SUPER+numpad combos are already bound and would fire instead of
// being captured.
Rectangle {
  id: root

  property string value: ""

  // Set by whoever hosts this box, so capturing can suspend Hyprland's own
  // keybinds — otherwise an already-bound combination fires instead of
  // being captured.
  property var widget: null

  // Shown in front of the value but never stored. Workspace keys are held
  // SUPER-relative in the config, and reading "KP_Insert" gives no clue
  // what you actually press.
  property string displayPrefix: ""
  property bool stripSuper: false
  property bool capturing: false
  property color fg: Color.foreground
  property color dimColor: Qt.rgba(fg.r, fg.g, fg.b, 0.55)
  property color lineColor: Qt.rgba(fg.r, fg.g, fg.b, 0.18)

  signal captured(string keys)

  radius: 5
  color: capturing ? Qt.rgba(fg.r, fg.g, fg.b, 0.08) : "transparent"
  border.color: capturing ? fg : lineColor
  border.width: 1

  function keyName(event) {
    var k = event.key

    if (event.modifiers & Qt.KeypadModifier) {
      var pad = {}
      pad[Qt.Key_Insert] = "KP_Insert"; pad[Qt.Key_End] = "KP_End"; pad[Qt.Key_Down] = "KP_Down"
      pad[Qt.Key_PageDown] = "KP_Next"; pad[Qt.Key_Left] = "KP_Left"; pad[Qt.Key_Clear] = "KP_Begin"
      pad[Qt.Key_Right] = "KP_Right"; pad[Qt.Key_Home] = "KP_Home"; pad[Qt.Key_Up] = "KP_Up"
      pad[Qt.Key_PageUp] = "KP_Prior"; pad[Qt.Key_Minus] = "KP_Subtract"; pad[Qt.Key_Plus] = "KP_Add"
      pad[Qt.Key_Enter] = "KP_Enter"; pad[Qt.Key_Slash] = "KP_Divide"; pad[Qt.Key_Asterisk] = "KP_Multiply"
      pad[Qt.Key_Delete] = "KP_Delete"; pad[Qt.Key_Period] = "KP_Delete"
      if (pad[k]) return pad[k]

      // With numlock on, a numpad digit arrives as Key_0..Key_9 and the
      // obvious name for it is KP_3. Hyprland will accept that name and then
      // never match it: it resolves a binding against the keymap's base
      // level, where that key is KP_Next. So a digit is reported under the
      // name the key carries with numlock off, which is what binds.
      var numlockOff = ["KP_Insert", "KP_End", "KP_Down", "KP_Next", "KP_Left",
                        "KP_Begin", "KP_Right", "KP_Home", "KP_Up", "KP_Prior"]
      if (k >= Qt.Key_0 && k <= Qt.Key_9) return numlockOff[k - Qt.Key_0]
    }

    if (k >= Qt.Key_F1 && k <= Qt.Key_F35) return "F" + (k - Qt.Key_F1 + 1)
    if (k >= Qt.Key_A && k <= Qt.Key_Z) return String.fromCharCode(65 + k - Qt.Key_A)
    if (k >= Qt.Key_0 && k <= Qt.Key_9) return String(k - Qt.Key_0)

    var named = {}
    named[Qt.Key_Space] = "SPACE"; named[Qt.Key_Return] = "RETURN"; named[Qt.Key_Tab] = "TAB"
    named[Qt.Key_Backspace] = "BACKSPACE"; named[Qt.Key_Delete] = "DELETE"; named[Qt.Key_Insert] = "INSERT"
    named[Qt.Key_Home] = "Home"; named[Qt.Key_End] = "End"; named[Qt.Key_PageUp] = "Prior"; named[Qt.Key_PageDown] = "Next"
    named[Qt.Key_Left] = "LEFT"; named[Qt.Key_Right] = "RIGHT"; named[Qt.Key_Up] = "UP"; named[Qt.Key_Down] = "DOWN"
    named[Qt.Key_Comma] = "COMMA"; named[Qt.Key_Period] = "PERIOD"; named[Qt.Key_Slash] = "SLASH"
    named[Qt.Key_Minus] = "MINUS"; named[Qt.Key_Equal] = "EQUAL"; named[Qt.Key_Semicolon] = "SEMICOLON"
    named[Qt.Key_Apostrophe] = "APOSTROPHE"; named[Qt.Key_BracketLeft] = "BRACKETLEFT"
    named[Qt.Key_BracketRight] = "BRACKETRIGHT"; named[Qt.Key_Backslash] = "BACKSLASH"
    named[Qt.Key_QuoteLeft] = "grave"; named[Qt.Key_Print] = "PRINT"
    if (named[k]) return named[k]

    return ""
  }

  Text {
    anchors.fill: parent
    anchors.leftMargin: 8
    anchors.rightMargin: 8
    verticalAlignment: Text.AlignVCenter
    text: root.capturing ? "press keys… (Esc cancels)"
        : (root.value === "" ? "click to set" : root.displayPrefix + root.value)
    color: root.capturing || root.value === "" ? root.dimColor : root.fg
    font.family: Style.font.family
    font.pixelSize: Style.font.body - 1
    elide: Text.ElideRight
  }

  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: {
      root.capturing = true
      root.forceActiveFocus()
    }
  }

  // Keys are handled on the component itself rather than a nested Item: a
  // ListView delegate is its own focus scope, and focus forced onto a child
  // inside one does not reliably receive key events.
  focus: false
  activeFocusOnTab: true
  onActiveFocusChanged: if (!activeFocus) root.capturing = false

  onCapturingChanged: {
    if (!root.widget) return
    if (root.capturing) { root.widget.beginKeyCapture(); captureTimeout.restart() }
    else { root.widget.endKeyCapture(); captureTimeout.stop() }
  }

  // Never leave the bindings suspended: if a capture is armed and forgotten,
  // it gives up on its own rather than stranding the keyboard.
  Timer {
    id: captureTimeout
    interval: 15000
    onTriggered: root.capturing = false
  }

  Keys.onPressed: function(event) {
    if (!root.capturing) return
    event.accepted = true

    if (event.key === Qt.Key_Escape) {
      root.capturing = false
      return
    }

    var name = root.keyName(event)
    if (name === "") return  // modifier or unmapped key: keep waiting

    var mods = []
    if ((event.modifiers & Qt.MetaModifier) && !root.stripSuper) mods.push("SUPER")
    if (event.modifiers & Qt.ShiftModifier) mods.push("SHIFT")
    if (event.modifiers & Qt.ControlModifier) mods.push("CTRL")
    if (event.modifiers & Qt.AltModifier) mods.push("ALT")
    mods.push(name)

    root.capturing = false
    root.captured(mods.join(" + "))
  }
}
