local wezterm = require("wezterm")

local M = {}

local function env(name, fallback)
  return os.getenv(name) or fallback
end

-- One sample of the machine's load: line 1 is CPU percent, line 2 is used RAM
-- in GiB. bar.lua runs it through a background process and reads the result
-- from a file, so its latency never reaches the status callback.
--
-- Only Windows has one. tabline.wez ships cpu and ram components, but they call
-- `wmic`, which Windows 11 no longer installs, and they call it synchronously
-- on the status callback. Linux and macOS are left without a command on
-- purpose: an unverified one would print a wrong number instead of nothing.
-- The script block matters: PowerShell attaches a redirection to the last
-- statement only, so without it the caller's `> file` would capture the memory
-- line and drop the CPU one.
local WINDOWS_SYSINFO = table.concat({
  "&{",
  "$p = Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average;",
  "$o = Get-CimInstance Win32_OperatingSystem;",
  "'{0:N0}' -f $p.Average;",
  "'{0:N1}' -f (($o.TotalVisibleMemorySize - $o.FreePhysicalMemory) / 1048576)",
  "}",
}, " ")

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
      backdrop = { key = "win32_system_backdrop", value = "Acrylic" },
      sysinfo_command = WINDOWS_SYSINFO,
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
    backdrop = os_name == "macos" and { key = "macos_window_background_blur", value = 30 } or nil,
    sysinfo_command = nil,
  }
end

local cached
function M.current()
  cached = cached or M.detect(wezterm.target_triple)
  return cached
end

return M
