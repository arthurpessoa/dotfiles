-- Finding the JDKs on this machine, so jdtls starts on one new enough to run
-- and so a project can be compiled against whichever one it targets.
--
-- SDKMAN is the tool that would normally answer both questions, but it is a
-- bash program with no native Windows build. Its layout is probed anyway, and
-- a project's .sdkmanrc is honoured, so this module needs no change if the
-- same config is later run under WSL or Linux where SDKMAN is real.
--
-- Versions are read from each installation's `release` file rather than by
-- running `java -version`: this runs during LSP setup, and spawning one
-- process per candidate would be felt.
local M = {}

-- jdtls itself will not start on anything older. This is separate from the
-- versions a project may target, which is what runtimes() is for.
M.JDTLS_MIN_MAJOR = 21

-- kotlin-language-server bundles an IntelliJ-derived JavaVersion parser that
-- throws instead of falling back on a version string newer than it shipped
-- against -- confirmed: JDK 25 crashes it outright with
-- "IllegalArgumentException: 25.0.1" during startup. Its compiler (2.1.0)
-- predates JDK 25 by about a year, so this ceiling tracks the last major the
-- server could plausibly have been built and tested against. The floor is
-- generous -- the server itself only needs a reasonably modern JVM to run.
M.KOTLIN_LSP_MIN_MAJOR = 17
M.KOTLIN_LSP_MAX_MAJOR = 24

function M.parse_release(text)
  if not text then
    return nil
  end
  -- Anchored to a line start so JAVA_VERSION_DATE cannot match.
  local value = text:match('\nJAVA_VERSION="?([^"\r\n]+)') or text:match('^JAVA_VERSION="?([^"\r\n]+)')
  return value
end

function M.major(version)
  if not version then
    return nil
  end
  local first, second = version:match("^(%d+)%.(%d+)")
  if first == "1" and second then
    -- 1.8.0_402 is Java 8. Anything before 9 is named this way.
    return tonumber(second)
  end
  local lone = version:match("^(%d+)")
  return lone and tonumber(lone) or nil
end

function M.parse_sdkmanrc(text)
  if not text then
    return nil
  end
  return text:match("\njava=([^\r\n]+)") or text:match("^java=([^\r\n]+)")
end

function M.runtime_name(major)
  -- The jdtls schema keeps the legacy spelling below 9.
  if major < 9 then
    return "JavaSE-1." .. major
  end
  return "JavaSE-" .. major
end

function M.sort_installs(installs)
  table.sort(installs, function(a, b)
    if a.major ~= b.major then
      return a.major > b.major
    end
    return a.version > b.version
  end)
  return installs
end

function M.pick_for_jdtls(installs, min)
  min = min or M.JDTLS_MIN_MAJOR
  for _, install in ipairs(M.sort_installs(installs)) do
    if install.major >= min then
      return install
    end
  end
  return nil
end

-- Unlike pick_for_jdtls, this has a ceiling as well as a floor: newest install
-- with min <= major <= max, so a bleeding-edge JDK that would crash
-- kotlin-language-server is skipped in favour of an older one that works.
function M.pick_for_kotlin_lsp(installs, min, max)
  min = min or M.KOTLIN_LSP_MIN_MAJOR
  max = max or M.KOTLIN_LSP_MAX_MAJOR
  for _, install in ipairs(M.sort_installs(installs)) do
    if install.major >= min and install.major <= max then
      return install
    end
  end
  return nil
end

local function read_file(path)
  local fd = io.open(path, "r")
  if not fd then
    return nil
  end
  local text = fd:read("*a")
  fd:close()
  return text
end

-- Every directory that might hold a JDK, in no particular order -- sorting is
-- by version, not by source, so a system JDK can win over a hand-placed one.
function M.roots()
  local home = vim.uv.os_homedir()
  return {
    home .. "/.sdkman/candidates/java", -- SDKMAN, when it is real
    home .. "/.jdks", -- IntelliJ
    home .. "/scoop/apps",
    "C:/Projects/jvm",
    "C:/Program Files/Java",
    "C:/Program Files/Eclipse Adoptium",
    "C:/Program Files/Microsoft",
    "C:/Program Files/Zulu",
    "/usr/lib/jvm",
  }
end

local function looks_like_jdk(dir)
  local exe = vim.fn.has("win32") == 1 and "/bin/java.exe" or "/bin/java"
  return vim.uv.fs_stat(dir .. exe) ~= nil
end

local function install_at(dir)
  if not looks_like_jdk(dir) then
    return nil
  end
  local version = M.parse_release(read_file(dir .. "/release"))
  local major = M.major(version)
  if not major then
    return nil
  end
  return { path = dir, version = version, major = major }
end

function M.discover(roots)
  local seen, out = {}, {}

  local function consider(dir)
    if not dir or dir == "" then
      return
    end
    local real = vim.uv.fs_realpath(dir)
    if not real or seen[real] then
      return
    end
    seen[real] = true
    local install = install_at(real)
    if install then
      table.insert(out, install)
    end
  end

  -- JAVA_HOME may point at a JDK none of the roots cover.
  consider(vim.env.JAVA_HOME)

  for _, root in ipairs(roots or M.roots()) do
    local handle = vim.uv.fs_scandir(root)
    while handle do
      local name, kind = vim.uv.fs_scandir_next(handle)
      if not name then
        break
      end
      if kind == "directory" or kind == "link" then
        consider(root .. "/" .. name)
        -- scoop keeps the usable copy behind a `current` link.
        consider(root .. "/" .. name .. "/current")
      end
    end
  end

  return M.sort_installs(out)
end

-- The default runtime: SDKMAN's `current` link when it exists, otherwise the
-- newest install. A project's .sdkmanrc overrides both, matched loosely because
-- "21.0.5-tem" names a distribution this module cannot see.
local function default_path(installs)
  local sdkman_current = vim.uv.os_homedir() .. "/.sdkman/candidates/java/current"
  local real = vim.uv.fs_realpath(sdkman_current)
  if real then
    return real
  end

  local rc = read_file((vim.uv.cwd() or ".") .. "/.sdkmanrc")
  local wanted = M.parse_sdkmanrc(rc)
  local wanted_major = wanted and M.major(wanted) or nil
  if wanted_major then
    for _, install in ipairs(installs) do
      if install.major == wanted_major then
        return install.path
      end
    end
  end

  return installs[1] and installs[1].path or nil
end

function M.runtimes()
  local installs = M.discover()
  local default = default_path(installs)
  local out, named = {}, {}
  for _, install in ipairs(installs) do
    local name = M.runtime_name(install.major)
    -- One entry per JavaSE level; the newest patch of each wins because
    -- discover() is already sorted.
    if not named[name] then
      named[name] = true
      table.insert(out, {
        name = name,
        path = install.path,
        default = install.path == default or nil,
      })
    end
  end
  return out
end

function M.jdtls_java(min)
  local pick = M.pick_for_jdtls(M.discover(), min)
  if not pick then
    return nil
  end
  return pick.path .. (vim.fn.has("win32") == 1 and "/bin/java.exe" or "/bin/java")
end

-- kotlin-language-server takes no --java-executable equivalent: it resolves
-- java from %JAVA_HOME%\bin\java.exe with no override flag, so the only lever
-- is JAVA_HOME itself -- hence a JDK root, not a java binary, unlike
-- jdtls_java() above.
function M.kotlin_lsp_home(min, max)
  local pick = M.pick_for_kotlin_lsp(M.discover(), min, max)
  return pick and pick.path or nil
end

return M
