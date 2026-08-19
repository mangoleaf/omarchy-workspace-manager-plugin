import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.Commons
import qs.Ui

// Named workspaces, split per monitor. Definitions live in
// ~/.config/hypr/workspaces.conf (id|key|monitor|label|apps), shared with
// monitors.lua, bindings.lua, and rename-workspace.sh.
// Right-click any workspace to open the editor; the jump hotkey opens the
// fuzzy workspace/window finder.
BarWidget {
  id: root
  moduleName: "mangoleaf.workspaces"

  property var rows: []
  property string renameKey: ""
  property string jumpKey: ""
  property string editorKey: ""
  readonly property string confPath: Quickshell.env("HOME") + "/.config/hypr/workspaces.conf"

  readonly property string screenName: {
    var win = QsWindow.window
    return win && win.screen ? win.screen.name : ""
  }

  function loadConf(t) {
    var out = []
    var settings = { rename: "", jump: "", editor: "" }
    var lines = (t || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var p = lines[i].split("|")
      if (p.length >= 4 && /^\d+$/.test(p[0]))
        out.push({ id: parseInt(p[0]), key: p[1], monitor: p[2], label: p[3], apps: p.length >= 5 ? p[4] : "" })
      else if (p.length >= 2 && settings[p[0]] !== undefined)
        settings[p[0]] = p.slice(1).join("|")
    }
    root.rows = out
    root.renameKey = settings.rename
    root.jumpKey = settings.jump
    root.editorKey = settings.editor
  }

  function saveConf(text) {
    confFile.setText(text)
    applyTimer.restart()
  }

  function workspaceIds() {
    var ids = []
    for (var i = 0; i < root.rows.length; i++)
      if (root.rows[i].monitor === root.screenName) ids.push(root.rows[i].id)
    if (ids.length === 0)
      for (var j = 1; j <= 26; j++) ids.push(j)
    return ids
  }

  function workspaceById(id) {
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      if (values[i].id === id) return values[i]
    }

    return null
  }

  function focusWorkspace(id) {
    if (!root.bar) return
    root.bar.run("hyprctl dispatch " + Util.shellQuote("hl.dsp.focus({ workspace = \"" + id + "\" })"))
  }

  function openEditor() {
    if (editorLoader.active && editorLoader.item) editorLoader.item.openNow()
    else editorLoader.active = true
  }

  // shell.summon/hide/toggle contract (Bar.findPanelWidget) — routes the
  // "jump" hotkey (omarchy-shell shell toggle mangoleaf.workspaces) to the
  // fuzzy finder.
  readonly property bool opened: jumpLoader.item ? jumpLoader.item.visible === true : false

  function open() {
    if (jumpLoader.active && jumpLoader.item) jumpLoader.item.openNow()
    else jumpLoader.active = true
  }

  function close() {
    if (jumpLoader.item) jumpLoader.item.close()
  }

  // The editor hotkey routes here. A bar widget exists per monitor and IPC
  // reaches exactly one of them, which is what a single modal editor wants.
  IpcHandler {
    target: "mangoleaf.workspaces"

    function editor(): void {
      root.openEditor()
    }
  }

  FileView {
    id: confFile
    path: root.confPath
    watchChanges: true
    printErrors: false
    onLoaded: root.loadConf(text())
    onFileChanged: { reload(); root.loadConf(text()) }
    onLoadFailed: root.loadConf("")
  }

  // Let the setText write land before hyprctl reads the file
  Timer {
    id: applyTimer
    interval: 400
    onTriggered: if (root.bar) root.bar.run(Quickshell.env("HOME") + "/sync/scripts/rename-workspace.sh --apply")
  }

  Loader {
    id: editorLoader
    active: false
    source: Qt.resolvedUrl("Editor.qml")
    onLoaded: {
      item.widget = root
      item.openNow()
    }
  }

  Loader {
    id: jumpLoader
    active: false
    source: Qt.resolvedUrl("Jump.qml")
    onLoaded: {
      item.widget = root
      item.openNow()
    }
  }

  readonly property real trailingGap: root.vertical ? 0 : Style.spaceReal(1.5)

  implicitWidth: grid.implicitWidth + trailingGap
  implicitHeight: grid.implicitHeight

  GridLayout {
    id: grid
    anchors.fill: parent
    anchors.rightMargin: root.trailingGap
    columns: root.vertical ? 1 : root.workspaceIds().length
    columnSpacing: root.vertical ? 0 : Style.space(1)
    rowSpacing: root.vertical ? Style.space(2) : 0

    Repeater {
      model: root.workspaceIds()

      WidgetButton {
        required property int modelData

        readonly property var workspace: root.workspaceById(modelData)
        readonly property bool occupied: workspace !== null && workspace.toplevels.values.length > 0
        readonly property bool focused: Hyprland.focusedWorkspace !== null && Hyprland.focusedWorkspace.id === modelData

        bar: root.bar
        text: workspace !== null && workspace.name !== "" ? workspace.name : String(modelData)
        active: focused
        dimmed: !occupied && !focused
        horizontalMargin: 4
        verticalPadding: 6
        fixedHeight: root.barSize
        onPressed: function(button) {
          if (button === Qt.RightButton) root.openEditor()
          else root.focusWorkspace(modelData)
        }
      }
    }
  }
}
