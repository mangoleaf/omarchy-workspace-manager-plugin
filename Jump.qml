import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import "TreeModel.js" as TreeModel

// Fuzzy workspace/window finder: a monitor → workspace → window tree, filtered
// as you type (every space-separated term must fuzzy-match somewhere). Enter
// or click jumps to the selected workspace or window; Up/Down navigate; Esc
// clears the filter, then closes. Opens on the focused monitor.
PanelWindow {
  id: win

  property var widget: null
  property string query: ""
  property int selected: 0

  visible: false
  anchors { top: true; bottom: true; left: true; right: true }
  color: "transparent"
  WlrLayershell.namespace: "omarchy-workspace-manager-jump"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

  readonly property color fg: Color.foreground
  readonly property color dim: Qt.rgba(fg.r, fg.g, fg.b, 0.55)
  readonly property color line: Qt.rgba(fg.r, fg.g, fg.b, 0.18)

  // App icon for a window class, via its desktop entry
  property var iconCache: ({})

  function classIcon(cls) {
    if (cls === "") return ""
    if (win.iconCache[cls] !== undefined) return win.iconCache[cls]
    var out = ""
    var entry = DesktopEntries.heuristicLookup(cls)
    if (entry && entry.icon) {
      var v = String(entry.icon)
      if (v.indexOf("file://") === 0 || v.indexOf("image://") === 0) out = v
      else if (v.charAt(0) === "/") out = "file://" + v
      else out = Quickshell.iconPath(v, true)
    }
    win.iconCache[cls] = out
    return out
  }

  // SUPER-relative hotkey per workspace id, from the shared workspaces.conf
  // the bar widget already parses
  function hotkeyFor(workspaceId) {
    var defs = widget ? widget.rows : []
    for (var i = 0; i < defs.length; i++)
      if (defs[i].id === workspaceId && defs[i].key !== "") return "SUPER + " + defs[i].key
    return ""
  }

  // Gated on visible so a closed finder costs nothing per Hyprland event.
  readonly property var monitorsData: {
    if (!win.visible) return []
    var out = []
    var values = Hyprland.monitors.values
    var focused = Hyprland.focusedMonitor
    for (var i = 0; i < values.length; i++)
      out.push({ name: String(values[i].name || ""), focused: !!focused && focused.name === values[i].name })
    return out
  }

  readonly property var workspacesData: {
    if (!win.visible) return []
    var out = []
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      var ws = values[i]
      out.push({
        id: ws.id,
        name: String(ws.name || ""),
        monitorName: ws.monitor ? String(ws.monitor.name || "") : "",
        active: ws.active === true,
        urgent: ws.urgent === true
      })
    }
    return out
  }

  readonly property var windowsData: {
    if (!win.visible) return []
    var out = []
    var values = Hyprland.toplevels.values
    var active = Hyprland.activeToplevel
    for (var i = 0; i < values.length; i++) {
      var t = values[i]
      var ipc = t.lastIpcObject || ({})
      out.push({
        address: String(t.address || ""),
        title: String(t.title || ""),
        appClass: String(ipc["class"] || ipc.initialClass || ""),
        workspaceId: t.workspace ? t.workspace.id : 0,
        monitorName: t.monitor ? String(t.monitor.name || "") : "",
        active: !!active && active.address === t.address,
        urgent: t.urgent === true,
        floating: ipc.floating === true,
        fullscreen: !!ipc.fullscreen,
        at: ipc.at,
        size: ipc.size,
        icon: win.classIcon(String(ipc["class"] || ipc.initialClass || ""))
      })
    }
    return out
  }

  readonly property var tree: TreeModel.build(win.monitorsData, win.workspacesData, win.windowsData)

  // Empty query: browse the full tree in stable order. With a query: a flat
  // list ranked best-match-first — substring hits beat subsequence hits,
  // earlier and tighter matches rank higher, workspaces get a small boost so
  // typing a workspace's name lands on the workspace, not one of its windows.
  readonly property var rows: win.query === ""
    ? TreeModel.flatten(win.tree, {})
    : win.rankedRows()

  // Per space-separated term: substring score 1000-position, else subsequence
  // score 400-spread; any term failing kills the candidate.
  function scoreText(text, q) {
    var hay = String(text || "").toLowerCase()
    var terms = String(q).toLowerCase().split(/\s+/)
    var total = 0
    for (var i = 0; i < terms.length; i++) {
      var t = terms[i]
      if (!t) continue
      var at = hay.indexOf(t)
      if (at !== -1) { total += 1000 - Math.min(at, 500); continue }
      var pos = -1
      var ok = true
      for (var c = 0; c < t.length; c++) {
        pos = hay.indexOf(t.charAt(c), pos + 1)
        if (pos === -1) { ok = false; break }
      }
      if (!ok) return -1
      total += 400 - Math.min(pos, 390)
    }
    return total
  }

  function rankedRows() {
    var out = []
    var wsLabelById = {}

    for (var s = 0; s < win.workspacesData.length; s++) {
      var ws = win.workspacesData[s]
      var label = ws.name !== "" ? ws.name : String(ws.id)
      wsLabelById[ws.id] = label
      var sc = win.scoreText(label, win.query)
      if (sc >= 0) out.push({
        kind: "workspace", key: "ws:" + ws.id, depth: 0,
        label: label, meta: ws.monitorName,
        workspaceId: ws.id, monitorName: ws.monitorName,
        active: ws.active, sc: sc + 50
      })
    }

    for (var w = 0; w < win.windowsData.length; w++) {
      var t = win.windowsData[w]
      var sc2 = win.scoreText(t.title + " " + t.appClass, win.query)
      if (sc2 >= 0) out.push({
        kind: "window", key: "win:" + t.address, depth: 0,
        label: t.title || t.appClass || "(untitled)",
        meta: (wsLabelById[t.workspaceId] || "") + " · " + t.appClass,
        address: TreeModel.normalizeAddress(t.address),
        workspaceId: t.workspaceId, monitorName: t.monitorName,
        active: t.active, icon: t.icon || "", sc: sc2
      })
    }

    out.sort(function(a, b) { return b.sc - a.sc })
    return out
  }

  onQueryChanged: selected = win.query === "" ? TreeModel.indexOfActiveWindow(win.rows) : 0
  onSelectedChanged: list.positionViewAtIndex(Math.min(selected, rows.length - 1), ListView.Contain)

  function openNow() {
    Hyprland.refreshMonitors()
    Hyprland.refreshWorkspaces()
    Hyprland.refreshToplevels()

    var focusedName = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""
    var screens = Quickshell.screens
    for (var i = 0; i < screens.length; i++)
      if (screens[i].name === focusedName) win.screen = screens[i]

    input.text = ""
    win.query = ""
    win.visible = true
    Qt.callLater(function() {
      if (!win.visible) return
      win.selected = win.pickIndex()
      input.forceActiveFocus()
    })
  }

  function close() { win.visible = false }

  function jump() {
    if (win.rows.length === 0) return
    var row = win.rows[Math.min(win.selected, win.rows.length - 1)]
    var commands = TreeModel.focusCommands(row)
    for (var i = 0; i < commands.length; i++) Hyprland.dispatch(commands[i])
    // Warp the cursor to the center of the now-focused window, otherwise
    // hover focus snaps right back to whatever the mouse is sitting on.
    // Done via hyprctl AFTER the focus lands, so the geometry is the target
    // window's real position (absolute coordinates = correct display too).
    if (row.kind === "window") warpProc.running = true
    close()
  }

  Process {
    id: warpProc
    command: ["sh", "-c",
      "sleep 0.15; set -- $(hyprctl activewindow -j | jq -r '.at[0], .at[1], .size[0], .size[1]' 2>/dev/null); " +
      "[ $# -eq 4 ] && hyprctl dispatch \"hl.dsp.cursor.move({ x = $(($1 + $3 / 2)), y = $(($2 + $4 / 2)) })\""]
  }

  // Scrim
  Rectangle {
    anchors.fill: parent
    color: Qt.rgba(0, 0, 0, 0.5)
    MouseArea { anchors.fill: parent; onClicked: win.close() }
  }

  Rectangle {
    id: card
    anchors.horizontalCenter: parent.horizontalCenter
    y: Math.round(parent.height * 0.14)
    width: 640
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

      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 32
        radius: 6
        color: "transparent"
        border.color: win.fg
        border.width: 1

        TextInput {
          id: input
          anchors.fill: parent
          anchors.leftMargin: 10
          anchors.rightMargin: 10
          verticalAlignment: TextInput.AlignVCenter
          color: win.fg
          font.family: Style.font.family
          font.pixelSize: Style.font.body + 1
          clip: true
          onTextChanged: win.query = text
          Keys.onEscapePressed: win.close()
          Keys.onReturnPressed: win.jump()
          Keys.onEnterPressed: win.jump()
          Keys.onDownPressed: if (win.selected < win.rows.length - 1) win.selected++
          Keys.onUpPressed: if (win.selected > 0) win.selected--
        }

        Text {
          anchors.fill: input
          verticalAlignment: Text.AlignVCenter
          text: "Jump to workspace or window…"
          color: win.dim
          font.family: Style.font.family
          font.pixelSize: Style.font.body + 1
          visible: input.text === ""
        }
      }

      ListView {
        id: list
        Layout.fillWidth: true
        Layout.preferredHeight: Math.min(contentHeight, Math.round(win.height * 0.6))
        clip: true
        spacing: 0
        model: win.rows

        delegate: Rectangle {
          required property var modelData
          required property int index

          width: list.width
          height: 28
          radius: 5
          color: index === win.selected ? Qt.rgba(win.fg.r, win.fg.g, win.fg.b, 0.12) : "transparent"

          RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10 + modelData.depth * 18
            anchors.rightMargin: 10
            spacing: 8

            Image {
              visible: modelData.kind === "window" && (modelData.icon || "") !== ""
              Layout.preferredWidth: 16
              Layout.preferredHeight: 16
              fillMode: Image.PreserveAspectFit
              sourceSize.width: 32
              sourceSize.height: 32
              source: modelData.icon || ""
              asynchronous: true
            }

            Text {
              text: modelData.label
              color: modelData.active ? win.fg : (index === win.selected ? win.fg : win.dim)
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              font.bold: modelData.kind !== "window" || modelData.active === true
              elide: Text.ElideRight
              Layout.fillWidth: false
              Layout.maximumWidth: parent.width * 0.7
            }

            Rectangle {
              visible: modelData.kind === "workspace" && win.hotkeyFor(modelData.workspaceId) !== ""
              Layout.preferredWidth: hotkeyText.implicitWidth + 14
              Layout.preferredHeight: 17
              radius: 8
              color: "transparent"
              border.color: win.line
              border.width: 1

              Text {
                id: hotkeyText
                anchors.centerIn: parent
                text: modelData.kind === "workspace" ? win.hotkeyFor(modelData.workspaceId) : ""
                color: win.dim
                font.family: Style.font.family
                font.pixelSize: Style.font.body - 3
              }
            }

            Item { Layout.fillWidth: true }

            Text {
              text: modelData.meta || ""
              color: win.dim
              font.family: Style.font.family
              font.pixelSize: Style.font.body - 2
            }
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: { win.selected = index; win.jump() }
          }
        }
      }

      Text {
        text: "Nothing matches"
        visible: win.rows.length === 0
        color: win.dim
        font.family: Style.font.family
        font.pixelSize: Style.font.body
      }
    }
  }
}
