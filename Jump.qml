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

  readonly property int rLarge: widget ? widget.roundLarge : 10
  readonly property int rSmall: widget ? widget.roundSmall : 5

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

  function workspaceLabel(ws) {
    if (widget) {
      var row = widget.rowById(ws.id)
      if (row) {
        var composed = widget.composeLabel(row.prefix, row.label)
        if (composed !== "") return composed
      }
      return widget.compactLabel(String(ws.name || ""))
    }
    return String(ws.name || "")
  }

  readonly property var workspacesData: {
    if (!win.visible) return []
    var out = []
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      var ws = values[i]
      out.push({
        id: ws.id,
        // Compose from our own fields rather than Hyprland's live name: the
        // live name only catches up on the next reload, so a spacing or
        // number change would not show here until then.
        name: win.workspaceLabel(ws),
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
        label: label, meta: "",
        workspaceId: ws.id, monitorName: ws.monitorName,
        active: ws.active, sc: sc
      })
    }

    for (var w = 0; w < win.windowsData.length; w++) {
      var t = win.windowsData[w]
      var sc2 = win.scoreText(t.title + " " + t.appClass, win.query)
      if (sc2 >= 0) out.push({
        kind: "window", key: "win:" + t.address, depth: 0,
        label: t.title === "" ? (t.appClass || "(untitled)")
                              : TreeModel.stripAppSuffix(t.title, t.appClass),
        // Flat results lose the tree, so a window says which workspace it is
        // on — the one thing the row no longer shows by its position.
        meta: wsLabelById[t.workspaceId] || "",
        address: TreeModel.normalizeAddress(t.address),
        workspaceId: t.workspaceId, monitorName: t.monitorName,
        active: t.active, icon: t.icon || "", sc: sc2
      })
    }

    // Windows win a tie. A workspace called Signal and the Signal window
    // score the same on "signal", and the window is the thing you were
    // actually looking for — the workspace is reachable by its own hotkey.
    out.sort(function(a, b) {
      if (b.sc !== a.sc) return b.sc - a.sc
      if (a.kind !== b.kind) return a.kind === "window" ? -1 : 1
      return 0
    })
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
    win.openedOn = focusedName

    input.text = ""
    win.query = ""
    win.visible = true
    win.grabInput()
  }

  // The surface is mapped asynchronously, so a single focus request can land
  // before there is anything to focus and leave the arrows dead until the
  // user clicks. Re-assert it whenever the window becomes visible.
  onVisibleChanged: if (visible) win.grabInput()

  // Where to land when the list appears: on the focused window while browsing
  // the tree, so Enter is a no-op and the arrows start somewhere recognised;
  // on the best match once something has been typed.
  function pickIndex() {
    return win.query === "" ? TreeModel.indexOfActiveWindow(win.rows) : 0
  }

  function grabInput() {
    Qt.callLater(function() {
      if (!win.visible) return
      win.selected = win.pickIndex()
      input.forceActiveFocus()
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


  property var pendingCommands: []
  property bool pendingWarp: false

  function jump() {
    if (win.rows.length === 0) return
    var row = win.rows[Math.min(win.selected, win.rows.length - 1)]
    win.pendingCommands = TreeModel.focusCommands(row)
    win.pendingWarp = row.kind === "window"
    // Close BEFORE focusing. This surface holds exclusive keyboard focus, and
    // the compositor hands focus back to whatever held it previously when the
    // surface goes away — which would land after our dispatch and undo it.
    close()
    dispatchTimer.restart()
  }

  // One command per tick, not all at once. Each step has to land before the
  // next makes sense: focusing the window while its workspace is still
  // switching is the same silent no-op as focusing across workspaces, so
  // firing them back to back leaves you on the right workspace with the
  // wrong window focused.
  // ponytail: 40ms is a step gap that holds on this machine; if a slower one
  // drops the last step, this is the number to raise.
  Timer {
    id: dispatchTimer
    interval: 40
    repeat: true
    onTriggered: {
      if (win.pendingCommands.length > 0) {
        var next = win.pendingCommands[0]
        win.pendingCommands = win.pendingCommands.slice(1)
        Hyprland.dispatch(next)
        return
      }

      dispatchTimer.stop()
      // Warp the cursor into the focused window, or hover focus snaps back to
      // whatever the pointer is still sitting on. Measured after the fact via
      // hyprctl, so it reads the window that actually ended up focused.
      if (win.pendingWarp) warpProc.running = true
      win.pendingWarp = false
    }
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
    radius: rLarge
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
        radius: rSmall
        color: "transparent"
        border.color: win.line
        border.width: 1

        TextInput {
          id: input
          // Own the window's focus so typing and the arrow keys work the
          // moment the finder appears, with no click first.
          focus: true
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
          id: rowItem
          required property var modelData
          required property int index

          readonly property bool isWindow: modelData.kind === "window"
          readonly property bool chosen: index === win.selected
          readonly property string hotkey: isWindow ? "" : win.hotkeyFor(modelData.workspaceId)

          width: list.width
          height: 28
          radius: rSmall
          color: chosen ? Qt.rgba(win.fg.r, win.fg.g, win.fg.b, 0.10) : "transparent"

          // A bar on the selected row rather than a brighter fill: the list is
          // mostly dim text, and a fill strong enough to read as "here" washes
          // the row's own text out.
          Rectangle {
            visible: parent.chosen
            width: 2
            radius: 1
            color: Color.accent
            anchors { left: parent.left; top: parent.top; bottom: parent.bottom
                      topMargin: 4; bottomMargin: 4 }
          }

          // One continuous rule under a workspace's own windows: which rows
          // belong to which workspace, without a second indent level or a
          // header row to skip past.
          Rectangle {
            // Only in the tree. Flat results have no parent to point at, and
            // the rule would just be a tick beside every icon.
            visible: rowItem.isWindow && modelData.depth > 0
            x: 19
            width: 1
            // Strong enough to survive the selected row's own highlight,
            // which the rule otherwise disappears into for one row.
            color: win.line
            anchors { top: parent.top; bottom: parent.bottom }
          }

          RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12 + modelData.depth * 16
            anchors.rightMargin: 12
            spacing: 8

            // Kept even when the icon is missing, so a window whose class has
            // no desktop entry does not hang its title out to the left of
            // every other one.
            Item {
              visible: rowItem.isWindow
              Layout.preferredWidth: 16
              Layout.preferredHeight: 16

              Image {
                anchors.fill: parent
                visible: source != ""
                fillMode: Image.PreserveAspectFit
                sourceSize.width: 32
                sourceSize.height: 32
                source: modelData.icon || ""
                asynchronous: true
              }
            }

            Text {
              text: modelData.label
              color: modelData.active || chosen ? win.fg : win.dim
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              font.bold: !isWindow || modelData.active === true
              elide: Text.ElideRight
              Layout.fillWidth: true
            }

            // Fixed, right-aligned columns. These were sized to their contents
            // and so began at a different x on every row, which turned the
            // list into a staircase of pills — the columns are the point, not
            // the chrome around each value.
            // Left-aligned: every hotkey opens with the same "SUPER + ", and
            // aligning that shared head is what makes the column scannable —
            // right alignment lines up the ends, which differ anyway.
            Text {
              visible: !isWindow
              text: hotkey
              color: win.dim
              font.family: Style.font.family
              font.pixelSize: Style.font.body - 2
              elide: Text.ElideRight
              Layout.preferredWidth: 172
            }

            Text {
              // Set false by the tree on every row but the first of a monitor;
              // the flat result list has no grouping, so there it always shows.
              visible: !isWindow && modelData.showMonitor !== false
              text: modelData.monitorName || ""
              color: win.dim
              font.family: Style.font.family
              font.pixelSize: Style.font.body - 2
              horizontalAlignment: Text.AlignRight
              Layout.preferredWidth: 66
            }

            // Holds the monitor column open on the rows that do not draw it,
            // so the count beyond it stays in line.
            Item {
              visible: !isWindow && modelData.showMonitor === false
              Layout.preferredWidth: 66
            }

            // Fixed rather than sharing the slack with the label: given the
            // choice the label took everything and elided this to nothing,
            // which is how a window stopped saying which workspace it is on.
            Text {
              text: modelData.meta || ""
              color: win.dim
              font.family: Style.font.family
              font.pixelSize: Style.font.body - 2
              horizontalAlignment: Text.AlignRight
              elide: Text.ElideRight
              Layout.preferredWidth: 104
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
