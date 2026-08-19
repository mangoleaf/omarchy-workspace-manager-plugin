# Omarchy Workspace Manager

Named workspaces for the Omarchy bar, with monitor locking, application
pinning, a click-to-capture hotkey editor, and a fuzzy search tree of
workspaces and applications.

Omarchy's stock workspace widget shows workspaces 1–10 as bare numbers on
every bar. This replaces it with workspaces that carry names, that belong to
a particular monitor, and that you configure from a visual editor instead of
by hand-editing config.

## Requirements

- Omarchy 4.0 or newer (the Quickshell shell — this is not a Waybar module)
- Hyprland 0.56+ with the Lua config format
- `jq`, which Omarchy already installs. Only the finder's cursor warp uses
  it, and it fails quietly without it: focus still moves, the pointer just
  stays where it was.

## Install

```bash
omarchy plugin add https://github.com/mangoleaf/omarchy-workspace-manager-plugin --enable
```

The widget appears in the bar's center section. Nothing else happens yet: the
plugin owns the bar widget and the editor, while Hyprland owns workspace rules
and keybindings, so the two are wired together by the config below.

## Setup

The plugin keeps every workspace definition in one file,
`~/.config/hypr/workspaces.conf`, and Hyprland reads the same file. Add both
snippets, then restart the shell.

**`~/.config/hypr/monitors.lua`** — workspace rules: name, monitor, and the
apps pinned to each workspace.

```lua
local seen_monitor = {}
local settings = { number = "true", delim = ":", compact = "false" }
local f = io.open(os.getenv("HOME") .. "/.config/hypr/workspaces.conf")
if f then
  for line in f:lines() do
    -- id|key|monitor|name|apps|number
    local id, key, mon, name, apps, num =
      line:match("^(%d+)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|?([^|]*)$")
    if not id then
      -- Older five-field rows: field 4 holds the combined "0: Name".
      id, key, mon, name, apps = line:match("^(%d+)|([^|]*)|([^|]*)|([^|]*)|?([^|]*)$")
      num = ""
    end

    if id then
      -- The name a workspace carries until the plugin renames it, composed
      -- the way the plugin composes it.
      local label = name
      if settings.number ~= "false" and num ~= "" then
        if name == "" then
          label = num
        elseif settings.compact == "true" then
          label = num .. settings.delim .. name
        else
          label = num .. settings.delim .. " " .. name
        end
      end

      local rule = {
        workspace = id,
        default_name = label,
        persistent = true,
      }

      -- An empty monitor field leaves the workspace unpinned: it follows
      -- focus instead of living on one output.
      if mon ~= "" then
        rule.monitor = mon
        rule.default = not seen_monitor[mon]
        seen_monitor[mon] = true
      end

      hl.workspace_rule(rule)

      for app in (apps or ""):gmatch("[^,]+") do
        local pattern = app:match("^%s*(.-)%s*$")
        if pattern ~= "" then
          o.window(pattern, { workspace = id })
        end
      end
    else
      local k, v = line:match("^(%a+)|(.*)$")
      if k and settings[k] ~= nil then settings[k] = v end
    end
  end
  f:close()
end
```

**`~/.config/hypr/bindings.lua`** — per-workspace keys and the three plugin
hotkeys.

```lua
local f = io.open(os.getenv("HOME") .. "/.config/hypr/workspaces.conf")
if f then
  for line in f:lines() do
    local id, key, mon, name = line:match("^(%d+)|([^|]*)|([^|]*)|([^|]*)")
    local num = line:match("^%d+|[^|]*|[^|]*|[^|]*|[^|]*|([^|]*)$")
    if id and key ~= "" then
      local base = (num and num ~= "") and num or name
      if name ~= "" and num and num ~= "" then base = num .. ": " .. name end
      o.bind("SUPER + " .. key, "Switch to workspace " .. base, hl.dsp.focus({ workspace = id }))
      o.bind("SUPER + SHIFT + " .. key, "Move to workspace " .. base, hl.dsp.window.move({ workspace = id }))
      o.bind("SUPER + CTRL + " .. key, "Move silently to workspace " .. base, hl.dsp.window.move({ workspace = id, follow = false }))
    else
      local action, keys = line:match("^(%a+)|(.+)$")
      -- Unbind first so these keys can take over an Omarchy default.
      if action == "rename" then
        hl.unbind(keys)
        o.bind(keys, "Rename workspace", "omarchy-shell mangoleaf.workspace-manager rename")
      elseif action == "jump" then
        hl.unbind(keys)
        o.bind(keys, "Jump to workspace", "omarchy-shell shell toggle mangoleaf.workspace-manager")
      elseif action == "editor" then
        hl.unbind(keys)
        o.bind(keys, "Workspace editor", "omarchy-shell mangoleaf.workspace-manager editor")
      end
    end
  end
  f:close()
end
```

The three hotkey commands are not typos for each other. `rename` and `editor`
are calls into this plugin's own IPC target, while the finder goes through the
shell's bar-widget summon path:

```
omarchy-shell mangoleaf.workspace-manager rename
omarchy-shell mangoleaf.workspace-manager editor
omarchy-shell shell toggle mangoleaf.workspace-manager
```

Then:

```bash
omarchy restart shell
```

Right-click the widget to open the editor and add your first workspaces.

## In the bar

Each bar shows the workspaces pinned to its own monitor. A workspace left
unpinned appears on whichever monitor it currently occupies and moves between
bars along with it, so it is never shown twice or not at all.

Four states are drawn differently: the focused workspace, the active workspace
on a monitor that does not have focus, a workspace with windows, and an empty
one. Each has a colour you can set in the editor; left blank they follow your
theme, except the unfocused-monitor state, which the theme has no colour for
and so defaults to `#ff9e3f`.

Empty workspaces are dimmed while their colour is blank — set one and the
dimming stops, on the grounds that a colour you picked should be shown as you
picked it.

## The editor

Right-click any workspace in the bar, or press the editor hotkey.

**Workspaces tab** — one row per workspace:

| Column | |
|---|---|
| Number | the number or tag shown before the name — typed, so `0A` or `L` work; blank falls back to the row's position |
| Name | click to rename |
| Monitor | click to cycle through your displays, or **Any monitor** to leave it unpinned |
| Hotkey | click, then press the combination — it is captured, not typed. Your existing bindings are suspended while it listens, so a combination that is already taken still records rather than firing. `SUPER` is implied on workspace rows |
| Apps | pinned apps as tags. **+** opens a searchable list of installed apps, **✕** unpins, and dragging a tag onto another workspace re-pins it there |

**+ Add workspace** appends one; the trash button removes it, unless it still
holds windows.

**Settings tab** — the three hotkeys (rename, jump, editor), how the bar
renders workspaces, how many app icons to show beside each name, a **Colours**
block with a live swatch and hex field for each of the four workspace states,
used both in the bar and in the editor's own list (blank means "theme"),
numbering options — whether numbers are shown, whether you count from 0 or 1,
the delimiter between number and name and whether a space follows it — and
*Center the workspaces in the bar*, which moves the widget to the bar's center
and pushes whatever was centered over to the right. Unticking puts those
widgets back where they were.

The editor autosaves: there is no Save button and Esc just closes it. A change
is written once you stop typing, then Hyprland reloads, names and monitors are
applied, and any pinned app's open windows move onto its workspace. A change
that is not valid — a blank name, a `|` in a field, a colour that is not hex —
shows an error and is not written until you fix it.

The rename hotkey is a shortcut for one workspace: it opens a small popup for
the *active* workspace only, and edits its name. The number is left alone —
it is a separate field, and the popup shows it beside the box so you can see
what you are naming.

## Fuzzy finder

The jump hotkey opens a two-level tree: workspaces, with their windows nested
one level in. Each workspace row carries its monitor and its hotkey as pills. Typing filters it
and ranks best match first; every space-separated term has to match, in any
order, so `dr chr` finds *Google Drive — Chromium*. Where a workspace and a
window match equally well — a workspace called Signal and the Signal window —
the window wins, since the workspace has a hotkey of its own. Enter on a workspace goes
there; Enter on a window focuses it across monitors and warps the pointer to
its center, so hover focus does not snap back. Esc closes.

## Application pinning

A pinned app always opens on its workspace. Add one from the editor's **+**
button: the picker lists every installed application with its icon, and can be
filtered to just what is running — a running window reports its class exactly,
while an app that has never run is a best-effort guess from its desktop entry.
If a pin does not fire, launch the app once and re-pick it from **Running**.

Values are window-class regexes, so pin narrowly. Pinning a browser or a
terminal will drag every window of that class along with it.

## Config format

`~/.config/hypr/workspaces.conf`, one workspace per line:

```
id|hotkey|monitor|name|apps|number
```

```
1|KP_Insert|DP-2|Main||0
2|KP_End||Notes|md.obsidian.Obsidian|1
```

`hotkey` is `SUPER`-relative and may be empty. `monitor` empty means unpinned.
`apps` is a comma-separated list of window-class regexes.

`number` and `name` are separate fields, and the bar joins them for display.
The number is typed, not counted, so it does not have to be a number —
`0A`, `L` or `SA` are all fine, which a derived position could never express.
Leave it empty and the row's position is used instead. A file written by an
older version, where field 4 held the combined `0: Main`, is split on its
first colon when it loads; a value with no colon is read as a number with no
name. Nothing needs hand-editing.

Settings lines come first:

```
rename|SUPER + SHIFT + F2
jump|SUPER + SHIFT + grave
editor|SUPER + SHIFT + F4
center|true
icons|3
style|pill
colorunfocused|#ff9e3f
```

`icons` is how many app icons appear beside a workspace name in the bar,
default `3`, or `0` for none. `style` is how the bar draws workspaces —
`plain` (default), `pill` or `underline`.

Four keys control numbering and how a number and name are joined. `base` is
`0` or `1`, whether you count from zero or one. `number` is `true` or `false`,
whether the number is drawn at all. `delim` is the single character between
number and name, `:` by default, and `compact` is `true` or `false` for
whether a space follows it. The last two are display only — they change how a
workspace is drawn, never what is stored, so switching them back and forth
leaves your names untouched.

`coloractive`, `colorunfocused`, `coloroccupied` and `colorempty` set the
four workspace colours, as `#rgb`, `#rrggbb` or `#aarrggbb`. Absent or blank
means follow the theme, which is the default for all but `colorunfocused`
(`#ff9e3f`).

The editor always writes `center`, `icons`, `style`, `base`, `compact`,
`number` and `delim`, and writes `rename`, `jump`, `editor`, `centermoved` and
the four colours only when they are set — so a hand-written config can leave
any of them out and still be valid.

No field may contain `|`. The editor enforces this; if you hand-edit, keep to
it.

Hand annotation is safe. The editor and the rename popup rewrite this file in
full, but comments, blank lines and keys the plugin does not recognise are
kept verbatim: anything above the first line it recognises stays at the top,
and everything else is written back after the workspace rows. Content always
survives; only position can shift, so a comment sitting between two workspace
rows reappears below them rather than where you put it.

## What it writes

The plugin writes two files, and nothing else on your system.

`~/.config/hypr/workspaces.conf` is its own file: it is created and rewritten
by the editor and by the rename popup, and holds every workspace definition
and setting described above. Even there it does not clobber what it did not
write — comments, blank lines and keys it does not recognise survive a rewrite
verbatim.

`~/.config/omarchy/shell.json` belongs to the shell, and is touched only if
you tick or untick *Center the workspaces in the bar* — and then not until you
close the editor, because rearranging the bar makes the shell rebuild it and
that would take the editor down with it. That write is a full
JSON round-trip that preserves every other key in the file — your idle
timings, plugin list and the rest are read back and written out with their
values intact — and it is undone by unticking the option. The file is
re-serialised at two-space indent, so hand formatting is normalised, though
nothing is lost: JSON has no comments.

`monitors.lua` and `bindings.lua` are **never** written. The snippets in
[Setup](#setup) are yours to add and yours to remove; the plugin only reads
the config file they point at.

Saving in the editor also runs `hyprctl reload` and applies workspace names,
monitor assignments and pinned-app window moves to the running session.

One further runtime change, which touches no file: at startup the plugin
defines a Hyprland submap named `omarchy-workspace-manager-capture`, and switches into it
only while a hotkey box is listening. That is what suspends your bindings
long enough to capture a combination that is already bound; it is left the
moment capture ends, and it disappears with the compositor's next reload.

All of the above are live compositor actions, not file changes. Nothing is
written to disk beyond the two files above.

## Uninstall

```bash
omarchy plugin remove mangoleaf.workspace-manager
```

Then remove the two Lua snippets above, and delete
`~/.config/hypr/workspaces.conf` if you want the workspace rules gone too.
If you had *Center the workspaces in the bar* enabled, untick it before
removing the plugin, so the displaced widgets return to the center on their
own. Untick before deleting `workspaces.conf` too: the record of which widgets
to put back lives in that file, as `centermoved`.

## Credits

The tree build, filter and flatten in `TreeModel.js` are adapted from
[omarchy-window-tree](https://github.com/chagel/omarchy-window-tree) by MGC,
used under the MIT licence.

## Licence

MIT — see [LICENSE](LICENSE).
