local wezterm = require("wezterm")

-- Everything else in this config is required by module name, so the directory
-- holding this file has to be on the search path. config_dir is whatever
-- directory WezTerm actually loaded this file from, which keeps the config
-- working through the ~/.config/wezterm junction and through --config-file.
package.path = wezterm.config_dir .. "/?.lua;" .. package.path

local config = wezterm.config_builder()

local platform = require("modules.platform").current()
local plugins = require("modules.plugins").load()
local activity = require("modules.activity")
local agent = require("modules.agent")

local state = {
  activity = activity.new_store(),
  agent = agent.new_store(),
  git = {},
}

-- Order matters. bar.apply calls tabline's apply_to_config, which sets
-- use_fancy_tab_bar, window_padding and status_update_interval for itself;
-- theme.apply runs afterwards so that the bar's placement at the bottom, the
-- padding and the tick rate are this config's choices and not the plugin's.
require("modules.bar").apply(config, plugins, platform, state)
require("modules.theme").apply(config, plugins, platform)
require("modules.keys").apply(config, plugins, platform)

-- Machine-local overrides. Gitignored, loaded last, and absent by default.
local ok, overrides = pcall(dofile, wezterm.config_dir .. "/local.lua")
if ok and type(overrides) == "table" then
  for key, value in pairs(overrides) do
    config[key] = value
  end
end

return config
