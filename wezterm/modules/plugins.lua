local wezterm = require("wezterm")

local M = {}

local RESURRECT = "https://github.com/MLFlexer/resurrect.wezterm"
local STATE_TYPES = { "workspace", "window", "tab" }

-- resurrect creates its state directories on load with os.execute('mkdir /p
-- "<dir>"'). On Windows that is wrong twice over. `/p` is a POSIX flag cmd does
-- not take, so the directories are never created and cmd answers "The syntax of
-- the command is incorrect"; and os.execute runs through cmd.exe, which --
-- wezterm-gui owning no console -- Windows hands a console window of its own.
-- Three of them flash open and shut on every config load and every reload.
--
-- So the call is swallowed while the plugin loads and the directories are made
-- below instead, through background_child_process. Measured with a window
-- enumerator across a 15-second run: the plugin alone opens console windows,
-- and background_child_process opens none.
local function without_console(load)
  local saved = os.execute
  os.execute = function() return true end
  local ok, result = pcall(load)
  os.execute = saved
  if not ok then error(result, 0) end
  return result
end

local function directory_exists(path)
  return (pcall(wezterm.read_dir, path))
end

-- One spawn for however many are missing, and none at all in the normal case
-- where they already exist.
local function ensure_state_dirs(platform, resurrect)
  local dir = resurrect.state_manager and resurrect.state_manager.save_state_dir
  if not dir then return end

  local base = dir:gsub("[\\/]+$", "")
  local missing = {}
  for _, kind in ipairs(STATE_TYPES) do
    local path = base .. "/" .. kind
    if not directory_exists(path) then
      table.insert(missing, string.format('"%s"', path))
    end
  end
  if #missing == 0 then return end

  local list = table.concat(missing, ",")
  wezterm.background_child_process(platform.shell_cmd(
    platform.os == "windows"
      and ("New-Item -ItemType Directory -Force -Path " .. list .. " | Out-Null")
      or ("mkdir -p " .. table.concat(missing, " "))))
end

function M.load(platform)
  -- Only resurrect's load is silenced. Swallowing os.execute around all five
  -- would hide a call another plugin makes for its own good reasons, on every
  -- platform, for the sake of a fault in one of them.
  local loaded = {
    kanagawa = wezterm.plugin.require("https://github.com/sravioli/kanagawa.wz"),
    tabline = wezterm.plugin.require("https://github.com/michaelbrusegard/tabline.wez"),
    agent_deck = wezterm.plugin.require("https://github.com/Eric162/wezterm-agent-deck"),
    resurrect = without_console(function() return wezterm.plugin.require(RESURRECT) end),
    domains = wezterm.plugin.require("https://github.com/DavidRR-F/quick_domains.wezterm"),
  }

  ensure_state_dirs(platform, loaded.resurrect)

  return loaded
end

return M
