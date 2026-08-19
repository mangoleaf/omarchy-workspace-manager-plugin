.pragma library

// Adapted from omarchy-window-tree by MGC <chagel@gmail.com>, MIT licensed:
// https://github.com/chagel/omarchy-window-tree
// Changed: workspaceLabel uses the workspace's own name verbatim (this setup
// names all workspaces, e.g. "0: MLStudios") instead of tag arithmetic.

// The tree behind the picker, kept free of Qt so it can be exercised outside
// the shell (`node test/tree.test.js`).
//
// Three fixed levels -- monitor, workspace, window. Nothing here recurses,
// because that is the actual shape of Hyprland's state rather than a
// simplification of it, and fixing the depth is what keeps the row prefixes
// and the filter small enough to read.

// Workspace ids are partitioned per monitor when a tag config is installed:
// 1-9 on the first output, 11-19 on the second, 21-29 on the third. The tag a
// bar shows is the id's position inside its block -- and for an unpartitioned
// pool (ids 1..9) that arithmetic is already the identity, so this needs no
// setting and cannot disagree with what the bar is drawing.
var STRIDE = 10

// Named workspaces and the scratchpad report ids <= 0, which belong to no
// block; they keep their own name instead.
function tagOf(id) {
  return id > 0 ? ((id - 1) % STRIDE) + 1 : id
}

// Hyprland's IPC spells addresses with an 0x prefix and the toplevel property
// spells them without. Dispatching wants the prefixed form.
function normalizeAddress(address) {
  var text = String(address || "")
  if (!text) return ""
  return text.indexOf("0x") === 0 ? text : "0x" + text
}

// Subsequence match, the usual fuzzy-picker rule: every character of a term
// appears in order, not necessarily adjacent.
//
// Whitespace separates independent terms, all of which must match somewhere,
// in any order -- so "dr chr" and "chr dr" both find "Google Drive -
// Chromium". Treating a space as just another character to skip would instead
// demand that the two halves appear in the order typed, which is exactly the
// thing a user cannot know in advance about a window title.
function matches(text, query) {
  var haystack = String(text || "").toLowerCase()
  var terms = String(query || "").toLowerCase().split(/\s+/)

  for (var i = 0; i < terms.length; i++) {
    if (!terms[i]) continue
    if (!matchesTerm(haystack, terms[i])) return false
  }

  return true
}

function matchesTerm(haystack, term) {
  var at = 0
  for (var i = 0; i < term.length; i++) {
    at = haystack.indexOf(term.charAt(i), at)
    if (at === -1) return false
    at++
  }
  return true
}

function plural(count, noun) {
  return count + " " + noun + (count === 1 ? "" : "s")
}

function workspaceLabel(workspace) {
  var name = workspace.name || ""
  return name !== "" ? name : String(workspace.id)
}

function windowLabel(window) {
  return window.title || window.appClass || "(untitled)"
}

// The right-hand column. Class first because it is the stable half -- titles
// churn as a browser changes tabs -- then whatever is unusual about the
// window's state. A window that is merely tiled and unfocused says nothing.
function windowMeta(window) {
  var parts = []
  if (window.appClass) parts.push(window.appClass)
  if (window.fullscreen) parts.push("fullscreen")
  else if (window.floating) parts.push("floating")
  if (window.urgent) parts.push("urgent")
  if (window.active) parts.push("active")
  return parts.join(" · ")
}

// ---- Building

// monitors  [{ name, focused }]
// workspaces[{ id, name, monitorName }]
// windows   [{ address, title, appClass, workspaceId, monitorName,
//              active, urgent, floating, fullscreen }]
//
// Order is taken from the caller and never re-sorted: the point of a tree is
// that a given window keeps its position between summons, so muscle memory is
// worth more here than ranking rows by match quality.
function build(monitors, workspaces, windows) {
  var windowsByWorkspace = {}
  for (var w = 0; w < windows.length; w++) {
    var win = windows[w]
    var key = String(win.workspaceId)
    if (!windowsByWorkspace[key]) windowsByWorkspace[key] = []
    windowsByWorkspace[key].push({
      kind: "window",
      key: "win:" + normalizeAddress(win.address),
      label: windowLabel(win),
      meta: windowMeta(win),
      search: [win.title, win.appClass].join(" "),
      address: normalizeAddress(win.address),
      workspaceId: win.workspaceId,
      monitorName: win.monitorName,
      active: win.active,
      urgent: win.urgent,
      icon: win.icon || ""
    })
  }

  // Hyprland hands back workspaces in creation order, not id order -- a live
  // machine reports things like 2, 18, 16, 1, 3, 5 -- so a tree built straight
  // from the model would list a monitor's tags shuffled. Sorting here rather
  // than at the call site keeps every consumer (and the tests) on one order.
  var ordered = workspaces.slice().sort(function(a, b) { return a.id - b.id })

  var tree = []
  for (var m = 0; m < monitors.length; m++) {
    var monitor = monitors[m]
    var children = []
    var total = 0

    for (var s = 0; s < ordered.length; s++) {
      var workspace = ordered[s]
      if (workspace.monitorName !== monitor.name) continue

      var kids = windowsByWorkspace[String(workspace.id)] || []
      total += kids.length
      children.push({
        kind: "workspace",
        key: "ws:" + workspace.id,
        label: workspaceLabel(workspace),
        meta: plural(kids.length, "window"),
        search: [workspaceLabel(workspace), workspace.name].join(" "),
        workspaceId: workspace.id,
        monitorName: monitor.name,
        active: workspace.active,
        urgent: workspace.urgent,
        children: kids
      })
    }

    // A monitor with no workspaces at all cannot happen -- Hyprland always has
    // one active per output -- but an empty row would be a dead end if it did.
    if (children.length === 0) continue

    tree.push({
      kind: "monitor",
      key: "mon:" + monitor.name,
      label: monitor.name,
      meta: plural(total, "window"),
      search: monitor.name,
      monitorName: monitor.name,
      active: monitor.focused,
      children: children
    })
  }

  return tree
}

// ---- Filtering

// A node survives if it matches or if anything beneath it does. Matching a
// parent keeps its whole subtree: typing a monitor name is a request to see
// that monitor, not to see the nothing underneath it that also matched.
function filterTree(tree, query) {
  if (!query) return tree

  var out = []
  for (var m = 0; m < tree.length; m++) {
    var monitor = tree[m]
    var monitorHit = matches(monitor.search, query)
    var workspaces = []

    for (var s = 0; s < monitor.children.length; s++) {
      var workspace = monitor.children[s]
      var workspaceHit = monitorHit || matches(workspace.search, query)
      var windows = []

      for (var w = 0; w < workspace.children.length; w++) {
        var window = workspace.children[w]
        if (workspaceHit || matches(window.search, query)) windows.push(window)
      }

      if (workspaceHit || windows.length > 0) {
        workspaces.push(withChildren(workspace, windows))
      }
    }

    if (workspaces.length > 0) out.push(withChildren(monitor, workspaces))
  }

  return out
}

// A shallow copy carrying a new child list, so filtering never mutates the
// tree it was handed.
function withChildren(node, children) {
  var copy = {}
  for (var k in node) copy[k] = node[k]
  copy.children = children
  return copy
}

// ---- Flattening

// Rows for the list view. Each carries the geometry of its own branch rather
// than a drawn prefix: `depth` for the indent, `last` for whether the branch
// stops here, and `parentLast` for whether the level above it keeps running.
//
// The view draws those as hairlines rather than box-drawing characters. A
// glyph is laid out in the font's line box, which is shorter than the row, so
// character verticals cannot meet across rows at any font size -- they come
// out as a dashed ladder. Three booleans render as one continuous rule.
//
// Depth is fixed at three, so the only ancestor a window has to know about is
// its workspace.
function flatten(tree, collapsed) {
  var held = collapsed || {}
  var rows = []

  for (var m = 0; m < tree.length; m++) {
    var monitor = tree[m]
    rows.push(row(monitor, 0, m === tree.length - 1, true, monitor.children.length > 0))
    if (held[monitor.key]) continue

    for (var s = 0; s < monitor.children.length; s++) {
      var workspace = monitor.children[s]
      var lastWorkspace = s === monitor.children.length - 1
      rows.push(row(workspace, 1, lastWorkspace, true, workspace.children.length > 0))
      if (held[workspace.key]) continue

      for (var w = 0; w < workspace.children.length; w++) {
        var window = workspace.children[w]
        rows.push(row(window, 2, w === workspace.children.length - 1, lastWorkspace, false))
      }
    }
  }

  return rows
}

function row(node, depth, last, parentLast, expandable) {
  return {
    kind: node.kind,
    key: node.key,
    depth: depth,
    last: last,
    parentLast: parentLast,
    label: node.label,
    meta: node.meta,
    address: node.address,
    workspaceId: node.workspaceId,
    monitorName: node.monitorName,
    active: node.active,
    urgent: node.urgent,
    icon: node.icon || "",
    expandable: expandable
  }
}

// ---- Selection

// The row to land on when the picker opens: wherever focus already is, so
// Enter is a no-op and the arrows move from somewhere the user recognises.
function indexOfActiveWindow(rows) {
  for (var i = 0; i < rows.length; i++) {
    if (rows[i].kind === "window" && rows[i].active) return i
  }
  return 0
}

// The row to land on after typing. Row 0 is a monitor header, and a picker
// that answers a search with "monitor DP-4" instead of the window you named
// makes the common path -- type a few letters, press Enter -- land on the one
// row you did not ask for. Headers stay reachable with the arrows.
function indexOfFirstWindow(rows) {
  for (var i = 0; i < rows.length; i++) {
    if (rows[i].kind === "window") return i
  }
  return 0
}


// ---- Activation

// The dispatches that focus a row, in order. All of them are reversible, and
// all are in the Lua form Hyprland 0.56 expects -- the classic
// `focuswindow address:0x…` string is a parse error under a Lua config.
//
// A window takes one call: focusing it follows the window to whatever monitor
// and workspace it is on. A workspace takes two, and the monitor has to come
// first -- switching to an absolute id pulls that workspace onto the focused
// output instead of moving focus to where it already lives, which silently
// rearranges the other monitor.
function focusCommands(row) {
  if (row.kind === "window" && row.address)
    return ['hl.dsp.focus({ window = "address:' + row.address + '" })']

  if (row.kind === "workspace")
    return [
      'hl.dsp.focus({ monitor = "' + row.monitorName + '" })',
      'hl.dsp.focus({ workspace = "' + row.workspaceId + '" })'
    ]

  if (row.kind === "monitor")
    return ['hl.dsp.focus({ monitor = "' + row.monitorName + '" })']

  return []
}
