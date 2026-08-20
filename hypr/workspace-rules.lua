-- Omarchy Workspace Manager — Hyprland workspace rules.
-- Reads ~/.config/hypr/workspaces.conf, which the plugin's editor writes.
-- Loaded from your monitors.lua with a single dofile line; see the README.

local seen_monitor = {}
local settings = { number = "true", delim = ":", compact = "false" }
local f = io.open(os.getenv("HOME") .. "/.config/hypr/workspaces.conf")
if f then
  for line in f:lines() do
    -- id|key|monitor|name|apps|number ; trailing fields may be absent
    local id, key, mon, name, apps, num =
      line:match("^(%d+)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|?([^|]*)$")
    if not id then
      -- Pre-6-field rows: field 4 still holds the combined "0: Name", which
      -- composes correctly as-is.
      id, key, mon, name, apps = line:match("^(%d+)|([^|]*)|([^|]*)|([^|]*)|?([^|]*)$")
      num = ""
    end

    if id then
      -- The plugin renames workspaces live; this is the name they carry
      -- until it does, composed the same way it composes them.
      local label = name
      num = num or ""
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
        layout_opts = { orientation = "center" },
      }

      if mon ~= "" then
        rule.monitor = mon
        rule.default = not seen_monitor[mon]
        seen_monitor[mon] = true
      end

      hl.workspace_rule(rule)

      for app in (apps or ""):gmatch("[^,]+") do
        local pattern = app:match("^%s*(.-)%s*$")
        if pattern ~= "" then
          -- A pin prefixed "title:" matches the window title instead of its
          -- class. Web apps need this: every Firefox web app reports the
          -- class "firefox", so a class pin cannot tell YouTube from any
          -- other Firefox window, while its title can.
          local wanted = pattern:match("^title:%s*(.+)$")
          local target = wanted or pattern

          -- Class and title matching are case-sensitive regexes, so a pin
          -- written as "xclock" silently never fires against the class
          -- "XClock" — no error, the window just opens wherever it would
          -- have anyway. Ask for case-insensitive matching unless the
          -- pattern already sets its own flags.
          if not target:match("^%(%?") then
            -- A rule has to match the whole class or title, not part of it.
            -- Classes are picked whole, but a title is a sentence — "YouTube"
            -- is meant to find "YouTube — Mozilla Firefox" — so a title
            -- pattern matches anywhere within the title.
            target = wanted and ("(?i).*" .. target .. ".*") or ("(?i)" .. target)
          end

          if wanted then
            o.window({ title = target }, { workspace = id })
          else
            o.window(target, { workspace = id })
          end
        end
      end
    else
      local k, v = line:match("^(%a+)|(.*)$")
      if k and settings[k] ~= nil then settings[k] = v end
    end
  end
  f:close()
end
