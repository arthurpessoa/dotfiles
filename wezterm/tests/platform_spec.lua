local platform = require("modules.platform")
local stub = require("stub_wezterm")

describe("platform.detect", function()
  it("recognises windows", function()
    local p = platform.detect("x86_64-pc-windows-msvc")
    assert_eq(p.os, "windows")
    assert_eq(p.default_prog[1], "pwsh.exe")
    assert_eq(p.mod_primary, "CTRL|SHIFT")
  end)

  it("recognises macos and uses CMD", function()
    local p = platform.detect("aarch64-apple-darwin")
    assert_eq(p.os, "macos")
    assert_eq(p.mod_primary, "CMD")
  end)

  it("recognises linux", function()
    local p = platform.detect("x86_64-unknown-linux-gnu")
    assert_eq(p.os, "linux")
    assert_eq(p.mod_primary, "CTRL|SHIFT")
  end)

  it("points at the platform neovim config directory", function()
    assert_true(platform.detect("x86_64-pc-windows-msvc").nvim_config_dir:find("nvim", 1, true) ~= nil)
    assert_true(platform.detect("x86_64-unknown-linux-gnu").nvim_config_dir:find(".config", 1, true) ~= nil)
  end)

  it("gives windows an acrylic backdrop", function()
    local p = platform.detect("x86_64-pc-windows-msvc")
    assert_eq(p.backdrop.key, "win32_system_backdrop")
    assert_eq(p.backdrop.value, "Acrylic")
  end)

  it("gives macos a background blur backdrop", function()
    local p = platform.detect("aarch64-apple-darwin")
    assert_eq(p.backdrop.key, "macos_window_background_blur")
    assert_eq(p.backdrop.value, 30)
  end)

  it("gives linux no backdrop", function()
    local p = platform.detect("x86_64-unknown-linux-gnu")
    assert_nil(p.backdrop)
  end)

  it("gives windows a two-line cpu and memory sample command", function()
    local command = platform.detect("x86_64-pc-windows-msvc").sysinfo_command
    assert_true(command:find("Win32_Processor", 1, true) ~= nil)
    assert_true(command:find("Win32_OperatingSystem", 1, true) ~= nil)
  end)

  it("leaves the other platforms without a sample command", function()
    assert_nil(platform.detect("x86_64-unknown-linux-gnu").sysinfo_command)
    assert_nil(platform.detect("aarch64-apple-darwin").sysinfo_command)
  end)
end)

describe("platform.shell_cmd", function()
  it("wraps a command for powershell on windows", function()
    local argv = platform.shell_cmd("windows", "git status")
    assert_eq(argv[1], "pwsh.exe")
    assert_eq(argv[2], "-NoProfile")
    assert_eq(argv[#argv], "git status")
  end)

  it("wraps a command for sh elsewhere", function()
    local argv = platform.shell_cmd("linux", "git status")
    assert_eq(argv[1], "sh")
    assert_eq(argv[2], "-c")
    assert_eq(argv[3], "git status")
  end)
end)

describe("platform.current", function()
  -- current() memoises into a module-local upvalue that this file's own
  -- describe blocks above never touch (they call detect() directly), so
  -- entering this block is guaranteed to be the first call to current()
  -- in the whole suite: nothing else requires modules.platform.
  it("detects the triple in effect on its first call", function()
    stub.__set_triple("aarch64-apple-darwin")
    local p = platform.current()
    assert_eq(p.os, "macos")
  end)

  it("keeps returning the first result after the triple changes", function()
    stub.__set_triple("x86_64-unknown-linux-gnu")
    local p = platform.current()
    -- Still macos: memoised from the previous case, not re-detected.
    assert_eq(p.os, "macos")
  end)
end)
