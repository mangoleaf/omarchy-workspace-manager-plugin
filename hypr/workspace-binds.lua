-- Omarchy Workspace Manager — per-workspace keys and the three plugin hotkeys.
-- Reads ~/.config/hypr/workspaces.conf, which the plugin's editor writes.
-- Loaded from your bindings.lua with a single dofile line; see the README.

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
