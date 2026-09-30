// ============================================================================
// Workspaces.qml — annotated Omarchy Workspace Manager replacement
// ============================================================================
// This file preserves the plugin's original workspace/editor/pinning behavior,
// while replacing the app-icon discovery path with a more robust implementation.
//
// ICON FIX SUMMARY
//   1. Uses `hyprctl clients -j` to obtain the same window classes Hyprland
//      reports in the terminal.
//   2. Matches those classes using DesktopEntries.heuristicLookup(), with an
//      explicit StartupWMClass / desktop-entry-id fallback.
//   3. Never caches failed icon lookups, so startup races can recover.
//   4. Refreshes workspace icon data after window lifecycle/movement events.
//   5. Uses Quickshell.iconPath(icon) without the strict `check=true` overload.
//
// The comments throughout the file describe the purpose of the declarations,
// functions, processes, timers, connections, loaders, and rendering blocks.
//
// Replace:
//   ~/.config/omarchy/plugins/mangoleaf.workspace-manager/Workspaces.qml
//
// Then restart the shell:
//   omarchy-restart-shell
// ============================================================================

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

  // Parsed workspace definitions from ~/.config/hypr/workspaces.conf.
  property var rows: []

  // Key combination that opens the workspace rename popup.
  property string renameKey: ""

  // Key combination that opens the fuzzy workspace/window jump interface.
  property string jumpKey: ""

  // Key combination that opens the full workspace-manager editor.
  property string editorKey: ""

  // Whether this plugin is allowed to occupy the bar's center section.
  property bool centerBar: false

  // Comma-separated widget ids displaced from the center when centerBar is on.
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

  // Finds one configured workspace row by numeric Hyprland workspace id.
  // Returns null when the id has no configured row.
  function rowById(id) {
    for (var i = 0; i < root.rows.length; i++) if (root.rows[i].id === id) return root.rows[i]
    return null
  }

  // Normalizes an already-composed label according to compactNames, preserving
  // the prefix before the first colon while adding/removing one display space.
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
  // Optional override color for a non-focused workspace containing windows.
  property string colorOccupied: ""

  // Optional override color for an empty, inactive workspace.
  property string colorEmpty: ""

  // Absolute path of the human-editable workspace-manager configuration file.
  readonly property string confPath: Quickshell.env("HOME") + "/.config/hypr/workspaces.conf"

  // Lines we do not understand — comments, blank lines, keys from a future
  // version — kept verbatim so rewriting the file never destroys them. The
  // config is documented as hand-editable, so it is not ours alone to own.
  property var confHeader: []
  property var confFooter: []

  // Name of the output/monitor that owns this particular bar-widget instance.
  // Omarchy creates one bar instance per screen, so this is used for filtering.
  readonly property string screenName: {
    var win = QsWindow.window
    return win && win.screen ? win.screen.name : ""
  }

  // Parses the pipe-delimited workspaces.conf file into workspace rows and
  // settings properties while preserving unknown lines for round-trip editing.
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

  // Serializes workspace rows plus a settings object back to workspaces.conf.
  // Unknown header/footer lines are retained so hand edits are not destroyed.
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

  // Writes a complete configuration string, immediately updates in-memory
  // state, and schedules a Hyprland reload so rules/bindings take effect.
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
    // Config order, not id order: the editor's list is the running order, so
    // dragging a row there is what moves a workspace along the bar. Sorting
    // here would quietly undo every reorder.
    return ids
  }

  // Returns the live Quickshell HyprlandWorkspace object matching an id, or
  // null when that workspace does not currently exist.
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

  // Dots mode keeps ordinary numbered workspaces compact while preserving a
  // short visible tag for named workspaces. The full composed name remains in
  // the tooltip, so a label such as "G" can stand for "Gaming" without
  // consuming the width of ten numbered workspaces.
  function isNamed(id) {
    var row = root.rowById(id)
    return row !== null && String(row.label || "") !== ""
  }

  // Returns the shortest human-readable token for a named workspace, favoring
  // its configured numeric/text prefix over the longer workspace name.
  function compactNameFor(id) {
    var row = root.rowById(id)
    if (!row) return ""
    var prefix = String(row.prefix === undefined ? "" : row.prefix)
    return prefix !== "" ? prefix : String(row.label || "")
  }

  // ---------------------------------------------------------------------------
  // Application-icon support
  // ---------------------------------------------------------------------------
  // The upstream plugin originally derived a class from HyprlandToplevel's
  // lastIpcObject and immediately cached both successful and failed desktop
  // entry lookups. On some Omarchy/Quickshell builds that leaves the bar with
  // permanently empty icons. The declarations and functions below deliberately
  // use `hyprctl clients -j` as the authoritative window/class source, retry
  // failed desktop-entry lookups, and invalidate bindings whenever either the
  // window list or desktop-entry model changes.

  // Caches only SUCCESSFUL class -> image-source resolutions. Failed lookups
  // are intentionally not cached, because DesktopEntries can finish loading
  // after this widget's first render.
  property var iconCache: ({})

  // Omarchy itself does not rely solely on Qt's icon-theme cache. The shell can
  // start before application icons are indexed, and Qt may never rescan them.
  // Mirror Omarchy's AppLibrary fallback: build a map from icon basename
  // ("firefox") to a real SVG/PNG file path on disk.
  property var iconIndex: ({})
  property var pendingIconIndex: ({})

  // Maps a numeric Hyprland workspace id to the distinct application classes
  // currently present on that workspace. Example: { "1": ["firefox", ...] }.
  property var workspaceClasses: ({})

  // Revision counter used only to make QML bindings reactive. iconsFor() reads
  // this property, so incrementing it forces each workspace chip to recalculate
  // its icon list even when the underlying JavaScript maps changed in place.
  property int iconRevision: 0

  // Clears resolved icons and bumps the revision so all workspace icon bindings
  // retry their desktop-entry and icon-theme lookups.
  function resetIconCache() {
    root.iconCache = ({})
    root.iconRevision++
  }

  // Parses `hyprctl clients -j` into workspaceClasses. Using hyprctl here avoids
  // depending on lastIpcObject refresh timing inside Quickshell's Hyprland API.
  function parseClientWindows(text) {
    var map = {}

    try {
      var clients = JSON.parse(text)

      for (var i = 0; i < clients.length; i++) {
        var client = clients[i]
        var workspace = client.workspace || ({})
        var id = Number(workspace.id || 0)

        // Hyprland uses positive ids for ordinary workspaces. Ignore special
        // workspaces and malformed records.
        if (id <= 0) continue

        var cls = String(client["class"] || client.initialClass || "")
        if (cls === "") continue

        var key = String(id)
        if (!map[key]) map[key] = []

        // Keep one icon per distinct application class on each workspace.
        if (map[key].indexOf(cls) === -1) map[key].push(cls)
      }
    } catch (e) {
      console.warn("workspace-manager: failed to parse hyprctl clients:", e)
    }

    root.workspaceClasses = map
    root.iconRevision++
  }

  // Starts a fresh hyprctl client query unless one is already in progress.
  // Window events are debounced by clientRefreshTimer, so overlapping calls are
  // uncommon and safely ignored.
  function refreshClientWindows() {
    if (!readClients.running) readClients.running = true
  }

  // Runs Hyprland's JSON client query. Its output contains the exact `class`
  // strings that you already verified with `hyprctl clients -j`.
  Process {
    id: readClients
    command: ["hyprctl", "clients", "-j"]

    stdout: StdioCollector {
      id: clientsOut
      onStreamFinished: root.parseClientWindows(clientsOut.text)
    }
  }

  // Debounces bursts of Hyprland events (opening/moving/closing windows) so the
  // plugin does not spawn several identical hyprctl processes at once.
  Timer {
    id: clientRefreshTimer
    interval: 120
    repeat: false
    onTriggered: root.refreshClientWindows()
  }

  // DesktopEntries.applications is an ObjectModel. Its `values` property
  // changes when Quickshell discovers/reloads .desktop entries. Clearing the
  // successful-icon cache here also lets a previously unavailable icon resolve.
  Connections {
    target: DesktopEntries.applications

    function onValuesChanged() {
      root.resetIconCache()
      clientRefreshTimer.restart()
      iconIndexDebounce.restart()
    }
  }

  // Builds the same filesystem icon index used by Omarchy's own AppLibrary.
  // Only application/device icon directories are scanned, preferring SVG over
  // PNG because the first path stored for a basename wins.
  function iconIndexScanCommand() {
    return [
      'dirs="$HOME/.icons $HOME/.local/share/icons";',
      'IFS=":"; for d in ${XDG_DATA_DIRS:-/usr/local/share:/usr/share}; do dirs="$dirs $d/icons"; done; unset IFS;',
      'for ext in svg png; do',
      '  for base in $dirs; do',
      '    [[ -d $base ]] && find "$base" \\( -path "*/apps/*" -o -path "*/devices/*" \\) -name "*.$ext" 2>/dev/null;',
      '  done;',
      '  find /usr/share/pixmaps -maxdepth 1 -name "*.$ext" 2>/dev/null;',
      'done'
    ].join(" ")
  }

  // Adds one discovered icon file to pendingIconIndex. The extension is removed
  // so DesktopEntry.Icon values such as "firefox" can be looked up directly.
  function indexIconLine(path) {
    var value = String(path || "").trim()
    if (value.length === 0) return

    var slash = value.lastIndexOf("/")
    var file = slash >= 0 ? value.slice(slash + 1) : value
    var dot = file.lastIndexOf(".")
    var name = dot > 0 ? file.slice(0, dot) : file

    if (name.length > 0 && root.pendingIconIndex[name] === undefined)
      root.pendingIconIndex[name] = value
  }

  // Scans icons asynchronously. When the scan completes, swapping iconIndex and
  // bumping iconRevision makes every workspace retry its icon sources.
  Process {
    id: iconIndexScan
    command: ["bash", "-c", root.iconIndexScanCommand()]

    stdout: SplitParser {
      onRead: function(line) {
        root.indexIconLine(line)
      }
    }

    onStarted: root.pendingIconIndex = ({})

    onExited: {
      root.iconIndex = root.pendingIconIndex
      root.iconCache = ({})
      root.iconRevision++
    }
  }

  // Coalesces DesktopEntries changes into one filesystem rescan.
  Timer {
    id: iconIndexDebounce
    interval: 750
    repeat: false
    onTriggered: {
      if (!iconIndexScan.running) iconIndexScan.running = true
    }
  }

  // Returns the DesktopEntry most likely to represent a Hyprland window class.
  // First use Quickshell's own heuristic. If that misses, explicitly compare the
  // class against StartupWMClass and desktop-entry id, case-insensitively.
  function desktopEntryForClass(cls) {
    if (cls === "") return null

    var entry = DesktopEntries.heuristicLookup(cls)
    if (entry) return entry

    var wanted = String(cls).toLowerCase()
    var applications = DesktopEntries.applications.values

    for (var i = 0; i < applications.length; i++) {
      var candidate = applications[i]
      var startupClass = String(candidate.startupClass || "").toLowerCase()
      var desktopId = String(candidate.id || "").toLowerCase()
      var desktopIdNoSuffix = desktopId.replace(/\.desktop$/, "")

      if (startupClass === wanted
          || desktopId === wanted
          || desktopIdNoSuffix === wanted) {
        return candidate
      }
    }

    return null
  }

  // Resolves a running application's class to an Image.source-compatible URL.
  //
  // Quickshell.iconPath(name) without a second argument deliberately returns a
  // "missing texture" URL when a theme icon cannot be found. That is the
  // purple/black checkerboard shown by Qt. To prevent it, every themed-icon
  // lookup below uses iconPath(name, true), which returns "" on failure.
  //
  // We also try several candidate names because desktop files and Hyprland do
  // not always use the same identifier. For example, Brave may advertise the
  // window class "brave-browser" while its desktop file says
  // Icon=brave-desktop. Only a successfully resolved source is cached.
  function classIcon(cls) {
    if (cls === "") return ""

    // Reuse only successful results. Failed results are never cached.
    if (root.iconCache[cls] !== undefined
        && root.iconCache[cls] !== "") {
      return root.iconCache[cls]
    }

    var entry = root.desktopEntryForClass(cls)
    if (!entry) return ""

    var candidates = []

    function addCandidate(value) {
      var v = String(value || "")
      if (v === "") return
      if (candidates.indexOf(v) === -1) candidates.push(v)
    }

    // Canonical .desktop Icon= name first.
    addCandidate(entry.icon)

    // Then identifiers commonly used as icon basenames.
    addCandidate(cls)
    var desktopId = String(entry.id || "").replace(/\.desktop$/, "")
    addCandidate(desktopId)

    // Brave is one example where Icon= and WM class differ by "-desktop".
    if (entry.icon)
      addCandidate(String(entry.icon).replace(/-desktop$/, ""))

    for (var i = 0; i < candidates.length; i++) {
      var icon = candidates[i]
      var out = ""

      // A desktop file may already contain a usable URL or absolute path.
      if (icon.indexOf("file://") === 0 || icon.indexOf("image://") === 0) {
        out = icon
      } else if (icon.charAt(0) === "/") {
        out = Util.fileUrl(icon)
      } else {
        // IMPORTANT: mirror Omarchy AppLibrary. Prefer our on-disk index before
        // asking Qt's icon theme, because Qt's theme cache may miss app icons.
        var found = root.iconIndex[icon]
        if (found) {
          out = Util.fileUrl(found)
        } else {
          out = Quickshell.iconPath(icon, true)
        }
      }

      if (out !== "") {
        root.iconCache[cls] = out
        return out
      }
    }

    return ""
  }

  // Builds the visible icon-source list for one workspace. The class list comes
  // from parseClientWindows(), while iconRevision creates the QML dependency
  // needed to recalculate this function when that map changes.
  function iconsFor(id) {
    var revision = root.iconRevision

    if (root.iconCount <= 0) return []

    var classes = root.workspaceClasses[String(id)] || []
    var out = []

    for (var i = 0; i < classes.length && out.length < root.iconCount; i++) {
      var src = root.classIcon(classes[i])
      if (src !== "") out.push(src)
    }

    return out
  }

  // Focuses the requested Hyprland workspace when its chip is left-clicked.
  function focusWorkspace(id) {
    if (!root.bar) return
    root.bar.run("hyprctl dispatch " + Util.shellQuote("hl.dsp.focus({ workspace = \"" + id + "\" })"))
  }

  // Lazily creates and opens Editor.qml. Reuses the already-loaded editor on
  // subsequent invocations instead of constructing a second window.
  function openEditor() {
    if (editorLoader.active && editorLoader.item) editorLoader.item.openNow()
    else editorLoader.active = true
  }

  // Lazily creates and opens Rename.qml for editing the current workspace name.
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

  // Closes the fuzzy jump panel when it exists; part of the shell panel-widget
  // open/close/toggle contract consumed by Omarchy's shell IPC.
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

  // Parses `hyprctl binds -j` into a map keyed by modifier mask and key name.
  // The editor uses this map to warn before assigning a conflicting shortcut.
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

  // Starts the asynchronous process that refreshes existingBinds from Hyprland.
  function refreshBinds() { readBinds.running = true }

  // Read once at startup as well as on open: the read is asynchronous, and a
  // capture completed moments after opening would otherwise be checked
  // against an empty list and reported as free.
  // Performs initial asynchronous discovery after the widget is constructed:
  // read existing keybinds, refresh Quickshell's toplevel metadata, and query
  // hyprctl for the class list used by the workspace icon renderer.
  Component.onCompleted: {
    root.refreshBinds()
    Hyprland.refreshToplevels()
    clientRefreshTimer.restart()

    // Match Omarchy's own AppLibrary behavior: build the real-file icon index
    // once at startup so app icons are not dependent on Qt's theme cache.
    if (!iconIndexScan.running) iconIndexScan.running = true
  }

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

  // Extracts the non-modifier key from a textual combination such as
  // "SUPER + SHIFT + F2", returning "F2" for conflict matching.
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

  // Returns a human-readable conflicting binding description, or an empty
  // string when the requested key combination is free (or already ours).
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
  // Directory containing the Lua helpers this plugin injects into Hyprland.
  readonly property string pluginHyprDir: root.pluginDir + "hypr/"

  // Read from the manifest rather than written twice: a version in two
  // places is a version that will disagree with itself.
  property string pluginVersion: ""

  readonly property string docsUrl:
    "https://github.com/mangoleaf/omarchy-workspace-manager-plugin"

  Process { id: docsProc; command: ["xdg-open", root.docsUrl] }

  // Launches the plugin documentation URL using the user's default browser.
  function openDocs() { docsProc.running = true }

  // Watches manifest.json so the editor can display the installed plugin
  // version even after an in-place plugin update.
  FileView {
    id: manifestFile
    path: root.pluginDir + "manifest.json"
    // Watched, because `omarchy plugin update` replaces this file underneath
    // a running shell — an unwatched read would keep showing the version the
    // user had before they updated.
    watchChanges: true
    printErrors: false
    onLoaded: root.readVersion(text())
    onFileChanged: manifestFile.reload()
  }

  // Extracts the version field from manifest.json; malformed JSON is ignored.
  function readVersion(text) {
    try { root.pluginVersion = String(JSON.parse(text).version || "") } catch (e) {}
  }

  // Watches monitors.lua to detect whether the workspace-rules helper has been
  // installed and to notice external edits.
  FileView {
    id: monitorsFile
    path: Quickshell.env("HOME") + "/.config/hypr/monitors.lua"
    watchChanges: true
    printErrors: false
  }

  // Watches bindings.lua to detect whether the workspace-bindings helper has
  // been installed and to notice external edits.
  FileView {
    id: bindingsFile
    path: Quickshell.env("HOME") + "/.config/hypr/bindings.lua"
    watchChanges: true
    printErrors: false
  }

  // Builds the marked dofile(...) block appended to a Hyprland Lua config file
  // when the user chooses "Add to Hyprland" in the plugin editor.
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

  // True only when both required Hyprland Lua integration blocks are detected.
  readonly property bool hyprConfigInstalled:
    root.confRevision >= 0
    && root.hyprFileConfigured(monitorsFile)
    && root.hyprFileConfigured(bindingsFile)

  // Bumped when either file changes, so the editor's banner re-evaluates.
  property int confRevision: 0
  Connections { target: monitorsFile; function onFileChanged() { root.confRevision++ } }
  Connections { target: bindingsFile; function onFileChanged() { root.confRevision++ } }

  // Backs up monitors.lua and bindings.lua before appending the plugin-managed
  // integration blocks. The actual writes happen only after this process exits.
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

  // Leaves the temporary capture submap and restores the normal Hyprland keymap.
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

    function identify(): void {
      identifyOverlay.flash()
    }
  }

  // Lives on the widget rather than in the editor so it can be flashed from
  // a keybind too, without the editor open.
  Identify { id: identifyOverlay; radiusLarge: root.roundLarge }

  function identifyMonitors() {
    identifyOverlay.flash()
  }

  // Bar layout lives in the shell's own config, so centering the workspaces
  // means editing shell.json. Everything else in that file is preserved.
  FileView {
    id: shellFile
    path: Quickshell.env("HOME") + "/.config/omarchy/shell.json"
    watchChanges: true
    printErrors: false
  }

  // Stages a complete shell.json rewrite until the next event-loop turn so the
  // current widget can finish saving its own state before the bar rebuilds.
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

  // Watches the primary workspaces.conf file. External edits automatically
  // reparse the configuration and update the bar without discarding unknown text.
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

  // Executes `hyprctl reload` after configuration writes and then reapplies
  // live workspace names/monitor assignments that a reload alone cannot move.
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

  // Hyprland decides a window's workspace once, at the moment it maps, and
  // never revisits it. Firefox maps its windows titled "Mozilla Firefox" and
  // only becomes "YouTube — Mozilla Firefox" once the page loads, so a title
  // rule is tested against a title the window does not have yet and never
  // fires — in exactly the case title pins exist for. So watch windows
  // appear and rename themselves, and place them here instead.
  property var placed: ({})

  // Corner radius follows the compositor, so this plugin's windows are
  // shaped like every other window on the desktop instead of imposing a
  // rounding the user did not choose. Someone running decoration:rounding = 0
  // gets square popups.
  property int hyprRounding: 10

  readonly property int roundLarge: root.hyprRounding
  // Inner controls sit at half the window radius — the proportion the panels
  // were already drawn at, before this started following Hyprland.
  readonly property int roundSmall: Math.round(root.hyprRounding * 0.5)

  Process {
    id: roundingProc
    command: ["hyprctl", "getoption", "decoration:rounding", "-j"]
    running: true
    stdout: StdioCollector {
      id: roundingOut
      onStreamFinished: {
        try {
          var v = JSON.parse(roundingOut.text)
          if (typeof v.int === "number") root.hyprRounding = Math.max(0, v.int)
        } catch (e) {}
      }
    }
  }

  // Saving this editor reloads Hyprland, and the user may have changed
  // rounding in the same pass.
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (String(event.name) === "configreloaded") roundingProc.running = true
    }
  }

  // Converts configured per-workspace application patterns into a single
  // pattern -> target-workspace lookup used by enforcePins().
  function pinMap() {
    var out = {}
    for (var i = 0; i < root.rows.length; i++) {
      var apps = root.rows[i].apps === "" ? [] : root.rows[i].apps.split(",")
      for (var a = 0; a < apps.length; a++) {
        var pattern = apps[a].replace(/^\s+|\s+$/g, "")
        if (pattern !== "") out[pattern] = root.rows[i].id
      }
    }
    return out
  }

  // Matched the same way the shipped Lua matches: a class must be the whole
  // string, a title need only contain the pattern, both case-insensitively.
  function pinMatches(pattern, cls, title) {
    var wanted = pattern.match(/^title:\s*(.+)$/)
    var subject = wanted ? title : cls
    if (subject === "") return false
    var re = null
    try {
      re = wanted ? new RegExp(wanted[1], "i")
                  : new RegExp("^(?:" + pattern + ")$", "i")
    } catch (e) { return false }
    return re.test(subject)
  }

  // A window is placed once and then left alone: dragging it somewhere else
  // afterwards is a decision, not something to undo on its next title change.
  // Saving the editor passes force, since moving a tag is an instruction to
  // gather up what is already open.
  function enforcePins(force) {
    var map = root.pinMap()
    var values = Hyprland.toplevels.values
    var next = {}

    for (var i = 0; i < values.length; i++) {
      var t = values[i]
      var ipc = t.lastIpcObject || ({})
      var cls = String(ipc["class"] || ipc.initialClass || "")
      var title = String(t.title || ipc.title || "")
      var addr = String(t.address || "")
      if (addr === "") continue
      if (addr.indexOf("0x") !== 0) addr = "0x" + addr
      if (root.placed[addr]) next[addr] = true

      for (var pattern in map) {
        if (!root.pinMatches(pattern, cls, title)) continue
        var target = map[pattern]
        if (t.workspace && t.workspace.id === target) { next[addr] = true; break }
        if (!force && root.placed[addr]) break
        next[addr] = true
        Hyprland.dispatch('hl.dsp.window.move({ window = "address:' + addr
          + '", workspace = "' + target + '", follow = false })')
        break
      }
    }

    root.placed = next
  }

  // Reacts to window lifecycle/movement events. One connection refreshes both
  // the icon source data and the plugin's existing application-pin enforcement.
  Connections {
    target: Hyprland

    function onRawEvent(event) {
      var name = String(event.name)

      if (name === "openwindow"
          || name === "windowtitle"
          || name === "windowtitlev2"
          || name === "closewindow"
          || name === "movewindow"
          || name === "movewindowv2"
          || name === "workspace"
          || name === "focusedmon") {
        Hyprland.refreshToplevels()
        clientRefreshTimer.restart()
        pinTimer.restart()
      }
    }
  }

  // Debounces window-title/open/move events before re-evaluating application
  // pinning rules; browser titles in particular can change several times quickly.
  Timer {
    id: pinTimer
    // Titles arrive in a burst while a page loads; wait for them to settle
    // rather than chasing every intermediate one.
    interval: 250
    onTriggered: root.enforcePins(false)
  }

  // Lazy loader for the full workspace editor; keeps startup cost low until used.
  Loader {
    id: editorLoader
    active: false
    source: Qt.resolvedUrl("Editor.qml")
    onLoaded: {
      item.widget = root
      item.openNow()
    }
  }

  // Lazy loader for the compact workspace rename dialog.
  Loader {
    id: renameLoader
    active: false
    source: Qt.resolvedUrl("Rename.qml")
    onLoaded: {
      item.widget = root
      item.openNow()
    }
  }

  // Lazy loader for the fuzzy workspace/window jump interface.
  Loader {
    id: jumpLoader
    active: false
    source: Qt.resolvedUrl("Jump.qml")
    onLoaded: {
      item.widget = root
      item.openNow()
    }
  }

  // Small horizontal breathing room appended after the workspace group; omitted
  // automatically when the bar is vertical.
  readonly property real trailingGap: root.vertical ? 0 : Style.spaceReal(1.5)

  implicitWidth: grid.implicitWidth + trailingGap
  implicitHeight: grid.implicitHeight

  // Main visual container. It lays workspace chips horizontally on a normal
  // top/bottom bar and vertically when Omarchy places the bar on a side.
  GridLayout {
    id: grid
    anchors.fill: parent
    anchors.rightMargin: root.trailingGap
    columns: root.vertical ? 1 : root.workspaceIds().length
    columnSpacing: root.vertical ? 0 : Style.space(1.5)
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

        readonly property var icons: root.barStyle === "dots" ? [] : root.iconsFor(modelData)
        readonly property bool named: root.isNamed(modelData)
        readonly property string compactName: root.compactNameFor(modelData)
        readonly property color accent: root.bar ? root.bar.urgent : Color.urgent
        readonly property color baseForeground: root.bar ? root.bar.barForeground : Color.foreground

        readonly property color tint: focused
          ? (root.colorActive !== "" ? root.colorActive : accent)
          : activeElsewhere
            ? (root.colorUnfocused !== "" ? root.colorUnfocused : root.defaultUnfocusedColor)
            : occupied
              ? (root.colorOccupied !== "" ? root.colorOccupied : baseForeground)
              : (root.colorEmpty !== "" ? root.colorEmpty : baseForeground)

        implicitWidth: root.barStyle === "dots" && !chip.named
          ? (chip.focused || chip.activeElsewhere ? Style.spaceReal(26) : Style.spaceReal(14))
          : body.implicitWidth + Style.spaceReal(8)
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

        Rectangle {
          visible: root.barStyle === "dots" && !chip.named
          anchors.centerIn: parent
          width: chip.focused || chip.activeElsewhere ? Style.spaceReal(22) : Style.spaceReal(9)
          height: Style.spaceReal(9)
          radius: height / 2
          color: chip.tint

          Behavior on width {
            NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
          }
        }

        Rectangle {
          visible: root.barStyle === "dots" && chip.named
          anchors.fill: parent
          anchors.topMargin: Style.spaceReal(3)
          anchors.bottomMargin: Style.spaceReal(3)
          radius: height / 2
          color: Qt.rgba(chip.tint.r, chip.tint.g, chip.tint.b,
            chip.focused || chip.activeElsewhere ? 0.24 : 0.10)
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
            textFormat: Text.PlainText
            visible: root.barStyle !== "dots" || chip.named
            anchors.verticalCenter: parent.verticalCenter
            text: root.barStyle === "dots" && chip.named
              ? chip.compactName
              : root.labelFor(chip.modelData)
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
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onEntered: {
            if (root.bar) root.bar.showTooltip(chip, root.labelFor(chip.modelData))
          }
          onExited: {
            if (root.bar) root.bar.hideTooltip(chip)
          }
          onClicked: function(mouse) {
            if (mouse.button === Qt.RightButton) root.openEditor()
            else root.focusWorkspace(chip.modelData)
          }
        }
      }
    }
  }
}
