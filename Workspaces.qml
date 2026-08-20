import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.Commons
import qs.Ui

// Named workspaces, split per monitor. Definitions live in
// ~/.config/hypr/workspaces.conf (id|key|monitor|label|apps), shared with
// monitors.lua and bindings.lua (see README.md).
// Right-click any workspace to open the editor; the jump hotkey opens the
// fuzzy workspace/window finder.
BarWidget {
  id: root
  moduleName: "mangoleaf.workspace-manager"

  property var rows: []
  property string renameKey: ""
  property string jumpKey: ""
  property string editorKey: ""
  property bool centerBar: false
  property string centerMoved: ""

  // ponytail: 3 is just a sane starting point for how many app icons fit
  // beside a name; the setting is what matters, not this number.
  readonly property int defaultIconCount: 3
  property int iconCount: defaultIconCount
  property string barStyle: "plain"

  // Hyprland has no workspace 0, so a numpad user who thinks of their first
  // workspace as 0 runs permanently one ahead of the ids. This only tells the
  // plugin how they count, so generated names and displayed numbers agree
  // with the numpad rather than with Hyprland.
  property bool countFromZero: false

  function displayNumber(id) {
    return root.countFromZero ? id - 1 : id
  }

  // Display-only: the stored label keeps its space, so the rename popup can
  // still split base from suffix on ": ". Only the first separator is
  // touched — a name that happens to contain another one keeps it.
  property bool compactNames: false

  // The number is its own field, not part of the name, so it can be hidden
  // without editing every workspace. On by default.
  property bool showNumbers: true

  // What sits between the number and the name. A colon by convention, but
  // it is only punctuation, so it is the user's to pick.
  property string delimiter: ":"

  // Prefix and name are stored apart; this is the only place they are joined.
  function composeLabel(prefix, name) {
    var p = String(prefix === undefined ? "" : prefix)
    var n = String(name === undefined ? "" : name)
    if (!root.showNumbers) return n !== "" ? n : p
    if (p === "") return n
    if (n === "") return p
    return root.compactNames ? p + root.delimiter + n : p + root.delimiter + " " + n
  }

  function rowById(id) {
    for (var i = 0; i < root.rows.length; i++) if (root.rows[i].id === id) return root.rows[i]
    return null
  }

  function compactLabel(label) {
    var text = String(label)
    var at = text.indexOf(":")
    if (at === -1) return text

    // Normalise rather than only strip, so the setting works whichever way
    // the name was typed: a stored "0:Test" still shows as "0: Test" when
    // spacing is on, and a stored "0: Test" still compacts when it is off.
    var head = text.substring(0, at + 1)
    var tail = text.substring(at + 1).replace(/^ +/, "")
    if (tail === "") return head
    return root.compactNames ? head + tail : head + " " + tail
  }

  // Workspace colours. Blank means "follow the theme", which is the default
  // for everything except the unfocused-monitor marker — the theme has no
  // opinion about that state, so it needs a colour of its own.
  readonly property string defaultUnfocusedColor: "#ff9e3f"
  property string colorActive: ""
  property string colorUnfocused: ""
  property string colorOccupied: ""
  property string colorEmpty: ""
  readonly property string confPath: Quickshell.env("HOME") + "/.config/hypr/workspaces.conf"

  // Lines we do not understand — comments, blank lines, keys from a future
  // version — kept verbatim so rewriting the file never destroys them. The
  // config is documented as hand-editable, so it is not ours alone to own.
  property var confHeader: []
  property var confFooter: []

  readonly property string screenName: {
    var win = QsWindow.window
    return win && win.screen ? win.screen.name : ""
  }

  function loadConf(t) {
    var out = []
    var settings = {
      rename: "", jump: "", editor: "", center: "", centermoved: "", icons: "", style: "", base: "", compact: "", number: "", delim: "",
      coloractive: "", colorunfocused: "", coloroccupied: "", colorempty: ""
    }
    var header = []
    var footer = []
    var seenKnown = false

    var lines = (t || "").split("\n")
    // A file ending in a newline yields a trailing "" that is not a blank
    // line the user wrote; keeping it would grow one on every save.
    if (lines.length > 0 && lines[lines.length - 1] === "") lines.pop()

    for (var i = 0; i < lines.length; i++) {
      var p = lines[i].split("|")
      if (p.length >= 4 && /^\d+$/.test(p[0])) {
        var name = p[3]
        var prefix = p.length >= 6 ? p[5] : null

        // Migration: before the split, field 4 held prefix and name together
        // as "0: MLStudios". A bare "4" or "LA" is a prefix with no name.
        if (prefix === null) {
          var at = name.indexOf(":")
          if (at === -1) { prefix = name; name = "" }
          else { prefix = name.substring(0, at); name = name.substring(at + 1).replace(/^ +/, "") }
        }

        out.push({ id: parseInt(p[0]), key: p[1], monitor: p[2], label: name, apps: p.length >= 5 ? p[4] : "", prefix: prefix })
        seenKnown = true
      } else if (p.length >= 2 && settings[p[0]] !== undefined) {
        settings[p[0]] = p.slice(1).join("|")
        seenKnown = true
      } else if (seenKnown) {
        footer.push(lines[i])
      } else {
        header.push(lines[i])
      }
    }

    root.confHeader = header
    root.confFooter = footer
    root.rows = out
    // Defaults matching hypr/workspace-binds.lua, so an untouched install has
    // working hotkeys and the editor shows the ones that are actually bound.
    root.renameKey = settings.rename === "" ? "SUPER + SHIFT + F2" : settings.rename
    root.jumpKey = settings.jump === "" ? "SUPER + SHIFT + F3" : settings.jump
    root.editorKey = settings.editor === "" ? "SUPER + SHIFT + F4" : settings.editor
    root.centerBar = settings.center === "true"
    root.centerMoved = settings.centermoved
    root.iconCount = settings.icons === "" ? root.defaultIconCount : parseInt(settings.icons)
    root.barStyle = settings.style === "" ? "plain" : settings.style
    root.countFromZero = settings.base === "0"
    root.compactNames = settings.compact === "true"
    root.showNumbers = settings.number !== "false"
    // One character. A longer value in a hand-edited config is trimmed to
    // its first rather than refused, and an empty one falls back to the
    // default so the number never runs straight into the name.
    root.delimiter = settings.delim === "" ? ":" : settings.delim.charAt(0)
    root.colorActive = settings.coloractive
    root.colorUnfocused = settings.colorunfocused
    root.colorOccupied = settings.coloroccupied
    root.colorEmpty = settings.colorempty
  }

  // Everything that knows the file format lives here, so the editor and the
  // rename popup can both write without duplicating it.
  function currentSettings() {
    return {
      rename: root.renameKey,
      jump: root.jumpKey,
      editor: root.editorKey,
      center: root.centerBar,
      centermoved: root.centerMoved,
      icons: root.iconCount,
      style: root.barStyle,
      base: root.countFromZero ? "0" : "1",
      compact: root.compactNames,
      number: root.showNumbers,
      delim: root.delimiter,
      coloractive: root.colorActive,
      colorunfocused: root.colorUnfocused,
      coloroccupied: root.colorOccupied,
      colorempty: root.colorEmpty
    }
  }

  function buildConf(rows, s) {
    var lines = root.confHeader.slice()
    if (s.rename !== "") lines.push("rename|" + s.rename)
    if (s.jump !== "") lines.push("jump|" + s.jump)
    if (s.editor !== "") lines.push("editor|" + s.editor)
    lines.push("center|" + (s.center ? "true" : "false"))
    if (s.centermoved !== "") lines.push("centermoved|" + s.centermoved)
    lines.push("icons|" + s.icons)
    lines.push("style|" + s.style)
    lines.push("base|" + s.base)
    lines.push("compact|" + (s.compact ? "true" : "false"))
    lines.push("number|" + (s.number ? "true" : "false"))
    lines.push("delim|" + s.delim)
    if (s.coloractive !== "") lines.push("coloractive|" + s.coloractive)
    if (s.colorunfocused !== "") lines.push("colorunfocused|" + s.colorunfocused)
    if (s.coloroccupied !== "") lines.push("coloroccupied|" + s.coloroccupied)
    if (s.colorempty !== "") lines.push("colorempty|" + s.colorempty)
    for (var i = 0; i < rows.length; i++)
      lines.push(rows[i].id + "|" + rows[i].key + "|" + rows[i].monitor + "|" + rows[i].label
        + "|" + rows[i].apps + "|" + (rows[i].prefix === undefined ? "" : rows[i].prefix))
    return lines.concat(root.confFooter).join("\n") + "\n"
  }

  // Used by the rename popup, which changes one workspace's name and nothing
  // else. Every other field — the number above all — is carried through
  // verbatim; rebuilding a row without its prefix would blank the numbers of
  // all 26 workspaces on a single rename.
  function writeName(id, name) {
    var rows = []
    for (var i = 0; i < root.rows.length; i++) {
      var r = root.rows[i]
      rows.push({
        id: r.id,
        key: r.key,
        monitor: r.monitor,
        label: r.id === id ? name : r.label,
        apps: r.apps,
        prefix: r.prefix
      })
    }
    root.saveConf(root.buildConf(rows, root.currentSettings()))
  }

  function saveConf(text) {
    confFile.setText(text)
    // Re-read our own write immediately. The file watcher does not
    // necessarily fire for a write we made ourselves, and anything that
    // reopens before it would otherwise see pre-write state — which is how
    // renaming twice in a row used to show the first name again.
    root.loadConf(text)
    applyTimer.restart()
  }

  // Fallback home for an unpinned workspace Hyprland has not placed yet, so
  // it shows on exactly one bar rather than none or all of them.
  readonly property bool isFirstScreen: {
    var screens = Quickshell.screens
    return screens.length > 0 && String(screens[0].name || "") === root.screenName
  }

  // This bar shows the workspaces pinned to its monitor, plus any unpinned
  // ones that currently live here — so an unpinned workspace appears once,
  // on whichever bar it is actually on, and follows as it moves.
  function workspaceIds() {
    // Nothing configured yet: fall back to whatever Hyprland already has, so
    // a fresh install still draws something and right-click can reach the
    // editor. Without this the widget would be empty and unreachable.
    if (root.rows.length === 0) {
      var live = []
      var all = Hyprland.workspaces.values
      for (var w = 0; w < all.length; w++) {
        var ws = all[w]
        if (ws.id <= 0) continue
        var where = ws.monitor ? String(ws.monitor.name || "") : ""
        if (where === root.screenName || (where === "" && root.isFirstScreen)) live.push(ws.id)
      }
      live.sort(function(a, b) { return a - b })
      return live
    }

    var ids = []
    for (var i = 0; i < root.rows.length; i++) {
      var row = root.rows[i]
      if (row.monitor === root.screenName) {
        ids.push(row.id)
        continue
      }
      if (row.monitor !== "") continue

      var live = root.workspaceById(row.id)
      var on = live && live.monitor ? String(live.monitor.name || "") : ""
      if (on === root.screenName || (on === "" && root.isFirstScreen)) ids.push(row.id)
    }
    ids.sort(function(a, b) { return a - b })
    return ids
  }

  function workspaceById(id) {
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      if (values[i].id === id) return values[i]
    }

    return null
  }

  // The config is the authority on names — a workspace that does not exist
  // yet still has one, and that is what a freshly added workspace shows.
  function labelFor(id) {
    var row = root.rowById(id)
    if (row) {
      var composed = root.composeLabel(row.prefix, row.label)
      if (composed !== "") return composed
    }

    var live = root.workspaceById(id)
    return root.compactLabel(live && live.name !== "" ? live.name : String(id))
  }

  // App icons for the windows on a workspace, one per distinct app so three
  // terminals do not eat the whole allowance.
  property var iconCache: ({})

  function classIcon(cls) {
    if (cls === "") return ""
    if (root.iconCache[cls] !== undefined) return root.iconCache[cls]
    var out = ""
    var entry = DesktopEntries.heuristicLookup(cls)
    if (entry && entry.icon) {
      var v = String(entry.icon)
      if (v.indexOf("file://") === 0 || v.indexOf("image://") === 0) out = v
      else if (v.charAt(0) === "/") out = "file://" + v
      else out = Quickshell.iconPath(v, true)
    }
    root.iconCache[cls] = out
    return out
  }

  function iconsFor(id) {
    if (root.iconCount <= 0) return []
    var ws = root.workspaceById(id)
    if (!ws || !ws.toplevels) return []

    var seen = {}
    var out = []
    var values = ws.toplevels.values
    for (var i = 0; i < values.length && out.length < root.iconCount; i++) {
      var ipc = values[i].lastIpcObject || ({})
      var cls = String(ipc["class"] || ipc.initialClass || "")
      if (cls === "" || seen[cls]) continue
      seen[cls] = true
      var src = root.classIcon(cls)
      if (src !== "") out.push(src)
    }
    return out
  }

  function focusWorkspace(id) {
    if (!root.bar) return
    root.bar.run("hyprctl dispatch " + Util.shellQuote("hl.dsp.focus({ workspace = \"" + id + "\" })"))
  }

  function openEditor() {
    if (editorLoader.active && editorLoader.item) editorLoader.item.openNow()
    else editorLoader.active = true
  }

  function openRename() {
    if (renameLoader.active && renameLoader.item) renameLoader.item.openNow()
    else renameLoader.active = true
  }

  // shell.summon/hide/toggle contract (Bar.findPanelWidget) — routes the
  // "jump" hotkey (omarchy-shell shell toggle mangoleaf.workspace-manager) to the
  // fuzzy finder.
  readonly property bool opened: jumpLoader.item ? jumpLoader.item.visible === true : false

  function open() {
    if (jumpLoader.active && jumpLoader.item) jumpLoader.item.openNow()
    else jumpLoader.active = true
  }

  function close() {
    if (jumpLoader.item) jumpLoader.item.close()
  }

  // Existing binds, read once when the editor opens, for two purposes:
  // warning about a hotkey that is already taken, and importing the stock
  // workspace keys. Hyprland reports its own generated workspace binds with
  // no key and no keycode, so those cannot be read back — the stock scheme
  // is reconstructed instead, below.
  property var existingBinds: ({})

  Process {
    id: readBinds
    command: ["hyprctl", "binds", "-j"]
    stdout: StdioCollector {
      id: bindsOut
      onStreamFinished: root.parseBinds(bindsOut.text)
    }
  }

  function parseBinds(text) {
    var map = {}
    try {
      var all = JSON.parse(text)
      for (var i = 0; i < all.length; i++) {
        var b = all[i]
        if (!b.key || b.key === "") continue
        // A combination can carry several bindings — ours and whatever it is
        // taking over. Keep them all; a single slot would let ours shadow the
        // one worth warning about.
        var slot = b.modmask + "|" + String(b.key).toUpperCase()
        if (!map[slot]) map[slot] = []
        map[slot].push(String(b.description || "a binding"))
      }
    } catch (e) {}
    root.existingBinds = map
  }

  function refreshBinds() { readBinds.running = true }

  // Read once at startup as well as on open: the read is asynchronous, and a
  // capture completed moments after opening would otherwise be checked
  // against an empty list and reported as free.
  Component.onCompleted: root.refreshBinds()

  // "SUPER + SHIFT + F2" -> the modmask Hyprland reports, so a captured
  // combination can be compared against what is already bound.
  function modmaskFor(keys) {
    var parts = String(keys).toUpperCase().split("+")
    var mask = 0
    for (var i = 0; i < parts.length; i++) {
      var p = parts[i].trim()
      if (p === "SHIFT") mask += 1
      else if (p === "CTRL" || p === "CONTROL") mask += 4
      else if (p === "ALT") mask += 8
      else if (p === "SUPER" || p === "META") mask += 64
    }
    return mask
  }

  function bareKeyOf(keys) {
    var parts = String(keys).split("+")
    return parts[parts.length - 1].trim().toUpperCase()
  }

  // What a combination is already bound to, or "" if it is free. Our own
  // bindings do not count: rebinding onto one of them is not a collision.
  // Bindings this plugin generates, matched exactly rather than by looking
  // for the word "workspace" anywhere in a description.
  function isOwnBinding(desc) {
    return desc.indexOf("Switch to workspace") === 0
        || desc.indexOf("Move to workspace") === 0
        || desc.indexOf("Move silently to workspace") === 0
        || desc === "Rename workspace"
        || desc === "Jump to workspace"
        || desc === "Workspace editor"
  }

  function bindingConflict(keys) {
    if (keys === "") return ""
    var hits = root.existingBinds[root.modmaskFor(keys) + "|" + root.bareKeyOf(keys)]
    if (!hits) return ""
    for (var i = 0; i < hits.length; i++)
      if (!root.isOwnBinding(hits[i])) return hits[i]
    return ""
  }

  // Everything Hyprland already has, as editor rows. Used on a fresh install
  // so an existing setup is adopted rather than retyped.
  function importableRows() {
    var out = []
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      var ws = values[i]
      if (ws.id <= 0) continue

      var name = String(ws.name || "")
      // A default Hyprland workspace is named after its own id; that is a
      // number, not a name.
      var prefix = name === "" ? String(ws.id) : name
      var label = ""
      var at = name.indexOf(":")
      if (at !== -1) { prefix = name.substring(0, at); label = name.substring(at + 1).replace(/^ +/, "") }
      else if (name !== String(ws.id) && name !== "") { prefix = String(ws.id); label = name }

      // Omarchy binds SUPER + code:10..19 to workspaces 1..10. Those binds
      // report no key through hyprctl, so reconstruct rather than read.
      var key = (ws.id >= 1 && ws.id <= 10) ? "code:" + (ws.id + 9) : ""

      out.push({
        id: ws.id,
        key: key,
        monitor: ws.monitor ? String(ws.monitor.name || "") : "",
        label: label,
        apps: "",
        prefix: prefix
      })
    }
    out.sort(function(a, b) { return a.id - b.id })
    return out
  }

  // Wiring Hyprland up used to mean pasting ~120 lines of Lua into two files
  // by hand. The Lua ships with the plugin instead, and each file needs one
  // line that loads it — which the editor can add, so nobody has to paste
  // anything they cannot read.
  readonly property string hyprMarker: "-- >>> omarchy-workspace-manager"
  readonly property string pluginDir:
    Quickshell.env("HOME") + "/.config/omarchy/plugins/mangoleaf.workspace-manager/"
  readonly property string pluginHyprDir: root.pluginDir + "hypr/"

  // Read from the manifest rather than written twice: a version in two
  // places is a version that will disagree with itself.
  property string pluginVersion: ""

  FileView {
    path: root.pluginDir + "manifest.json"
    watchChanges: false
    printErrors: false
    onLoaded: {
      try { root.pluginVersion = String(JSON.parse(text()).version || "") } catch (e) {}
    }
  }

  FileView {
    id: monitorsFile
    path: Quickshell.env("HOME") + "/.config/hypr/monitors.lua"
    watchChanges: true
    printErrors: false
  }

  FileView {
    id: bindingsFile
    path: Quickshell.env("HOME") + "/.config/hypr/bindings.lua"
    watchChanges: true
    printErrors: false
  }

  function hyprBlock(file) {
    return "\n" + root.hyprMarker + " (managed block — safe to remove)\n"
      + 'dofile(os.getenv("HOME") .. "/.config/omarchy/plugins/mangoleaf.workspace-manager/hypr/'
      + file + '")\n'
      + "-- <<< omarchy-workspace-manager\n"
  }

  // Counts as installed however it got there: someone who pasted the Lua by
  // hand from an older README has a working setup, and must not be offered a
  // second copy of it.
  function hyprFileConfigured(view) {
    var text = view.text()
    if (text.indexOf(root.hyprMarker) !== -1) return true
    // Someone who pasted the Lua from an older README has a working setup and
    // must not be offered a second copy. Look for the code that reads the
    // config, not a mention of it — every one of these files carries a
    // comment naming workspaces.conf.
    return text.indexOf("io.open") !== -1 && text.indexOf("workspaces.conf") !== -1
  }

  readonly property bool hyprConfigInstalled:
    root.confRevision >= 0
    && root.hyprFileConfigured(monitorsFile)
    && root.hyprFileConfigured(bindingsFile)

  // Bumped when either file changes, so the editor's banner re-evaluates.
  property int confRevision: 0
  Connections { target: monitorsFile; function onFileChanged() { root.confRevision++ } }
  Connections { target: bindingsFile; function onFileChanged() { root.confRevision++ } }

  Process {
    id: hyprBackup
    command: ["sh", "-c",
      'for f in "$HOME/.config/hypr/monitors.lua" "$HOME/.config/hypr/bindings.lua"; do '
      + '[ -f "$f" ] && cp "$f" "$f.bak.$(date +%s)"; done']
    onExited: {
      if (!root.hyprFileConfigured(monitorsFile))
        monitorsFile.setText(monitorsFile.text() + root.hyprBlock("workspace-rules.lua"))
      if (!root.hyprFileConfigured(bindingsFile))
        bindingsFile.setText(bindingsFile.text() + root.hyprBlock("workspace-binds.lua"))
      root.confRevision++
      applyTimer.restart()
    }
  }

  // Back up first, then append. Never touches either file unless asked.
  function installHyprConfig() {
    hyprBackup.running = true
  }

  // Hyprland matches its own keybinds before a client ever sees the keys, so
  // arming a capture box is not enough: pressing an already-bound combination
  // fires that binding instead of being captured. The submap that suspends
  // them is defined in hypr/workspace-binds.lua — a submap registered at
  // runtime does not survive a reload, and this plugin reloads on save.
  readonly property string captureSubmap: "omarchy-workspace-manager-capture"

  function beginKeyCapture() {
    Hyprland.dispatch('hl.dsp.submap("' + root.captureSubmap + '")')
  }

  function endKeyCapture() {
    Hyprland.dispatch('hl.dsp.submap("reset")')
  }

  // The editor hotkey routes here. A bar widget exists per monitor and IPC
  // reaches exactly one of them, which is what a single modal editor wants.
  IpcHandler {
    target: "mangoleaf.workspace-manager"

    function editor(): void {
      root.openEditor()
    }

    function rename(): void {
      root.openRename()
    }
  }

  // Bar layout lives in the shell's own config, so centering the workspaces
  // means editing shell.json. Everything else in that file is preserved.
  FileView {
    id: shellFile
    path: Quickshell.env("HOME") + "/.config/omarchy/shell.json"
    watchChanges: true
    printErrors: false
  }

  property string pendingShellJson: ""

  // Writing shell.json makes the shell rebuild the bar, which tears down this
  // widget — so let the caller's own config write land first.
  Timer {
    id: shellWriteTimer
    interval: 0
    onTriggered: {
      if (root.pendingShellJson === "") return
      shellFile.setText(root.pendingShellJson)
      root.pendingShellJson = ""
    }
  }

  // Move this widget into the bar's center section, pushing whatever was
  // centered over to the right; or undo that, putting the displaced widgets
  // back. Returns the ids it displaced, for the caller to persist.
  function setBarCentered(enabled, movedCsv) {
    var cfg
    try { cfg = JSON.parse(shellFile.text()) } catch (e) { return movedCsv }
    if (!cfg || !cfg.bar || !cfg.bar.layout) return movedCsv

    var layout = cfg.bar.layout
    layout.left = layout.left || []
    layout.center = layout.center || []
    layout.right = layout.right || []

    var me = root.moduleName
    function without(list, id) {
      return list.filter(function(entry) { return entry.id !== id })
    }
    function find(id) {
      var all = layout.left.concat(layout.center, layout.right)
      for (var i = 0; i < all.length; i++) if (all[i].id === id) return all[i]
      return { id: id }
    }

    var self = find(me)
    var result = movedCsv

    if (enabled) {
      var displaced = without(layout.center, me)
      layout.left = without(layout.left, me)
      layout.right = without(layout.right, me).concat(displaced)
      layout.center = [self]
      cfg.bar.centerAnchor = me
      result = displaced.map(function(entry) { return entry.id }).join(",")
    } else {
      var ids = movedCsv === "" ? [] : movedCsv.split(",")
      var back = []
      for (var i = 0; i < ids.length; i++) {
        back.push(find(ids[i]))
        layout.right = without(layout.right, ids[i])
        layout.center = without(layout.center, ids[i])
      }
      layout.center = back
      layout.left = without(layout.left, me).concat([self])
      layout.right = without(layout.right, me)
      cfg.bar.centerAnchor = back.length > 0
        ? (ids.indexOf("omarchy.clock") !== -1 ? "omarchy.clock" : back[0].id)
        : ""
      result = ""
    }

    root.pendingShellJson = JSON.stringify(cfg, null, 2) + "\n"
    shellWriteTimer.restart()
    return result
  }

  FileView {
    id: confFile
    path: root.confPath
    watchChanges: true
    printErrors: false
    // reload() is asynchronous — calling text() straight after it returns the
    // PREVIOUS contents, which would overwrite fresh rows with stale ones.
    // Let onLoaded do the parsing once the re-read has actually finished.
    onLoaded: root.loadConf(text())
    onFileChanged: reload()
    onLoadFailed: root.loadConf("")
  }

  // Let the setText write land before hyprctl re-reads the file, then pick up
  // the new workspace rules and bindings.
  Timer {
    id: applyTimer
    interval: 400
    onTriggered: reloadProc.running = true
  }

  Process {
    id: reloadProc
    command: ["hyprctl", "reload"]
    onExited: root.applyWorkspaceState()
  }

  // Hyprland reloads rules but does not retroactively rename or re-home the
  // workspaces it already has, so push those through after the reload.
  function applyWorkspaceState() {
    for (var i = 0; i < root.rows.length; i++) {
      var row = root.rows[i]
      var name = root.composeLabel(row.prefix, row.label).replace(/"/g, '\\"')
      Hyprland.dispatch('hl.dsp.workspace.rename({ workspace = "' + row.id + '", name = "' + name + '" })')
      if (row.monitor !== "")
        Hyprland.dispatch('hl.dsp.workspace.move({ workspace = "' + row.id + '", monitor = "' + row.monitor + '" })')
    }
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
    id: renameLoader
    active: false
    source: Qt.resolvedUrl("Rename.qml")
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

      Item {
        id: chip
        required property int modelData

        readonly property var workspace: root.workspaceById(modelData)
        readonly property bool occupied: workspace !== null && workspace.toplevels.values.length > 0

        // Active on the focused monitor vs active on some other monitor —
        // the second still deserves a marker, just a different one.
        readonly property bool focused: Hyprland.focusedWorkspace !== null && Hyprland.focusedWorkspace.id === modelData
        readonly property bool activeElsewhere: !focused && workspace !== null && workspace.active === true

        readonly property var icons: root.iconsFor(modelData)
        readonly property color accent: root.bar ? root.bar.urgent : Color.urgent
        readonly property color baseForeground: root.bar ? root.bar.barForeground : Color.foreground

        readonly property color tint: focused
          ? (root.colorActive !== "" ? root.colorActive : accent)
          : activeElsewhere
            ? (root.colorUnfocused !== "" ? root.colorUnfocused : root.defaultUnfocusedColor)
            : occupied
              ? (root.colorOccupied !== "" ? root.colorOccupied : baseForeground)
              : (root.colorEmpty !== "" ? root.colorEmpty : baseForeground)

        implicitWidth: body.implicitWidth + Style.spaceReal(8)
        implicitHeight: root.barSize

        // An empty workspace is dimmed only while it is taking the theme's
        // colour — a colour chosen for it is meant to be seen as chosen.
        opacity: occupied || focused || activeElsewhere || root.colorEmpty !== "" ? 1 : 0.5

        Behavior on opacity {
          NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
        }

        // "pill" fills behind the marked workspace, "underline" rules under
        // it; "plain" is the stock look, colour only.
        Rectangle {
          visible: root.barStyle === "pill" && (chip.focused || chip.activeElsewhere)
          anchors.fill: parent
          anchors.topMargin: Style.spaceReal(3)
          anchors.bottomMargin: Style.spaceReal(3)
          radius: height / 2
          color: Qt.rgba(chip.tint.r, chip.tint.g, chip.tint.b, 0.18)
        }

        Rectangle {
          visible: root.barStyle === "underline" && (chip.focused || chip.activeElsewhere)
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          anchors.bottomMargin: Style.spaceReal(3)
          anchors.leftMargin: Style.spaceReal(3)
          anchors.rightMargin: Style.spaceReal(3)
          height: Math.max(1, Style.spaceReal(2))
          radius: height / 2
          color: chip.tint
        }

        Row {
          id: body
          anchors.centerIn: parent
          spacing: Style.spaceReal(4)

          Repeater {
            model: chip.icons

            Image {
              required property string modelData
              anchors.verticalCenter: parent.verticalCenter
              width: Style.font.body
              height: Style.font.body
              fillMode: Image.PreserveAspectFit
              // Decode at 2x so small icons stay sharp on HiDPI outputs.
              sourceSize.width: width * 2
              sourceSize.height: height * 2
              source: modelData
              asynchronous: true
            }
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.labelFor(chip.modelData)
            color: chip.tint
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.body
            renderType: Text.NativeRendering

            Behavior on color {
              ColorAnimation { duration: 160 }
            }
          }
        }

        MouseArea {
          anchors.fill: parent
          acceptedButtons: Qt.LeftButton | Qt.RightButton
          cursorShape: Qt.PointingHandCursor
          onClicked: function(mouse) {
            if (mouse.button === Qt.RightButton) root.openEditor()
            else root.focusWorkspace(chip.modelData)
          }
        }
      }
    }
  }
}
