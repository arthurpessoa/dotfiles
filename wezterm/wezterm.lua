local wezterm = require("wezterm")
local config = wezterm.config_builder()

----------------------------------------------------------
-- Plugins
----------------------------------------------------------

local kanagawa = wezterm.plugin.require(
  "https://github.com/sravioli/kanagawa.wz"
)

local agent_deck = wezterm.plugin.require(
  "https://github.com/Eric162/wezterm-agent-deck"
)

----------------------------------------------------------
-- Theme
----------------------------------------------------------

kanagawa.apply_to_config(config)

config.font = wezterm.font("JetBrainsMono Nerd Font")
config.font_size = 12.5

config.window_background_opacity = 0.97

config.window_padding = {
  left = 8,
  right = 8,
  top = 8,
  bottom = 8,
}
config.win32_system_backdrop = "Acrylic"
----------------------------------------------------------
-- General
----------------------------------------------------------

config.enable_tab_bar = true
config.use_fancy_tab_bar = false
config.hide_tab_bar_if_only_one_tab = false

config.window_decorations = "RESIZE"

config.scrollback_lines = 100000
config.audible_bell = "Disabled"

----------------------------------------------------------
-- Default shell
----------------------------------------------------------

config.default_prog = {
  "powershell.exe",
  "-NoLogo",
}

----------------------------------------------------------
-- Agent Deck
----------------------------------------------------------

agent_deck.apply_to_config(config, {
  update_interval = 500,

  colors = {
    working = "#98BB6C",
    waiting = "#E6C384",
    idle = "#7FB4CA",
    inactive = "#727169",
  },

  icons = {
    style = "unicode",

    unicode = {
      working = "●",
      waiting = "◔",
      idle = "○",
      inactive = "◌",
    },
  },

  notifications = {
    enabled = true,
    on_waiting = true,
  },
})

----------------------------------------------------------
-- Mouse bindings
----------------------------------------------------------

config.mouse_bindings = {
  {
    event = {
      Down = {
        streak = 1,
        button = "Left",
      },
    },

    mods = "CTRL|SHIFT",

    action = wezterm.action.StartWindowDrag,
  },
}

----------------------------------------------------------
-- Pane splitting
----------------------------------------------------------

local function split(direction)
  return wezterm.action_callback(function(window, pane)
    local cwd = pane:get_current_working_dir()

    local action

    if direction == "horizontal" then
      action = wezterm.action.SplitHorizontal({
        cwd = cwd,
      })
    else
      action = wezterm.action.SplitVertical({
        cwd = cwd,
      })
    end

    window:perform_action(action, pane)
  end)
end

----------------------------------------------------------
-- Leader
----------------------------------------------------------

config.leader = {
  key = "q",
  mods = "CTRL",
  timeout_milliseconds = 1000,
}

----------------------------------------------------------
-- Key bindings
----------------------------------------------------------

config.keys = {

  --------------------------------------------------------
  -- Pane navigation
  --------------------------------------------------------

  {
    key = "h",
    mods = "LEADER",
    action = wezterm.action.ActivatePaneDirection("Left"),
  },

  {
    key = "j",
    mods = "LEADER",
    action = wezterm.action.ActivatePaneDirection("Down"),
  },

  {
    key = "k",
    mods = "LEADER",
    action = wezterm.action.ActivatePaneDirection("Up"),
  },

  {
    key = "l",
    mods = "LEADER",
    action = wezterm.action.ActivatePaneDirection("Right"),
  },

  --------------------------------------------------------
  -- Pane splitting
  --------------------------------------------------------

  {
    key = "v",
    mods = "CTRL|SHIFT",
    action = split("vertical"),
  },

  {
    key = "h",
    mods = "CTRL|SHIFT",
    action = split("horizontal"),
  },

  --------------------------------------------------------
  -- Pane management
  --------------------------------------------------------

  {
    key = "z",
    mods = "LEADER",
    action = wezterm.action.TogglePaneZoomState,
  },

  {
    key = "w",
    mods = "LEADER",
    action = wezterm.action.CloseCurrentPane({
      confirm = false,
    }),
  },

  --------------------------------------------------------
  -- Tabs
  --------------------------------------------------------

  {
    key = "t",
    mods = "CTRL|SHIFT",
    action = wezterm.action.SpawnTab("CurrentPaneDomain"),
  },

  {
    key = "[",
    mods = "CTRL|SHIFT",
    action = wezterm.action.ActivateTabRelative(-1),
  },

  {
    key = "]",
    mods = "CTRL|SHIFT",
    action = wezterm.action.ActivateTabRelative(1),
  },

  --------------------------------------------------------
  -- Launcher
  --------------------------------------------------------

  {
    key = "p",
    mods = "LEADER",
    action = wezterm.action.ShowLauncher,
  },

  --------------------------------------------------------
  -- Workspaces
  --------------------------------------------------------

  {
    key = "W",
    mods = "CTRL|SHIFT",
    action = wezterm.action.ShowLauncherArgs({
      flags = "WORKSPACES",
    }),
  },
}

----------------------------------------------------------
-- Right status
----------------------------------------------------------

wezterm.on("update-right-status", function(window, pane)
  local process = pane:get_foreground_process_name() or ""

  process = process:gsub("^.*[\\/]", "")

  local workspace = window:active_workspace()

  local date = wezterm.strftime("%H:%M")

  local status = "○"

  pcall(function()
    status = agent_deck.get_status()
  end)

  window:set_right_status(wezterm.format({
    { Text = "󰚩 " .. status },
    { Text = "   " },
    { Text = " " .. process },
    { Text = "   " },
    { Text = "󰓩 " .. workspace },
    { Text = "   " },
    { Text = "󰥔 " .. date },
    { Text = " " },
  }))
end)

----------------------------------------------------------
-- Tab title
----------------------------------------------------------

wezterm.on("format-tab-title", function(tab)
  local title = tab.active_pane.title

  return {
    { Text = " " },
    { Text = tostring(tab.tab_index + 1) },
    { Text = ":" },
    { Text = " " },
    { Text = title },
    { Text = " " },
  }
end)

return config
