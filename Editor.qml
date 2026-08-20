import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons

// Workspace editor. Every change autosaves to workspaces.conf after a short
// debounce — there is no save button, Esc just closes. An invalid edit (blank
// name, "|" in a field) shows an error and is held back until it is valid.
PanelWindow {
  id: win

  property var widget: null
  property var rows: []
  property int revision: 0
  property string errorText: ""
  property string renameKey: ""
  property string jumpKey: ""
  property string editorKey: ""
  property bool centerBar: false
  property bool centerBarLoaded: false
  property string centerMoved: ""
  property string tab: "workspaces"
  property bool showHelp: false
  property int iconCount: 3
  property string barStyle: "plain"
  property bool countFromZero: false
  property bool compactNames: false
  property bool showNumbers: true
  property string delimiter: ":"
  property string lastAppliedPins: ""
  property string colorActive: ""
  property string colorUnfocused: ""
  property string colorOccupied: ""
  property string colorEmpty: ""

  readonly property var barStyles: ["plain", "pill", "underline"]

  readonly property var colorFields: [
    { key: "coloractive", label: "Active" },
    { key: "colorunfocused", label: "Active elsewhere" },
    { key: "coloroccupied", label: "Has windows" },
    { key: "colorempty", label: "Empty" }
  ]

  function colorValue(key) {
    if (key === "coloractive") return win.colorActive
    if (key === "colorunfocused") return win.colorUnfocused
    if (key === "coloroccupied") return win.colorOccupied
    return win.colorEmpty
  }

  function setColorValue(key, value) {
    if (key === "coloractive") win.colorActive = value
    else if (key === "colorunfocused") win.colorUnfocused = value
    else if (key === "coloroccupied") win.colorOccupied = value
    else win.colorEmpty = value
    win.autosave()
  }

  // Blank is allowed and means "follow the theme"; anything else has to be a
  // hex colour, or the bar would silently fall back to black.
  function colorValid(v) {
    return v === "" || /^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/.test(v)
  }

  // What the bar would actually draw, so the swatch shows the theme default
  // rather than nothing while the field is blank.
  function colorPreview(key) {
    var v = win.colorValue(key)
    if (v !== "" && win.colorValid(v)) return v
    if (key === "coloractive") return Color.urgent
    if (key === "colorunfocused") return widget ? widget.defaultUnfocusedColor : "#ff9e3f"
    return Color.foreground
  }

  // Every change writes itself. The debounce keeps a burst of typing to one
  // file write, which the widget then turns into one hyprctl reload.
  Timer {
    id: autosaveTimer
    interval: 500
    onTriggered: win.flush()
  }

  function autosave() {
    autosaveTimer.restart()
  }

  // A captured combination that Hyprland already uses. Not fatal — ours
  // unbinds the old one for the three global hotkeys — but silently taking
  // a key away from something else is worse than saying so.
  property string conflictNote: ""

  // A clash warning describes the current configuration and stays until it
  // stops being true. Passing remarks — an import count — expire.
  property bool noteExpires: true
  onConflictNoteChanged: if (conflictNote !== "" && noteExpires) noteTimeout.restart()

  Timer {
    id: noteTimeout
    interval: 6000
    onTriggered: win.conflictNote = ""
  }
  // Which combinations currently in use are taken from something else, as
  // combination -> what it displaced. Derived by scanning, not remembered
  // from a capture: a clash is a state of the configuration, so it has to
  // survive closing and reopening the editor.
  property var conflicts: ({})

  function conflictFor(combo) {
    return combo === "" ? "" : (win.conflicts[combo] || "")
  }

  function rescanConflicts() {
    if (!widget) return

    var combos = []
    if (win.renameKey !== "") combos.push(win.renameKey)
    if (win.jumpKey !== "") combos.push(win.jumpKey)
    if (win.editorKey !== "") combos.push(win.editorKey)
    for (var i = 0; i < win.rows.length; i++)
      if (win.rows[i].key !== "") combos.push("SUPER + " + win.rows[i].key)

    var out = {}
    var n = 0
    var firstCombo = ""
    for (var c = 0; c < combos.length; c++) {
      if (out[combos[c]] !== undefined) continue
      var hit = widget.bindingConflict(combos[c])
      if (hit === "") continue
      out[combos[c]] = hit
      if (n === 0) firstCombo = combos[c]
      n++
    }
    win.conflicts = out

    win.noteExpires = false
    win.conflictNote = n === 0 ? ""
      : n === 1 ? "!  \u201c" + firstCombo + "\u201d is already bound to " + out[firstCombo]
                  + " — this takes it over."
      : "!  " + n + " hotkeys take keys that are already bound elsewhere — hover a badge for detail."
  }

  // The bind list arrives asynchronously; rescan when it does.
  Connections {
    target: win.widget
    function onExistingBindsChanged() { win.rescanConflicts() }
  }

  // Tooltip for the warning badge, drawn at card level so the row's clipping
  // does not cut it off.
  property string tipText: ""
  property real tipX: 0
  property real tipY: 0

  // Generic tooltip, used by the overflow pill as well as the clash badge.
  function showTextTip(hovered, item, text) {
    if (!hovered || text === "") { win.tipText = ""; return }
    var p = card.mapFromItem(item, item.width + 8, item.height / 2)
    win.tipX = p.x
    win.tipY = p.y
    win.tipText = text
  }

  function showTip(hovered, item, combo) {
    var what = win.conflictFor(combo)
    if (!hovered || what === "") { win.tipText = ""; return }
    var p = card.mapFromItem(item, item.width + 8, item.height / 2)
    win.tipX = p.x
    win.tipY = p.y
    win.tipText = "takes it from " + what
  }

  function validate() {
    if (win.renameKey.indexOf("|") !== -1 || win.jumpKey.indexOf("|") !== -1 || win.editorKey.indexOf("|") !== -1)
      return "Hotkeys must not contain \"|\" (it is the field separator)"

    if (win.delimiter.indexOf("|") !== -1)
      return "The delimiter must not contain \"|\" (it is the field separator)"

    for (var c = 0; c < win.colorFields.length; c++)
      if (!win.colorValid(win.colorValue(win.colorFields[c].key)))
        return "Colours must be blank or hex, like #ff9e3f"

    for (var j = 0; j < win.rows.length; j++) {
      var r = win.rows[j]
      if (r.label === "" && r.prefix === "") return "Workspace " + r.id + " needs a number or a name"
      if (r.label.indexOf("|") !== -1 || r.key.indexOf("|") !== -1 || r.apps.indexOf("|") !== -1
          || r.prefix.indexOf("|") !== -1)
        return "Entry for \"" + r.label + "\" contains \"|\" — not allowed (it is the field separator)"
    }
    return ""
  }

  // Write whatever is valid right now. An invalid edit simply is not written
  // until it becomes valid again, so a half-typed name never reaches disk.
  function flush() {
    var problem = win.validate()
    win.errorText = problem
    if (problem !== "" || !widget) return

    widget.saveConf(widget.buildConf(win.rows, {
      rename: win.renameKey,
      jump: win.jumpKey,
      editor: win.editorKey,
      center: win.centerBarLoaded,
      centermoved: win.centerMoved,
      icons: win.iconCount,
      style: win.barStyle,
      base: win.countFromZero ? "0" : "1",
      compact: win.compactNames,
      number: win.showNumbers,
      delim: win.delimiter,
      coloractive: win.colorActive,
      colorunfocused: win.colorUnfocused,
      coloroccupied: win.colorOccupied,
      colorempty: win.colorEmpty
    }))

    // Only chase windows when the pins actually changed, so an unrelated
    // edit does not yank windows around.
    var pins = JSON.stringify(win.pinMap())
    if (pins !== win.lastAppliedPins) {
      win.applyPinMoves()
      win.lastAppliedPins = pins
    }
  }

  // App picker: which row is choosing an app class (-1 = closed)
  property int appsPickerRow: -1
  property string appQuery: ""
  property bool pickerRunningOnly: false
  property int appSelected: 0

  onAppQueryChanged: appSelected = 0
  onPickerRunningOnlyChanged: appSelected = 0

  function iconSourceFor(icon) {
    var v = String(icon || "")
    if (v === "") return ""
    if (v.indexOf("file://") === 0 || v.indexOf("image://") === 0) return v
    if (v.charAt(0) === "/") return "file://" + v
    return Quickshell.iconPath(v, true)
  }

  function classIcon(cls) {
    var entry = DesktopEntries.heuristicLookup(cls)
    return entry ? win.iconSourceFor(entry.icon) : ""
  }

  function openAppsPicker(index) {
    Hyprland.refreshToplevels()
    win.appQuery = ""
    win.appSelected = 0
    win.appsPickerRow = index
  }

  // Unique window classes of everything currently running, with an example
  // title each. These classes are exact — they come from live windows.
  readonly property var runningApps: {
    if (win.appsPickerRow < 0) return []
    var seen = {}
    var out = []
    var values = Hyprland.toplevels.values
    for (var i = 0; i < values.length; i++) {
      var ipc = values[i].lastIpcObject || ({})
      var cls = String(ipc["class"] || ipc.initialClass || "")
      if (cls === "" || seen[cls]) continue
      seen[cls] = true
      out.push({ cls: cls, name: String(values[i].title || ""), running: true, icon: win.classIcon(cls) })
    }
    return out
  }

  // Every installed app (desktop entries). Class is StartupWMClass when the
  // app declares one, else the desktop id — a best-effort guess; a running
  // window's class (the "running" filter) is always exact.
  readonly property var installedApps: {
    if (win.appsPickerRow < 0) return []
    var out = []
    var running = {}
    for (var r = 0; r < win.runningApps.length; r++) running[win.runningApps[r].cls] = true
    var values = DesktopEntries.applications.values || []
    for (var i = 0; i < values.length; i++) {
      var e = values[i]
      if (!e || e.noDisplay) continue
      var cls = String(e.startupClass || e.id || "")
      if (cls === "") continue
      // A live window's class is exact; when one matches the desktop-file
      // guess (case-insensitive prefix), prefer it — e.g. the guess
      // "md.Obsidian" becomes the real class "md.obsidian.Obsidian".
      for (var c = 0; c < win.runningApps.length; c++) {
        var rc = win.runningApps[c].cls
        if (rc.toLowerCase().indexOf(cls.toLowerCase()) === 0) { cls = rc; break }
      }
      out.push({ cls: cls, name: String(e.name || ""), running: running[cls] === true, icon: win.iconSourceFor(e.icon) })
    }
    return out
  }

  function scoreApp(item, q) {
    if (q === "") return 0
    var hay = (item.cls + " " + item.name).toLowerCase()
    var terms = q.toLowerCase().split(/\s+/)
    var total = 0
    for (var i = 0; i < terms.length; i++) {
      var t = terms[i]
      if (!t) continue
      var at = hay.indexOf(t)
      if (at !== -1) { total += 1000 - Math.min(at, 500); continue }
      var pos = -1
      for (var c = 0; c < t.length; c++) {
        pos = hay.indexOf(t.charAt(c), pos + 1)
        if (pos === -1) return -1
      }
      total += 400 - Math.min(pos, 390)
    }
    return total
  }

  readonly property var pickerItems: {
    var source = win.pickerRunningOnly ? win.runningApps : win.installedApps
    var out = []
    for (var i = 0; i < source.length; i++) {
      var sc = win.scoreApp(source[i], win.appQuery)
      if (sc >= 0) out.push({ item: source[i], sc: sc })
    }
    out.sort(function(a, b) {
      if (b.sc !== a.sc) return b.sc - a.sc
      return a.item.cls < b.item.cls ? -1 : 1
    })
    var items = []
    for (var j = 0; j < out.length; j++) items.push(out[j].item)
    return items
  }

  function pickApp(cls) {
    if (win.appsPickerRow >= 0) {
      var cur = win.rows[win.appsPickerRow].apps
      var apps = cur === "" ? [] : cur.split(",")
      if (apps.indexOf(cls) === -1) apps.push(cls)
      win.rows[win.appsPickerRow].apps = apps.join(",")
      win.touch()
    }
    win.appsPickerRow = -1
  }

  function removeApp(rowIndex, app) {
    var apps = win.rows[rowIndex].apps.split(",").filter(function(a) { return a !== app })
    win.rows[rowIndex].apps = apps.join(",")
    win.touch()
  }

  function moveApp(fromRow, toRow, app) {
    if (fromRow === toRow || fromRow < 0 || toRow < 0) return
    var from = win.rows[fromRow].apps.split(",").filter(function(a) { return a !== app })
    win.rows[fromRow].apps = from.join(",")
    var cur = win.rows[toRow].apps
    var apps = cur === "" ? [] : cur.split(",")
    if (apps.indexOf(app) === -1) apps.push(app)
    win.rows[toRow].apps = apps.join(",")
    win.touch()
  }

  visible: false
  anchors { top: true; bottom: true; left: true; right: true }
  color: "transparent"
  WlrLayershell.namespace: "omarchy-workspace-manager-editor"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

  readonly property color fg: Color.foreground
  readonly property color dim: Qt.rgba(fg.r, fg.g, fg.b, 0.55)
  readonly property color line: Qt.rgba(fg.r, fg.g, fg.b, 0.18)

  // "" is a real choice: an unpinned workspace opens wherever focus is.
  function monitorNames() {
    var names = []
    var screens = Quickshell.screens
    for (var i = 0; i < screens.length; i++) names.push(String(screens[i].name))
    names.push("")
    return names
  }

  function monitorLabel(name) {
    return name === "" ? "Any monitor" : name
  }

  // Adopt whatever Hyprland already has, so someone installing this on a
  // machine they have been using does not retype a setup that exists.
  // How many of Hyprland's workspaces are not in the list yet.
  function missingCount() {
    if (!widget) return 0
    var found = widget.importableRows()
    var byId = {}
    for (var i = 0; i < win.rows.length; i++) byId[win.rows[i].id] = true
    var n = 0
    for (var j = 0; j < found.length; j++) if (!byId[found[j].id]) n++
    return n
  }

  function importExisting() {
    if (!widget) return
    var found = widget.importableRows()
    if (found.length === 0) return

    var byId = {}
    for (var i = 0; i < win.rows.length; i++) byId[win.rows[i].id] = true

    var copy = win.rows.slice()
    var added = 0
    for (var j = 0; j < found.length; j++) {
      if (byId[found[j].id]) continue   // never overwrite one already configured
      copy.push(found[j])
      added++
    }
    copy.sort(function(a, b) { return a.id - b.id })
    win.rows = copy
    win.errorText = ""
    win.noteExpires = true
    win.conflictNote = added === 0
      ? "Nothing to import — every workspace Hyprland has is already listed."
      : "Imported " + added + (added === 1 ? " workspace" : " workspaces") + " from Hyprland."
    win.revision++
    win.autosave()
  }

  function addWorkspace() {
    var maxId = 0
    for (var i = 0; i < win.rows.length; i++) maxId = Math.max(maxId, win.rows[i].id)
    var next = maxId + 1
    var copy = win.rows.slice()
    copy.push({ id: next, key: "", monitor: "", label: "",
                apps: "", prefix: String(win.countFromZero ? next - 1 : next) })
    win.rows = copy
    win.errorText = ""
    win.revision++
    win.autosave()
    Qt.callLater(function() { list.positionViewAtEnd() })
  }

  function windowCount(workspaceId) {
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++)
      if (values[i].id === workspaceId)
        return values[i].toplevels ? values[i].toplevels.values.length : 0
    return 0
  }

  // Removing a workspace that still holds windows would strand them, so make
  // the user move them out first.
  function removeWorkspace(index) {
    if (win.rows.length <= 1) {
      win.errorText = "At least one workspace is needed"
      return
    }

    var row = win.rows[index]
    var open = win.windowCount(row.id)
    if (open > 0) {
      win.errorText = "\"" + row.label + "\" still has " + open
        + (open === 1 ? " open window" : " open windows") + " — move them somewhere else first"
      return
    }

    var copy = []
    for (var i = 0; i < win.rows.length; i++) if (i !== index) copy.push(win.rows[i])
    win.rows = copy
    win.errorText = ""
    win.revision++
    win.autosave()
  }

  // The colour the bar would draw this workspace in, so the editor list reads
  // the same way at a glance: which one is focused, which is active on the
  // other monitor, which hold windows, which are empty.
  function rowTint(row) {
    var live = null
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++)
      if (values[i].id === row.id) { live = values[i]; break }

    var focusedId = Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : -1
    if (row.id === focusedId)
      return win.colorActive !== "" ? win.colorActive : Color.urgent

    if (live && live.active === true)
      return win.colorUnfocused !== "" ? win.colorUnfocused
                                       : (widget ? widget.defaultUnfocusedColor : "#ff9e3f")

    var occupied = live && live.toplevels ? live.toplevels.values.length > 0 : false
    if (occupied) return win.colorOccupied !== "" ? win.colorOccupied : win.fg
    return win.colorEmpty !== "" ? win.colorEmpty : win.dim
  }

  function openNow() {
    var src = widget ? widget.rows : []
    var copy = []
    for (var i = 0; i < src.length; i++)
      copy.push({ id: src[i].id, key: src[i].key, monitor: src[i].monitor, label: src[i].label,
                  apps: src[i].apps || "", prefix: src[i].prefix === undefined ? "" : src[i].prefix })
    win.rows = copy
    win.renameKey = widget ? widget.renameKey : ""
    win.jumpKey = widget ? widget.jumpKey : ""
    win.editorKey = widget ? widget.editorKey : ""
    win.centerBar = widget ? widget.centerBar : false
    win.centerBarLoaded = win.centerBar
    win.centerMoved = widget ? widget.centerMoved : ""
    win.iconCount = widget ? widget.iconCount : 3
    win.barStyle = widget ? widget.barStyle : "plain"
    win.countFromZero = widget ? widget.countFromZero : false
    win.compactNames = widget ? widget.compactNames : false
    win.showNumbers = widget ? widget.showNumbers : true
    win.delimiter = widget ? widget.delimiter : ":"
    win.colorActive = widget ? widget.colorActive : ""
    win.colorUnfocused = widget ? widget.colorUnfocused : ""
    win.colorOccupied = widget ? widget.colorOccupied : ""
    win.colorEmpty = widget ? widget.colorEmpty : ""
    win.lastAppliedPins = JSON.stringify(win.pinMap())
    win.tab = "workspaces"
    win.conflicts = ({})
    win.tipText = ""
    if (widget) widget.refreshBinds()
    Qt.callLater(win.rescanConflicts)

    // Nothing configured yet: adopt what Hyprland already has rather than
    // opening on an empty table. Only ever on an empty list — once there is
    // a configuration, it is the source of truth, and a workspace Hyprland
    // has that this does not is usually transient rather than missing.
    if (win.rows.length === 0) Qt.callLater(win.importExisting)
    win.revision++
    win.errorText = ""

    // Open on whichever monitor has focus, not wherever the instance that
    // handled the hotkey happens to live.
    var focusedName = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""
    var screens = Quickshell.screens
    for (var s = 0; s < screens.length; s++)
      if (screens[s].name === focusedName) win.screen = screens[s]
    win.openedOn = focusedName

    win.visible = true
    Qt.callLater(function() { if (win.visible) card.forceActiveFocus() })
  }

  function pinMap() {
    var out = {}
    for (var i = 0; i < win.rows.length; i++) {
      var apps = win.rows[i].apps === "" ? [] : win.rows[i].apps.split(",")
      for (var a = 0; a < apps.length; a++) out[apps[a]] = win.rows[i].id
    }
    return out
  }

  // Saving enforces every pin on the windows that are already open, so a tag
  // dragged to another workspace takes its running windows along and the
  // pins never disagree with what is on screen.
  function applyPinMoves() {
    Hyprland.refreshToplevels()
    var now = win.pinMap()
    var values = Hyprland.toplevels.values

    for (var app in now) {
      var re = null
      try { re = new RegExp(app) } catch (e) { re = null }

      for (var i = 0; i < values.length; i++) {
        var t = values[i]
        var ipc = t.lastIpcObject || ({})
        var cls = String(ipc["class"] || ipc.initialClass || "")
        if (re ? !re.test(cls) : cls !== app) continue
        if (t.workspace && t.workspace.id === now[app]) continue

        var addr = String(t.address || "")
        if (addr.indexOf("0x") !== 0) addr = "0x" + addr
        Hyprland.dispatch('hl.dsp.window.move({ window = "address:' + addr + '", workspace = "' + now[app] + '", follow = false })')
      }
    }
  }

  function close() {
    // A change made in the last half-second is still sitting behind the
    // debounce. Closing must not be a way to lose it.
    if (autosaveTimer.running) {
      autosaveTimer.stop()
      win.flush()
    }
    win.visible = false
    win.applyBarLayout()
  }

  // Rearranging the bar makes the shell rebuild it, which tears this window
  // down with it — so it waits until the window is going away anyway. The
  // setting is still saved the moment it is clicked; only the rearranging
  // is held back.
  function applyBarLayout() {
    if (!widget || win.centerBar === win.centerBarLoaded) return
    win.centerMoved = widget.setBarCentered(win.centerBar, win.centerMoved)
    win.centerBarLoaded = win.centerBar
    widget.saveConf(widget.buildConf(win.rows, {
      rename: win.renameKey,
      jump: win.jumpKey,
      editor: win.editorKey,
      center: win.centerBarLoaded,
      centermoved: win.centerMoved,
      icons: win.iconCount,
      style: win.barStyle,
      base: win.countFromZero ? "0" : "1",
      compact: win.compactNames,
      number: win.showNumbers,
      delim: win.delimiter,
      coloractive: win.colorActive,
      colorunfocused: win.colorUnfocused,
      coloroccupied: win.colorOccupied,
      colorempty: win.colorEmpty
    }))
  }

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


  // The rows are plain JS objects, so a mutation inside one is invisible to
  // QML bindings. Rebuild the array to make every delegate re-read its row.
  function touch() {
    var copy = []
    for (var i = 0; i < win.rows.length; i++) {
      var r = win.rows[i]
      copy.push({ id: r.id, key: r.key, monitor: r.monitor, label: r.label, apps: r.apps, prefix: r.prefix })
    }
    win.rows = copy
    win.revision++
    win.rescanConflicts()
    win.autosave()
  }

  function cycleMonitor(index) {
    var names = monitorNames()
    if (names.length === 0) return
    var current = names.indexOf(win.rows[index].monitor)
    win.rows[index].monitor = names[(current + 1) % names.length]
    win.touch()
  }

  function setKey(index, keys) {
    // A key belongs to one workspace. Assigning it here takes it from
    // whoever had it, rather than leaving two rows claiming the same
    // combination and letting whichever binds last win.
    if (keys !== "") {
      for (var i = 0; i < win.rows.length; i++)
        if (i !== index && win.rows[i].key === keys) win.rows[i].key = ""
    }

    win.rows[index].key = keys
    // Check before rebuilding the rows. touch() destroys and recreates the
    // delegates, which takes the handler that called this down with it — a
    // second statement after it never runs.
    win.touch()
    win.rescanConflicts()
  }


  // Scrim
  Rectangle {
    anchors.fill: parent
    color: Qt.rgba(0, 0, 0, 0.6)
    MouseArea { anchors.fill: parent; onClicked: win.close() }
  }

  Rectangle {
    id: card
    anchors.centerIn: parent
    width: 1180
    height: Math.min(win.height - 120, content.implicitHeight + 40)
    radius: 10
    color: Color.background
    border.color: win.line
    border.width: 1

    MouseArea { anchors.fill: parent }

    // Esc closes the editor. A KeyCapture consumes Esc while it is capturing
    // and the app picker's search field handles its own, so this only fires
    // when neither is holding focus.
    focus: true
    Keys.onEscapePressed: win.close()

    ColumnLayout {
      id: content
      anchors.fill: parent
      anchors.margins: 20
      spacing: 12

      RowLayout {
        Layout.fillWidth: true
        spacing: 16

        Repeater {
          model: [{ id: "workspaces", label: "Workspaces" }, { id: "settings", label: "Settings" }]

          Text {
            required property var modelData
            readonly property bool selected: win.tab === modelData.id

            text: modelData.label
            color: selected ? win.fg : win.dim
            font.family: Style.font.family
            font.pixelSize: Style.font.body + 3
            font.bold: selected

            MouseArea {
              anchors.fill: parent
              anchors.margins: -4
              cursorShape: Qt.PointingHandCursor
              onClicked: win.tab = modelData.id
            }
          }
        }

        Item { Layout.fillWidth: true }

        Text {
          visible: widget && widget.pluginVersion !== ""
          text: "v" + (widget ? widget.pluginVersion : "")
          color: win.dim
          font.family: Style.font.family
          font.pixelSize: Style.font.body - 3
          Layout.rightMargin: 4
        }

        // The explanation is a page of text that is worth reading once and
        // then never again, so it hides behind this rather than sitting
        // above the table forever.
        Rectangle {
          visible: win.tab === "workspaces"
          Layout.preferredWidth: 20
          Layout.preferredHeight: 20
          radius: 10
          color: win.showHelp ? Qt.rgba(win.fg.r, win.fg.g, win.fg.b, 0.15) : "transparent"
          border.color: win.showHelp ? win.fg : win.line
          border.width: 1

          Text {
            anchors.centerIn: parent
            text: "i"
            color: win.showHelp ? win.fg : win.dim
            font.family: Style.font.family
            font.pixelSize: Style.font.body - 1
            font.bold: true
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: win.showHelp = !win.showHelp
          }
        }
      }

      // Shown only until Hyprland is wired up. Without it the widget draws
      // but nothing switches, binds or persists, which is a confusing state
      // to leave someone in silently.
      Rectangle {
        visible: win.tab === "workspaces" && widget && !widget.hyprConfigInstalled
        Layout.fillWidth: true
        Layout.preferredHeight: setupRow.implicitHeight + 20
        radius: 6
        color: Qt.rgba(Color.urgent.r, Color.urgent.g, Color.urgent.b, 0.10)
        border.color: Color.urgent
        border.width: 1

        RowLayout {
          id: setupRow
          anchors.fill: parent
          anchors.margins: 10
          spacing: 12

          ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            Text {
              text: "Hyprland is not wired up yet"
              color: win.fg
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              font.bold: true
            }

            Text {
              text: "Workspaces will not switch, bind or persist until two lines are added to your monitors.lua and bindings.lua. Both files are backed up first, and the lines sit in a marked block you can delete."
              color: win.dim
              font.family: Style.font.family
              font.pixelSize: Style.font.body - 2
              Layout.fillWidth: true
              wrapMode: Text.WordWrap
            }
          }

          Rectangle {
            visible: win.missingCount() > 0
            Layout.preferredWidth: 150
            Layout.preferredHeight: 30
            radius: 6
            color: "transparent"
            border.color: win.fg
            border.width: 1

            Text {
              anchors.centerIn: parent
              text: "Import existing"
              color: win.fg
              font.family: Style.font.family
              font.pixelSize: Style.font.body
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: win.importExisting()
            }
          }

          Rectangle {
            Layout.preferredWidth: 150
            Layout.preferredHeight: 30
            radius: 6
            color: win.fg

            Text {
              anchors.centerIn: parent
              text: "Add to Hyprland"
              color: Color.background
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              font.bold: true
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: if (widget) widget.installHyprConfig()
            }
          }
        }
      }

      // One line per thing, rather than a paragraph nobody finishes.
      ColumnLayout {
        visible: win.tab === "workspaces" && win.showHelp
        Layout.fillWidth: true
        spacing: 3

        Repeater {
          model: [
            "Everything saves as you change it. Esc closes.",
            "Click a number, name or monitor to edit it. “Any monitor” leaves a workspace free to open wherever focus is.",
            "Click a hotkey, then press the combination. Existing bindings are suspended while it listens, so a key that is already taken still records. SUPER is implied on workspace rows.",
            "“+” pins an app so it always opens on that workspace. “✕” unpins it.",
            "Drag a tag from one workspace onto another to move the pin — the app's open windows follow when you close the editor.",
            "A workspace can only be deleted once its windows have moved elsewhere."
          ]

          Text {
            required property string modelData
            text: "· " + modelData
            color: win.dim
            font.family: Style.font.family
            font.pixelSize: Style.font.body - 1
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
          }
        }

        Text {
          text: "· Full documentation: " + (widget ? widget.docsUrl : "")
          color: win.fg
          font.family: Style.font.family
          font.pixelSize: Style.font.body - 1
          Layout.fillWidth: true
          wrapMode: Text.WordWrap

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: if (widget) widget.openDocs()
          }
        }
      }

      // Settings pane — one row per setting
      ColumnLayout {
        visible: win.tab === "settings"
        Layout.fillWidth: true
        spacing: 8

        Repeater {
          model: [
            { key: "rename", label: "Rename hotkey", hint: "Rename the active workspace" },
            { key: "jump", label: "Jump hotkey", hint: "Fuzzy-find workspaces and windows" },
            { key: "editor", label: "Editor hotkey", hint: "Open this editor" }
          ]

          RowLayout {
            required property var modelData
            Layout.fillWidth: true
            spacing: 10

            Text {
              text: modelData.label
              color: win.dim
              font.family: Style.font.family
              font.pixelSize: Style.font.body - 1
              Layout.preferredWidth: 110
            }

            KeyCapture {
              widget: win.widget
              Layout.preferredWidth: 190
              Layout.preferredHeight: 26
              value: modelData.key === "rename" ? win.renameKey
                   : modelData.key === "jump" ? win.jumpKey : win.editorKey
              warn: win.conflictFor(value) !== ""
              onWarnHover: function(hovered) { win.showTip(hovered, this, value) }
              fg: win.fg
              dimColor: win.dim
              lineColor: win.line
              onCaptured: function(keys) {
                if (modelData.key === "rename") win.renameKey = keys
                else if (modelData.key === "jump") win.jumpKey = keys
                else win.editorKey = keys
                value = keys
                win.claimGlobalHotkey(modelData.key, keys)
                win.rescanConflicts()
                win.autosave()
              }
            }

            Text {
              text: modelData.hint
              color: win.dim
              font.family: Style.font.family
              font.pixelSize: Style.font.body - 2
              Layout.fillWidth: true
              elide: Text.ElideRight
            }
          }
        }
      }

      // Settings pane
      RowLayout {
        visible: win.tab === "settings"
        Layout.fillWidth: true
        Layout.topMargin: 6
        spacing: 10

        Rectangle {
          Layout.preferredWidth: 18
          Layout.preferredHeight: 18
          radius: 4
          color: win.centerBar ? win.fg : "transparent"
          border.color: win.centerBar ? win.fg : win.line
          border.width: 1

          Text {
            anchors.centerIn: parent
            text: win.centerBar ? "✓" : ""
            color: Color.background
            font.pixelSize: Style.font.body - 2
            font.bold: true
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: { win.centerBar = !win.centerBar; win.autosave() }
          }
        }

        ColumnLayout {
          Layout.fillWidth: true
          spacing: 2

          Text {
            text: "Center the workspaces in the bar"
            color: win.fg
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: { win.centerBar = !win.centerBar; win.autosave() }
            }
          }

          Text {
            text: (win.centerBar
              ? "Widgets that were centered sit on the right; unticking puts them back."
              : "Workspaces sit on the left. Ticking moves them to the center and pushes the centered widgets to the right.")
              + (win.centerBar !== win.centerBarLoaded ? "  The bar rearranges when you close this window." : "")
            color: win.dim
            font.family: Style.font.family
            font.pixelSize: Style.font.body - 2
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
          }
        }
      }

      // App icons beside each workspace name
      RowLayout {
        visible: win.tab === "settings"
        Layout.fillWidth: true
        Layout.topMargin: 4
        spacing: 10

        Text {
          text: "App icons"
          color: win.dim
          font.family: Style.font.family
          font.pixelSize: Style.font.body - 1
          Layout.preferredWidth: 110
        }

        Rectangle {
          Layout.preferredWidth: 26
          Layout.preferredHeight: 26
          radius: 5
          color: "transparent"
          border.color: win.line
          border.width: 1
          Text { anchors.centerIn: parent; text: "−"; color: win.iconCount > 0 ? win.fg : win.dim; font.pixelSize: Style.font.body }
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: if (win.iconCount > 0) { win.iconCount--; win.autosave() }
          }
        }

        Text {
          text: win.iconCount === 0 ? "off" : String(win.iconCount)
          color: win.fg
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          horizontalAlignment: Text.AlignHCenter
          Layout.preferredWidth: 30
        }

        Rectangle {
          Layout.preferredWidth: 26
          Layout.preferredHeight: 26
          radius: 5
          color: "transparent"
          border.color: win.line
          border.width: 1
          Text { anchors.centerIn: parent; text: "+"; color: win.fg; font.pixelSize: Style.font.body }
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: { win.iconCount++; win.autosave() }
          }
        }

        Text {
          text: "How many app icons show next to a workspace name (0 turns them off). One icon per distinct app."
          color: win.dim
          font.family: Style.font.family
          font.pixelSize: Style.font.body - 2
          Layout.fillWidth: true
          wrapMode: Text.WordWrap
        }
      }

      // How the marked workspace is drawn on the bar
      RowLayout {
        visible: win.tab === "settings"
        Layout.fillWidth: true
        spacing: 10

        Text {
          text: "Bar style"
          color: win.dim
          font.family: Style.font.family
          font.pixelSize: Style.font.body - 1
          Layout.preferredWidth: 110
        }

        Repeater {
          model: win.barStyles

          Rectangle {
            required property string modelData
            Layout.preferredWidth: 80
            Layout.preferredHeight: 26
            radius: 5
            color: win.barStyle === modelData ? Qt.rgba(win.fg.r, win.fg.g, win.fg.b, 0.15) : "transparent"
            border.color: win.barStyle === modelData ? win.fg : win.line
            border.width: 1

            Text {
              anchors.centerIn: parent
              text: modelData
              color: win.fg
              font.family: Style.font.family
              font.pixelSize: Style.font.body - 2
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: { win.barStyle = modelData; win.autosave() }
            }
          }
        }

        Text {
          text: "Plain colours the text only; pill fills behind it; underline rules beneath it."
          color: win.dim
          font.family: Style.font.family
          font.pixelSize: Style.font.body - 2
          Layout.fillWidth: true
          wrapMode: Text.WordWrap
        }
      }

      // How the user counts workspaces
      RowLayout {
        visible: win.tab === "settings"
        Layout.fillWidth: true
        spacing: 10

        Text {
          text: "Numbering"
          color: win.dim
          font.family: Style.font.family
          font.pixelSize: Style.font.body - 1
          Layout.preferredWidth: 110
        }

        Repeater {
          model: [{ zero: false, label: "From 1" }, { zero: true, label: "From 0" }]

          Rectangle {
            required property var modelData
            Layout.preferredWidth: 80
            Layout.preferredHeight: 26
            radius: 5
            color: win.countFromZero === modelData.zero ? Qt.rgba(win.fg.r, win.fg.g, win.fg.b, 0.15) : "transparent"
            border.color: win.countFromZero === modelData.zero ? win.fg : win.line
            border.width: 1

            Text {
              anchors.centerIn: parent
              text: modelData.label
              color: win.fg
              font.family: Style.font.family
              font.pixelSize: Style.font.body - 2
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: { win.countFromZero = modelData.zero; win.autosave() }
            }
          }
        }

        Text {
          text: "Hyprland has no workspace 0, so counting from 0 leaves your first workspace on id 1. This only affects the numbers the plugin generates and shows — names you have already written are left alone."
          color: win.dim
          font.family: Style.font.family
          font.pixelSize: Style.font.body - 2
          Layout.fillWidth: true
          wrapMode: Text.WordWrap
        }
      }

      // Whether the number is drawn at all
      RowLayout {
        visible: win.tab === "settings"
        Layout.fillWidth: true
        spacing: 10

        Rectangle {
          Layout.preferredWidth: 18
          Layout.preferredHeight: 18
          radius: 4
          color: win.showNumbers ? win.fg : "transparent"
          border.color: win.showNumbers ? win.fg : win.line
          border.width: 1

          Text {
            anchors.centerIn: parent
            text: win.showNumbers ? "✓" : ""
            color: Color.background
            font.pixelSize: Style.font.body - 2
            font.bold: true
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: { win.showNumbers = !win.showNumbers; win.autosave() }
          }
        }

        ColumnLayout {
          Layout.fillWidth: true
          spacing: 2

          Text {
            text: "Include the number in the bar"
            color: win.fg
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: { win.showNumbers = !win.showNumbers; win.autosave() }
            }
          }

          Text {
            text: "The number is a field of its own, not part of the name, so it can be hidden without editing anything. A workspace with only a number still shows it."
            color: win.dim
            font.family: Style.font.family
            font.pixelSize: Style.font.body - 2
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
          }
        }
      }

      // What separates the number from the name
      RowLayout {
        visible: win.tab === "settings"
        Layout.fillWidth: true
        spacing: 10

        Text {
          text: "Delimiter"
          color: win.dim
          font.family: Style.font.family
          font.pixelSize: Style.font.body - 1
          Layout.preferredWidth: 110
        }

        Rectangle {
          Layout.preferredWidth: 60
          Layout.preferredHeight: 26
          radius: 5
          color: "transparent"
          border.color: delimInput.text.indexOf("|") !== -1 ? Color.urgent
                      : (delimInput.activeFocus ? win.fg : win.line)
          border.width: 1

          TextInput {
            id: delimInput
            maximumLength: 1
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            verticalAlignment: TextInput.AlignVCenter
            text: win.delimiter
            color: win.fg
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            clip: true
            selectByMouse: true
            onTextEdited: { win.delimiter = text; win.autosave() }
            Keys.onEscapePressed: win.close()
          }
        }

        Text {
          text: "A single character between the number and the name — “0" + win.delimiter + " MLStudios”. Display only; it is not stored in either field."
          color: win.dim
          font.family: Style.font.family
          font.pixelSize: Style.font.body - 2
          Layout.fillWidth: true
          wrapMode: Text.WordWrap
        }
      }

      // Spacing after the "number:" prefix, on the bar only
      RowLayout {
        visible: win.tab === "settings"
        Layout.fillWidth: true
        spacing: 10

        Text {
          text: "Name spacing"
          color: win.dim
          font.family: Style.font.family
          font.pixelSize: Style.font.body - 1
          Layout.preferredWidth: 110
        }

        Repeater {
          model: [{ compact: false, spaced: true }, { compact: true, spaced: false }]

          Rectangle {
            required property var modelData
            Layout.preferredWidth: 80
            Layout.preferredHeight: 26
            radius: 5
            color: win.compactNames === modelData.compact ? Qt.rgba(win.fg.r, win.fg.g, win.fg.b, 0.15) : "transparent"
            border.color: win.compactNames === modelData.compact ? win.fg : win.line
            border.width: 1

            Text {
              anchors.centerIn: parent
              text: "0" + win.delimiter + (modelData.spaced ? " " : "") + "Test"
              color: win.fg
              font.family: Style.font.family
              font.pixelSize: Style.font.body - 2
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: { win.compactNames = modelData.compact; win.autosave() }
            }
          }
        }

        Text {
          text: "Drops the space after the first colon when drawing a workspace. Display only — the name keeps its space, so renaming still works on the part after it."
          color: win.dim
          font.family: Style.font.family
          font.pixelSize: Style.font.body - 2
          Layout.fillWidth: true
          wrapMode: Text.WordWrap
        }
      }

      // Workspace colours — blank follows the theme
      ColumnLayout {
        visible: win.tab === "settings"
        Layout.fillWidth: true
        Layout.topMargin: 4
        spacing: 6

        RowLayout {
          Layout.fillWidth: true
          spacing: 10

          Text {
            text: "Colours"
            color: win.dim
            font.family: Style.font.family
            font.pixelSize: Style.font.body - 1
            Layout.preferredWidth: 110
          }

          Text {
            text: "Hex like #ff9e3f, or blank to follow the theme."
            color: win.dim
            font.family: Style.font.family
            font.pixelSize: Style.font.body - 2
            Layout.fillWidth: true
          }
        }

        Repeater {
          model: win.colorFields

          RowLayout {
            required property var modelData
            Layout.fillWidth: true
            spacing: 10

            Item { Layout.preferredWidth: 110 }

            Rectangle {
              Layout.preferredWidth: 20
              Layout.preferredHeight: 20
              radius: 4
              color: win.colorPreview(modelData.key)
              border.color: win.line
              border.width: 1
            }

            Text {
              text: modelData.label
              color: win.fg
              font.family: Style.font.family
              font.pixelSize: Style.font.body - 1
              Layout.preferredWidth: 130
            }

            Rectangle {
              Layout.preferredWidth: 120
              Layout.preferredHeight: 24
              radius: 5
              color: "transparent"
              border.color: win.colorValid(hexInput.text) ? (hexInput.activeFocus ? win.fg : win.line) : Color.urgent
              border.width: 1

              TextInput {
                id: hexInput
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                verticalAlignment: TextInput.AlignVCenter
                text: win.colorValue(modelData.key)
                color: win.fg
                font.family: Style.font.family
                font.pixelSize: Style.font.body - 2
                clip: true
                selectByMouse: true
                onTextEdited: win.setColorValue(modelData.key, text)
                Keys.onEscapePressed: win.close()
              }

              Text {
                anchors.fill: hexInput
                verticalAlignment: Text.AlignVCenter
                text: "theme"
                color: Qt.rgba(win.fg.r, win.fg.g, win.fg.b, 0.3)
                font.family: Style.font.family
                font.pixelSize: Style.font.body - 2
                visible: hexInput.text === ""
              }
            }

            Item { Layout.fillWidth: true }
          }
        }
      }

      Item {
        visible: win.tab === "settings"
        Layout.fillHeight: true
      }

      Rectangle {
        visible: win.tab === "workspaces"
        Layout.fillWidth: true
        height: 1
        color: win.line
      }

      // Column headers, widths kept in step with the row delegate below.
      RowLayout {
        visible: win.tab === "workspaces"
        Layout.fillWidth: true
        Layout.bottomMargin: 2
        spacing: 10

        Repeater {
          model: [
            { title: "No.", width: 54 },
            { title: "Name", width: 200 },
            { title: "Monitor", width: 130 },
            { title: "Hotkey", width: 230 },
            { title: "Pinned apps", width: -1 },
            { title: "", width: 26 },
            { title: "", width: 26 }
          ]

          Text {
            required property var modelData
            text: modelData.title
            color: win.dim
            font.family: Style.font.family
            font.pixelSize: Style.font.body - 1
            font.bold: true
            elide: Text.ElideRight
            Layout.preferredWidth: modelData.width > 0 ? modelData.width : 0
            Layout.fillWidth: modelData.width < 0
          }
        }
      }

      Rectangle {
        visible: win.tab === "workspaces"
        Layout.fillWidth: true
        height: 1
        color: win.line
      }

      ListView {
        id: list
        visible: win.tab === "workspaces"
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.preferredHeight: visible ? contentHeight : 0
        clip: true
        spacing: 2
        model: win.rows

        delegate: Rectangle {
          id: rowRoot
          required property var modelData
          required property int index
          width: list.width
          height: Math.max(30, appsFlow.implicitHeight + 8)
          radius: 5
          color: rowDrop.containsDrag ? Qt.rgba(win.fg.r, win.fg.g, win.fg.b, 0.10) : "transparent"

          readonly property var row: modelData
          readonly property var appList: modelData.apps === "" ? [] : modelData.apps.split(",")


          // Any app tag dragged from another row can be dropped anywhere on
          // this row to re-pin it here.
          DropArea {
            id: rowDrop
            anchors.fill: parent
            keys: ["app-chip"]
            onDropped: function(drop) {
              win.moveApp(drop.source.fromRow, rowRoot.index, drop.source.appName)
              drop.accept()
            }
          }

          RowLayout {
            anchors.fill: parent
            spacing: 10

            // The number this workspace is under the chosen numbering, next to
            // the Hyprland id it actually maps to — the offset a count-from-0
            // numpad user lives with, made visible instead of remembered.
            // The number is its own field: it is often not a number at all
            // (0A, L, SA), so it is typed rather than derived.
            Rectangle {
              Layout.preferredWidth: 54
              Layout.preferredHeight: 26
              radius: 5
              color: "transparent"
              border.color: prefixInput.text.indexOf("|") !== -1 ? Color.urgent
                          : (prefixInput.activeFocus ? win.fg : "transparent")
              border.width: 1

              TextInput {
                id: prefixInput
                anchors.fill: parent
                anchors.leftMargin: 6
                anchors.rightMargin: 6
                verticalAlignment: TextInput.AlignVCenter
                text: rowRoot.row.prefix !== "" ? rowRoot.row.prefix
                    : String(win.countFromZero ? rowRoot.index : rowRoot.index + 1)
                color: win.rowTint(rowRoot.row)
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                clip: true
                selectByMouse: true
                onTextEdited: { win.rows[rowRoot.index].prefix = text; win.autosave() }
                Keys.onEscapePressed: win.close()
              }
            }

            Rectangle {
              Layout.preferredWidth: 200
              Layout.preferredHeight: 26
              radius: 5
              color: "transparent"
              border.color: labelInput.text.indexOf("|") !== -1
                ? Color.urgent
                : (labelInput.activeFocus ? win.fg : "transparent")
              border.width: 1

              TextInput {
                id: labelInput
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                verticalAlignment: TextInput.AlignVCenter
                text: rowRoot.row.label
                color: win.rowTint(rowRoot.row)
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                clip: true
                selectByMouse: true
                // Mutate in place rather than touch(): rebuilding the rows on
                // every keystroke would destroy this field mid-word.
                onTextEdited: { win.rows[rowRoot.index].label = text; win.autosave() }
                Keys.onEscapePressed: win.close()
              }
            }

            Rectangle {
              Layout.preferredWidth: 130
              Layout.preferredHeight: 26
              radius: 5
              color: "transparent"
              border.color: win.line
              border.width: 1

              Text {
                anchors.centerIn: parent
                text: win.monitorLabel(rowRoot.row.monitor)
                color: rowRoot.row.monitor === "" ? win.dim : win.fg
                font.family: Style.font.family
                font.pixelSize: Style.font.body - 1
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: win.cycleMonitor(rowRoot.index)
              }
            }

            KeyCapture {
              widget: win.widget
              Layout.preferredWidth: 230
              Layout.preferredHeight: 26
              value: rowRoot.row.key
              warn: rowRoot.row.key !== "" && win.conflictFor("SUPER + " + rowRoot.row.key) !== ""
              onWarnHover: function(hovered) { win.showTip(hovered, this, "SUPER + " + rowRoot.row.key) }
              displayPrefix: "SUPER + "
              stripSuper: true
              fg: win.fg
              dimColor: win.dim
              lineColor: win.line
              onCaptured: function(keys) { win.setKey(rowRoot.index, keys) }
            }

            // Pinned apps as tags: ✕ removes, drag a tag onto another row to
            // move the pin there.
            Item {
              Layout.fillWidth: true
              Layout.preferredHeight: Math.max(26, appsFlow.implicitHeight)

              // Wrapping rather than truncating: a tag that is not drawn is a
              // pin that cannot be removed or dragged, and hiding the control
              // is worse than spending the height.
              Flow {
                id: appsFlow
                width: parent.width
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4

                Repeater {
                  model: rowRoot.appList

                  Item {
                    id: chipSlot
                    required property string modelData
                    width: chipRect.width
                    height: 20

                    Rectangle {
                      id: chipRect
                      readonly property string appName: chipSlot.modelData
                      readonly property int fromRow: rowRoot.index

                      width: chipText.implicitWidth + 30
                      height: 20
                      radius: 10
                      color: Qt.rgba(win.fg.r, win.fg.g, win.fg.b, 0.12)
                      border.color: win.line
                      border.width: 1

                      Drag.active: chipDrag.drag.active
                      Drag.keys: ["app-chip"]
                      Drag.source: chipRect
                      Drag.hotSpot.x: width / 2
                      Drag.hotSpot.y: height / 2

                      Text {
                        id: chipText
                        anchors.left: parent.left
                        anchors.leftMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        // Class names are long and their tail is the
                        // distinctive part, so keep that rather than the
                        // reverse-DNS prefix everything shares.
                        text: chipRect.appName.length > 16
                          ? "…" + chipRect.appName.slice(-15)
                          : chipRect.appName
                        color: win.fg
                        font.family: Style.font.family
                        font.pixelSize: Style.font.body - 2
                      }

                      Text {
                        id: chipClose
                        anchors.right: parent.right
                        anchors.rightMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        text: "✕"
                        color: win.dim
                        font.pixelSize: Style.font.body - 3
                      }

                      MouseArea {
                        id: chipDrag
                        anchors.fill: parent
                        anchors.rightMargin: 16
                        drag.target: chipRect
                        preventStealing: true
                        cursorShape: Qt.OpenHandCursor
                        onPressed: rowRoot.z = 10
                        onReleased: {
                          rowRoot.z = 0
                          if (chipRect.Drag.target !== null) chipRect.Drag.drop()
                          chipRect.x = 0
                          chipRect.y = 0
                        }
                      }

                      MouseArea {
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: 16
                        cursorShape: Qt.PointingHandCursor
                        onClicked: win.removeApp(rowRoot.index, chipRect.appName)
                      }
                    }
                  }
                }

              }
            }

            Rectangle {
              Layout.preferredWidth: 26
              Layout.preferredHeight: 26
              radius: 5
              color: "transparent"
              border.color: win.line
              border.width: 1

              Text {
                anchors.centerIn: parent
                text: "+"
                color: win.fg
                font.family: Style.font.family
                font.pixelSize: Style.font.body + 2
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: win.openAppsPicker(rowRoot.index)
              }
            }

            Rectangle {
              Layout.preferredWidth: 26
              Layout.preferredHeight: 26
              radius: 5
              color: "transparent"
              border.color: removeHover.containsMouse ? Color.urgent : win.line
              border.width: 1

              Text {
                anchors.centerIn: parent
                text: "🗑"
                color: removeHover.containsMouse ? Color.urgent : win.dim
                font.pixelSize: Style.font.body - 2
              }

              MouseArea {
                id: removeHover
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: win.removeWorkspace(rowRoot.index)
              }
            }
          }
        }
      }

      Rectangle {
        visible: win.tab === "workspaces"
        Layout.preferredWidth: addText.implicitWidth + 24
        Layout.preferredHeight: 26
        radius: 5
        color: "transparent"
        border.color: addHover.containsMouse ? win.fg : win.line
        border.width: 1

        Text {
          id: addText
          anchors.centerIn: parent
          text: "+  Add workspace"
          color: win.fg
          font.family: Style.font.family
          font.pixelSize: Style.font.body - 1
        }

        MouseArea {
          id: addHover
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: win.addWorkspace()
        }
      }

      Rectangle {
        visible: win.tab === "workspaces" && win.revision >= 0 && win.missingCount() > 0
        Layout.preferredWidth: importText.implicitWidth + 24
        Layout.preferredHeight: 26
        radius: 5
        color: "transparent"
        border.color: win.fg
        border.width: 1

        Text {
          id: importText
          anchors.centerIn: parent
          text: win.missingCount() === 1
            ? "Hyprland has 1 workspace that is not listed — import it"
            : "Hyprland has " + win.missingCount() + " workspaces that are not listed — import them"
          color: win.fg
          font.family: Style.font.family
          font.pixelSize: Style.font.body - 1
        }

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: win.importExisting()
        }
      }

      Rectangle { Layout.fillWidth: true; height: 1; color: win.line }

      RowLayout {
        Layout.fillWidth: true
        spacing: 10

        Text {
          text: win.errorText
          visible: win.errorText !== ""
          color: Color.urgent
          font.family: Style.font.family
          font.pixelSize: Style.font.body - 1
          elide: Text.ElideRight
          Layout.fillWidth: true
        }

        Text {
          text: win.conflictNote
          visible: win.errorText === "" && win.conflictNote !== ""
          color: "#ffb020"
          font.bold: true
          font.family: Style.font.family
          font.pixelSize: Style.font.body - 1
          elide: Text.ElideRight
          Layout.fillWidth: true
        }

        Text {
          text: "Changes save as you make them · Esc closes"
          visible: win.errorText === "" && win.conflictNote === ""
          color: win.dim
          font.family: Style.font.family
          font.pixelSize: Style.font.body - 1
          Layout.fillWidth: true
          horizontalAlignment: Text.AlignRight
        }
      }
    }
    Rectangle {
      visible: win.tipText !== ""
      x: Math.min(win.tipX, card.width - width - 8)
      y: win.tipY - height / 2
      z: 20
      width: tipLabel.implicitWidth + 16
      height: tipLabel.implicitHeight + 10
      radius: 4
      color: Color.background
      border.color: "#ffb020"
      border.width: 1

      Text {
        id: tipLabel
        anchors.centerIn: parent
        text: win.tipText
        color: "#ffb020"
        font.family: Style.font.family
        font.pixelSize: Style.font.body - 2
      }
    }
  }

  // App picker: fuzzy-search installed apps (or running windows), click or
  // Enter to add the class to the row
  Item {
    anchors.fill: parent
    visible: win.appsPickerRow >= 0
    z: 10

    onVisibleChanged: if (visible) Qt.callLater(function() { appSearch.forceActiveFocus() })

    MouseArea { anchors.fill: parent; onClicked: win.appsPickerRow = -1 }

    Rectangle {
      anchors.centerIn: parent
      width: 460
      height: Math.min(pickerContent.implicitHeight + 28, win.height - 200)
      radius: 10
      color: Color.background
      border.color: win.fg
      border.width: 1

      MouseArea { anchors.fill: parent }

      ColumnLayout {
        id: pickerContent
        anchors.fill: parent
        anchors.margins: 14
        spacing: 8

        RowLayout {
          Layout.fillWidth: true
          spacing: 8

          Text {
            text: "Pin an app"
            color: win.fg
            font.family: Style.font.family
            font.pixelSize: Style.font.body + 1
            font.bold: true
            Layout.fillWidth: true
          }

          Rectangle {
            Layout.preferredWidth: 70
            Layout.preferredHeight: 24
            radius: 5
            color: !win.pickerRunningOnly ? Qt.rgba(win.fg.r, win.fg.g, win.fg.b, 0.15) : "transparent"
            border.color: win.line
            border.width: 1
            Text { anchors.centerIn: parent; text: "All apps"; color: win.fg; font.family: Style.font.family; font.pixelSize: Style.font.body - 2 }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: win.pickerRunningOnly = false }
          }

          Rectangle {
            Layout.preferredWidth: 70
            Layout.preferredHeight: 24
            radius: 5
            color: win.pickerRunningOnly ? Qt.rgba(win.fg.r, win.fg.g, win.fg.b, 0.15) : "transparent"
            border.color: win.line
            border.width: 1
            Text { anchors.centerIn: parent; text: "Running"; color: win.fg; font.family: Style.font.family; font.pixelSize: Style.font.body - 2 }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: win.pickerRunningOnly = true }
          }
        }

        Rectangle {
          Layout.fillWidth: true
          Layout.preferredHeight: 30
          radius: 6
          color: "transparent"
          border.color: win.fg
          border.width: 1

          TextInput {
            id: appSearch
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            verticalAlignment: TextInput.AlignVCenter
            color: win.fg
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            clip: true
            onTextChanged: win.appQuery = text
            Keys.onEscapePressed: win.appsPickerRow = -1
            Keys.onReturnPressed: if (win.pickerItems.length > 0) win.pickApp(win.pickerItems[Math.min(win.appSelected, win.pickerItems.length - 1)].cls)
            Keys.onEnterPressed: if (win.pickerItems.length > 0) win.pickApp(win.pickerItems[Math.min(win.appSelected, win.pickerItems.length - 1)].cls)
            Keys.onDownPressed: {
              if (win.appSelected < win.pickerItems.length - 1) win.appSelected++
              pickerList.positionViewAtIndex(win.appSelected, ListView.Contain)
            }
            Keys.onUpPressed: {
              if (win.appSelected > 0) win.appSelected--
              pickerList.positionViewAtIndex(win.appSelected, ListView.Contain)
            }
          }

          Text {
            anchors.fill: appSearch
            verticalAlignment: Text.AlignVCenter
            text: "Search apps…"
            color: win.dim
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            visible: appSearch.text === ""
          }
        }

        ListView {
          id: pickerList
          Layout.fillWidth: true
          Layout.fillHeight: true
          Layout.preferredHeight: contentHeight
          clip: true
          spacing: 2
          model: win.pickerItems

          delegate: Rectangle {
            required property var modelData
            required property int index
            width: pickerList.width
            height: 30
            radius: 5
            color: index === win.appSelected || pickerHover.containsMouse ? Qt.rgba(win.fg.r, win.fg.g, win.fg.b, 0.12) : "transparent"

            RowLayout {
              anchors.fill: parent
              anchors.leftMargin: 8
              anchors.rightMargin: 8
              spacing: 10

              Image {
                Layout.preferredWidth: 18
                Layout.preferredHeight: 18
                fillMode: Image.PreserveAspectFit
                // Decode at 2x so PNG icons stay sharp on HiDPI displays
                sourceSize.width: 36
                sourceSize.height: 36
                source: modelData.icon
                asynchronous: true
              }

              Text {
                text: modelData.cls
                color: win.fg
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                Layout.preferredWidth: 220
                elide: Text.ElideRight
              }

              Text {
                text: modelData.name
                color: win.dim
                font.family: Style.font.family
                font.pixelSize: Style.font.body - 2
                elide: Text.ElideRight
                Layout.fillWidth: true
              }

              Text {
                text: modelData.running ? "●" : ""
                color: win.fg
                font.pixelSize: Style.font.body - 4
              }
            }

            MouseArea {
              id: pickerHover
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: win.pickApp(modelData.cls)
            }
          }
        }

        Text {
          text: win.pickerRunningOnly ? "No running windows found" : "No matching apps"
          visible: win.pickerItems.length === 0
          color: win.dim
          font.family: Style.font.family
          font.pixelSize: Style.font.body
        }
      }
    }
  }
}
