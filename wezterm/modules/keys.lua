local wezterm = require("wezterm")
local icons = require("modules.icons")

local M = {}

local DIRECTIONS = { h = "Left", j = "Down", k = "Up", l = "Right" }

-- The forwarding half of smart-splits: CTRL+hjkl has to reach Neovim's own
-- window navigation when a pane is running it, and move between WezTerm panes
-- everywhere else. icons.basename already lowercases and drops ".exe", so a
-- Windows absolute path and a POSIX one answer the same.
function M.is_nvim(process)
  if not process then return false end
  local name = icons.basename(process)
  return name == "nvim" or name == "vim"
end

-- A split action carries the cwd it was built with, and the domain's default is
-- the home directory rather than the pane's. Reading the pane needs a callback,
-- so the action is built at press time.
-- Named for where the new pane lands, not for WezTerm's own terms: it calls a
-- side-by-side split "horizontal", which is the opposite of what vim and tmux
-- call it, and the keys here follow vim -- v splits beside, h splits below.
local function split(placement)
  return wezterm.action_callback(function(window, pane)
    local cwd = pane:get_current_working_dir()
    local action = placement == "beside"
      and wezterm.action.SplitHorizontal({ cwd = cwd })
      or wezterm.action.SplitVertical({ cwd = cwd })
    window:perform_action(action, pane)
  end)
end

local function smart_split_nav(key)
  return wezterm.action_callback(function(window, pane)
    if M.is_nvim(pane:get_foreground_process_name()) then
      window:perform_action(
        wezterm.action.SendKey({ key = key, mods = "CTRL" }), pane)
    else
      window:perform_action(
        wezterm.action.ActivatePaneDirection(DIRECTIONS[key]), pane)
    end
  end)
end

function M.build(mod_primary)
  local list = {}

  for key, direction in pairs(DIRECTIONS) do
    table.insert(list, { key = key, mods = "LEADER",
      action = wezterm.action.ActivatePaneDirection(direction) })
    table.insert(list, { key = key, mods = "CTRL", action = smart_split_nav(key) })
  end

  table.insert(list, { key = "v", mods = mod_primary, action = split("beside") })
  table.insert(list, { key = "h", mods = mod_primary, action = split("below") })
  table.insert(list, { key = "t", mods = mod_primary,
    action = wezterm.action.SpawnTab("CurrentPaneDomain") })
  table.insert(list, { key = "[", mods = mod_primary,
    action = wezterm.action.ActivateTabRelative(-1) })
  table.insert(list, { key = "]", mods = mod_primary,
    action = wezterm.action.ActivateTabRelative(1) })
  table.insert(list, { key = "W", mods = mod_primary,
    action = wezterm.action.ShowLauncherArgs({ flags = "WORKSPACES" }) })

  table.insert(list, { key = "z", mods = "LEADER",
    action = wezterm.action.TogglePaneZoomState })
  table.insert(list, { key = "w", mods = "LEADER",
    action = wezterm.action.CloseCurrentPane({ confirm = false }) })
  table.insert(list, { key = "p", mods = "LEADER",
    action = wezterm.action.ShowLauncher })

  -- Placeholders. apply() swaps in the real plugin handles; build() stays pure
  -- so the whole table can be asserted without loading a single plugin.
  table.insert(list, { key = "s", mods = "LEADER", action = wezterm.action.Nop })
  table.insert(list, { key = "r", mods = "LEADER", action = wezterm.action.Nop })
  table.insert(list, { key = "d", mods = "LEADER", action = wezterm.action.Nop })

  return list
end

-- fuzzy_load hands back a path-like id: "workspace/name.json". load_state wants
-- the bare name and the type separately, and reading the state does not restore
-- it -- restore_workspace does. Anything that is not a workspace is ignored:
-- only workspaces are ever saved here.
local function restore_selected(plugins, id)
  local kind = id:match("^([^/]+)")
  local name = id:match("([^/]+)$"):match("(.+)%..+$")
  if kind ~= "workspace" then return end
  plugins.resurrect.workspace_state.restore_workspace(
    plugins.resurrect.state_manager.load_state(name, "workspace"),
    { relative = true, restore_text = true })
end

function M.apply(config, plugins, platform)
  config.leader = { key = "q", mods = "CTRL", timeout_milliseconds = 1000 }
  config.keys = M.build(platform.mod_primary)

  for index = #config.keys, 1, -1 do
    local entry = config.keys[index]
    if entry.mods == "LEADER" and entry.key == "s" then
      entry.action = wezterm.action_callback(function(window, _pane)
        plugins.resurrect.state_manager.save_state(
          plugins.resurrect.workspace_state.get_workspace_state())
        window:toast_notification("resurrect", "workspace saved", nil, 3000)
      end)
    elseif entry.mods == "LEADER" and entry.key == "r" then
      entry.action = wezterm.action_callback(function(window, pane)
        plugins.resurrect.fuzzy_loader.fuzzy_load(window, pane, function(id)
          restore_selected(plugins, id)
        end)
      end)
    elseif entry.mods == "LEADER" and entry.key == "d" then
      -- quick_domains exposes no action to bind; it appends its own entries to
      -- config.keys instead, so the placeholder makes way for them below.
      table.remove(config.keys, index)
    end
  end

  -- Has to run after config.keys is populated, and its own defaults sit on
  -- CTRL+d, CTRL+v and CTRL+h -- the last of which is smart-splits navigation.
  -- All three move behind the leader. Its split names follow WezTerm's, so
  -- hsplit -- the one that opens beside -- takes V, matching the plain splits.
  plugins.domains.apply_to_config(config, {
    keys = {
      attach = { mods = "LEADER", key = "d", tbl = "" },
      hsplit = { mods = "LEADER", key = "V", tbl = "" },
      vsplit = { mods = "LEADER", key = "H", tbl = "" },
    },
  })

  config.mouse_bindings = {
    {
      event = { Down = { streak = 1, button = "Left" } },
      mods = "CTRL|SHIFT",
      action = wezterm.action.StartWindowDrag,
    },
  }
end

return M
