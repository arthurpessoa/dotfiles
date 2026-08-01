local wezterm = require("wezterm")

local M = {}

function M.load()
  return {
    kanagawa = wezterm.plugin.require("https://github.com/sravioli/kanagawa.wz"),
    tabline = wezterm.plugin.require("https://github.com/michaelbrusegard/tabline.wez"),
    agent_deck = wezterm.plugin.require("https://github.com/Eric162/wezterm-agent-deck"),
    resurrect = wezterm.plugin.require("https://github.com/MLFlexer/resurrect.wezterm"),
    domains = wezterm.plugin.require("https://github.com/DavidRR-F/quick_domains.wezterm"),
  }
end

return M
