local wezterm = require("wezterm")

local M = {}

local function env(name, fallback)
  return os.getenv(name) or fallback
end

function M.shell_cmd(os_name, command)
  if os_name == "windows" then
    return { "pwsh.exe", "-NoProfile", "-NonInteractive", "-Command", command }
  end
  return { "sh", "-c", command }
end

function M.detect(triple)
  local home = env("HOME", env("USERPROFILE", "."))

  if triple:find("windows", 1, true) then
    return {
      os = "windows",
      default_prog = { "pwsh.exe", "-NoLogo" },
      mod_primary = "CTRL|SHIFT",
      temp_dir = env("TEMP", home),
      nvim_config_dir = env("LOCALAPPDATA", home) .. "\\nvim",
      shell_cmd = function(command) return M.shell_cmd("windows", command) end,
    }
  end

  local os_name = triple:find("darwin", 1, true) and "macos" or "linux"
  return {
    os = os_name,
    default_prog = { env("SHELL", "/bin/sh"), "-l" },
    mod_primary = os_name == "macos" and "CMD" or "CTRL|SHIFT",
    temp_dir = env("TMPDIR", "/tmp"),
    nvim_config_dir = home .. "/.config/nvim",
    shell_cmd = function(command) return M.shell_cmd(os_name, command) end,
  }
end

local cached
function M.current()
  cached = cached or M.detect(wezterm.target_triple)
  return cached
end

return M
