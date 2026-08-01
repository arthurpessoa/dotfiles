local wezterm = require("wezterm")
local bar = require("modules.bar")

-- bar.lua formats and nothing else, so the only thing worth asserting here is
-- the shape of the section table it hands tabline -- in particular what it does
-- on a platform the config has no machine-load sample for.
local function apply_with(platform)
  local captured
  local plugins = {
    tabline = {
      setup = function(cfg) captured = cfg end,
      apply_to_config = function() end,
    },
    -- Shaped like a real wezterm colour scheme, because bar.lua reads more of
    -- it than the background: the tab process component takes its two title
    -- colours from ansi[5] and foreground.
    kanagawa = {
      get = function()
        return {
          background = "#1F1F28",
          foreground = "#DCD7BA",
          ansi = { "#090618", "#C34043", "#76946A", "#C0A36E", "#7E9CD8", "#957FB8", "#6A9589", "#C8C093" },
          tab_bar = { inactive_tab = { bg_color = "#000000" } },
        }
      end,
    },
    agent_deck = {},
    resurrect = {},
    domains = {},
  }
  local state = { activity = {}, agent = {}, git = {} }
  bar.apply({}, plugins, platform, state)
  return captured
end

local function windows()
  return {
    os = "windows",
    temp_dir = "C:/Temp",
    sysinfo_command = "sample",
    shell_cmd = function(command) return { "pwsh", "-Command", command } end,
  }
end

local function linux()
  return {
    os = "linux",
    temp_dir = "/tmp",
    sysinfo_command = nil,
    shell_cmd = function(command) return { "sh", "-c", command } end,
  }
end

describe("bar.apply", function()
  it("fills the load section where there is a sample command", function()
    local sections = apply_with(windows()).sections
    assert_eq(#sections.tabline_y, 1)
    assert_eq(type(sections.tabline_y[1]), "function")
  end)

  it("leaves the load section empty where there is none", function()
    -- Empty rather than absent: tabline falls back to its own datetime and
    -- battery components for a section that is not named at all, and its cpu
    -- and ram components shell out on every status tick.
    local sections = apply_with(linux()).sections
    assert_eq(#sections.tabline_y, 0)
  end)

  it("keeps the rest of the bar on every platform", function()
    local sections = apply_with(linux()).sections
    for _, name in ipairs({ "tabline_a", "tabline_b", "tabline_c", "tabline_x", "tabline_z" }) do
      assert_true(sections[name] ~= nil, "missing section " .. name)
    end
    assert_true(wezterm.__handlers["update-status"] ~= nil, "update-status never registered")
    assert_true(wezterm.__handlers["user-var-changed"] ~= nil, "user-var-changed never registered")
  end)
end)
