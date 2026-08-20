-- Omarchy Workspace Manager — per-workspace keys and the three plugin hotkeys.
-- Reads ~/.config/hypr/workspaces.conf, which the plugin's editor writes.
-- Loaded from your bindings.lua with a single dofile line; see the README.

-- Defaults, used when workspaces.conf does not name a hotkey for an action.
local hotkeys = {
  rename = "SUPER + SHIFT + F2",
  jump   = "SUPER + SHIFT + F3",
  editor = "SUPER + SHIFT + F4",
}

local f = io.open(os.getenv("HOME") .. "/.config/hypr/workspaces.conf")
if f then
  for line in f:lines() do
    -- id|key|monitor|name|apps|number ; only the first four are needed here
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
      if action and hotkeys[action] ~= nil then hotkeys[action] = keys end
    end
  end
  f:close()
end

-- Unbind first so these can take over an Omarchy default.
local actions = {
  { key = "rename", label = "Rename workspace", ipc = "omarchy-shell mangoleaf.workspace-manager rename" },
  { key = "jump",   label = "Jump to workspace", ipc = "omarchy-shell shell toggle mangoleaf.workspace-manager" },
  { key = "editor", label = "Workspace editor", ipc = "omarchy-shell mangoleaf.workspace-manager editor" },
}

for _, a in ipairs(actions) do
  local keys = hotkeys[a.key]
  if keys and keys ~= "" then
    hl.unbind(keys)
    o.bind(keys, a.label, a.ipc)
  end
end
