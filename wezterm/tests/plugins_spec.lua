local wezterm = require("wezterm")
local plugins = require("modules.plugins")

local RESURRECT = "https://github.com/MLFlexer/resurrect.wezterm"
local STATE_DIR = "C:/plugins/resurrect/state/"

local function platform()
  return { shell_cmd = function(command) return { "pwsh.exe", "-Command", command } end }
end

-- Stands in for the real plugin: its init runs a broken mkdir through
-- os.execute, which is exactly the call that opens a console window.
local function arrange(executed)
  wezterm.__reset()
  wezterm.__plugin_factories[RESURRECT] = function()
    os.execute('mkdir /p "' .. STATE_DIR .. 'workspace"')
    return { state_manager = { save_state_dir = STATE_DIR } }
  end
  local saved = os.execute
  local spy = function(command)
    table.insert(executed, command)
    return true
  end
  os.execute = spy
  return function() os.execute = saved end, spy
end

local function spawned_command()
  local args = wezterm.__spawned[1]
  return args and args[#args] or nil
end

describe("plugins.load", function()
  it("returns every plugin the config uses", function()
    local executed = {}
    local restore = arrange(executed)
    local loaded = plugins.load(platform())
    restore()
    for _, name in ipairs({ "kanagawa", "tabline", "agent_deck", "resurrect", "domains" }) do
      assert_true(loaded[name] ~= nil, "missing plugin " .. name)
    end
  end)

  it("keeps resurrect's directory creation off the console", function()
    local executed = {}
    local restore = arrange(executed)
    plugins.load(platform())
    restore()
    assert_eq(#executed, 0)
  end)

  it("puts os.execute back once the plugins are loaded", function()
    local executed = {}
    local restore, spy = arrange(executed)
    plugins.load(platform())
    local after = os.execute
    restore()
    assert_eq(after, spy)
  end)

  it("creates the state directories resurrect left behind", function()
    local executed = {}
    local restore = arrange(executed)
    wezterm.__dirs = { [STATE_DIR .. "workspace"] = true }
    plugins.load(platform())
    restore()
    local command = spawned_command()
    assert_true(command ~= nil, "nothing was spawned")
    assert_true(command:find("window", 1, true) ~= nil, "window directory not created")
    assert_true(command:find("tab", 1, true) ~= nil, "tab directory not created")
    assert_true(command:find("workspace", 1, true) == nil, "workspace already existed")
  end)

  it("spawns nothing when the state directories are all there", function()
    local executed = {}
    local restore = arrange(executed)
    wezterm.__dirs = nil
    plugins.load(platform())
    restore()
    assert_eq(#wezterm.__spawned, 0)
  end)
end)
