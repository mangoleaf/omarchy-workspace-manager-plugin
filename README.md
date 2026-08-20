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
- `jq`, used by the finder's cursor warp. Omarchy itself depends on it, so a
  working install already has it.

## Install

```bash
omarchy plugin add https://github.com/mangoleaf/omarchy-workspace-manager-plugin --enable
```

The widget appears in the bar's center section. **Right-click it to open the
editor** — that is where everything is configured, and where setup finishes.

Nothing else happens yet: the
plugin owns the bar widget and the editor, while Hyprland owns workspace rules
and keybindings, so the two are wired together by the config below.

## Setup

Every workspace definition lives in one file, `~/.config/hypr/workspaces.conf`.
Hyprland has to read it too, which takes one line in each of two configs.

**The easy way.** Right-click the widget in the bar to open the editor — every
part of this plugin is configured from there. Until
Hyprland is wired up it shows a setup notice with an **Add to Hyprland**
button, which appends the two lines for you, backs both files up first, and
reloads. Skip to [The editor](#the-editor).

**By hand**, if you would rather see exactly what lands where. Add to
`~/.config/hypr/monitors.lua`:

```lua
dofile(os.getenv("HOME") .. "/.config/omarchy/plugins/mangoleaf.workspace-manager/hypr/workspace-rules.lua")
```

and to `~/.config/hypr/bindings.lua`:

```lua
dofile(os.getenv("HOME") .. "/.config/omarchy/plugins/mangoleaf.workspace-manager/hypr/workspace-binds.lua")
```

Then:

```bash
omarchy restart shell
```

The Lua those lines load ships with the plugin, in `hypr/`. It builds a
workspace rule per line of `workspaces.conf` — name, monitor, pinned apps —
and binds `SUPER + key` to switch, `SUPER + SHIFT + key` to move a window
there, and `SUPER + CTRL + key` to move one without following. It also binds
the three plugin hotkeys. Because it ships with the plugin, it updates when
the plugin does, and there is no pasted copy to drift out of date.

The three hotkeys are not typos for each other. `rename` and `editor` call
this plugin's own IPC target, while the finder goes through the shell's
bar-widget summon path:

```
omarchy-shell mangoleaf.workspace-manager rename
omarchy-shell mangoleaf.workspace-manager editor
omarchy-shell shell toggle mangoleaf.workspace-manager
```

Those are bind targets, not commands to run in a terminal. `omarchy-shell`
locates the running shell through `$OMARCHY_PATH`, and a shell started before
an Omarchy upgrade can carry a stale one — in which case it reports
"omarchy-shell is not running" even though it is. Hyprland always has the
right value, so the hotkeys work regardless; a fresh login fixes the terminal.

Right-click the widget to open the editor. If you already had workspaces
before installing this, it offers to bring them in — names, monitors and the
stock `SUPER` number keys — so you are not retyping a setup you already had.

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
| Monitor | click to cycle through your displays, or **Any monitor** to leave it unpinned. Hover it to see which panel that connector is, or whether it is plugged in at all |
| Hotkey | click, then press the combination — it is captured, not typed. Your existing bindings are suspended while it listens, so a combination that is already taken still records rather than firing. `SUPER` is implied on workspace rows |
| Apps | pinned apps as tags. **+** opens a searchable list of installed apps, **✕** unpins. **Drag a tag onto another workspace row to move the pin there** — see below |

**+ Add workspace** appends one; the trash button removes it, unless it still
holds windows.

**◉ Identify monitors** puts each display's own connector name on it in large
type for a few seconds — the same trick desktop display settings use. Nobody
knows which panel `DP-2` is on a fresh install, and two identical monitors
report identical makes and models, so this is the only reliable way to tell
them apart before pinning workspaces. It works from a keybind too:

```bash
omarchy-shell mangoleaf.workspace-manager identify
```

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
one level in. Each workspace row carries its monitor and its hotkey as pills.
Typing filters it and ranks best match first; every space-separated term has
to match, in any order, so `dr chr` finds *Google Drive — Chromium*. Where a
workspace and a window match equally well — a workspace called Signal and the
Signal window — the window wins, since the workspace has a hotkey of its own.
Enter on a workspace goes there; Enter on a window focuses it across monitors
and warps the pointer to its center, so hover focus does not snap back. Esc
closes.

## Application pinning

A pinned app always opens on its workspace. Add one from the editor's **+**
button: the picker lists every installed application with its icon, and can be
filtered to just what is running — a running window reports its class exactly,
while an app that has never run is a best-effort guess from its desktop entry.
If a pin does not fire, launch the app once and re-pick it from **Running**.

**Moving a pin between workspaces:** drag its tag from one workspace's row
onto another. The pin moves, and when you close the editor that app's open
windows move with it — so re-homing an app is one drag rather than an unpin,
a re-pin, and moving its windows by hand.

Values are window-class regexes, so pin narrowly. Pinning a browser or a
terminal will drag every window of that class along with it. Matching
ignores case, so `xclock` finds the class `XClock`; a pattern that sets its
own flags — one starting `(?` — is used exactly as written.

**Web apps need a title, not a class.** Every Firefox web app reports the
class `firefox`, so pinning `YouTube` matches nothing and pinning `firefox`
takes every Firefox window with it. Prefix the pin with `title:` to match the
window title instead:

```
title:YouTube
```

A title pin matches anywhere in the title, so `title:YouTube` finds
*YouTube — Mozilla Firefox*. A class pin still has to match the whole class.

Hyprland chooses a window's workspace once, as the window maps, and never
revisits it. Browsers map their windows titled just *Mozilla Firefox* and only
take the page's title once it loads, so a title rule is tested against a title
the window does not have yet. The plugin therefore watches windows appear and
rename themselves and places them itself. A window is placed once and then
left alone — moving it somewhere else afterwards is a decision, not something
to undo the next time its title changes.

The **+** picker offers both: every installed app by class, and every open
window by title, listed as `title:…`. Anything it does not know about can be
typed into its search box and taken as written.

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

`~/.config/hypr/monitors.lua` and `~/.config/hypr/bindings.lua` are written in
exactly one circumstance: you press **Add to Hyprland** in the editor's setup
notice. It appends one `dofile` line to each, inside a marked block, after
copying both files to timestamped backups beside them. Nothing else in either
file is touched, it will not add a line that is already there, and deleting
the block is a clean uninstall. Wire them up by hand instead and the plugin
never writes them at all.

Saving in the editor also runs `hyprctl reload` and applies workspace names,
monitor assignments and pinned-app window moves to the running session.

One further runtime change, which touches no file: at startup the plugin
defines a Hyprland submap named `omarchy-workspace-manager-capture`, and
switches into it only while a hotkey box is listening. That is what suspends
your bindings long enough to capture a combination that is already bound; it
is left the moment capture ends, and it disappears with the compositor's next
reload.

All of the above are live compositor actions, not file changes. Nothing is
written to disk beyond the two files above.

## Uninstall

```bash
omarchy plugin remove mangoleaf.workspace-manager
```

Then delete the `-- >>> omarchy-workspace-manager` block from
`~/.config/hypr/monitors.lua` and `~/.config/hypr/bindings.lua`, and delete
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
