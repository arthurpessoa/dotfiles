# WezTerm Configuration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the single-file `~/.wezterm.lua` with a modular, cross-platform WezTerm configuration in `~/.dotfiles/wezterm/`, driving a bottom powerline bar with per-process icons, an activity spinner, git state, AI agent state, desktop notifications, and Neovim integration.

**Architecture:** `wezterm.lua` builds the config and hands it to each module in turn, holding no logic itself. `activity.lua`, `git.lua`, and `agent.lua` are pure state providers with no WezTerm dependency in their testable core — each exposes plain functions over plain tables, so they run under `nvim -l` with a stubbed `wezterm` module. `bar.lua` is the only module that formats, and `platform.lua` is the only module that inspects the OS.

**Tech Stack:** Lua (WezTerm's 5.4 at runtime, LuaJIT/5.1 under `nvim -l` for tests), WezTerm nightly, `tabline.wez`, `kanagawa.wz`, `wezterm-agent-deck`, `resurrect.wezterm`, `quick_domains.wezterm`, LazyVim, `smart-splits.nvim`.

**Spec:** `docs/specs/2026-08-01-wezterm-dotfiles-design.md`

## Global Constraints

- Repo root is `~/.dotfiles`. All paths below are relative to it unless absolute.
- Tests must run under **LuaJIT (Lua 5.1)** because the runner is `nvim -l`. Do not use `\u{XXXX}` string escapes, integer division `//`, `goto`, or `utf8.*` — none exist in 5.1. Write glyphs as literal UTF-8 characters in the source file.
- No module except `platform.lua` may read `wezterm.target_triple` or otherwise branch on the operating system.
- No module except `bar.lua` may produce formatted output for the status bar.
- `activity.lua`, `git.lua`, and `agent.lua` must not call `os.time`, `os.clock`, or any WezTerm timer directly. Time enters as a `now` parameter so tests can control it.
- Spinner frames are exactly these 8 characters in this order: `⠋⠙⠹⠸⠼⠴⠦⠧`.
- Kanagawa palette values used throughout: green `#98BB6C`, amber `#E6C384`, blue `#7E9CD8`, aqua `#7AA89F`, red `#E46876`, grey `#727169`, fg `#DCD7BA`.
- Long-run notification threshold is **30 seconds**, and notifications fire only when the pane's tab is not the active tab.
- Git poll interval is **4 seconds**; bar/status interval is **120 milliseconds**.
- Every task ends with a commit. Commit messages use Conventional Commits and are written in normal prose, not shorthand.
- Never delete an existing config directory. Rename to `<name>.bak-<timestamp>` and leave it in place.

---

## File Structure

| File | Responsibility |
| --- | --- |
| `wezterm/wezterm.lua` | Entry point. Builds the config object, calls each module's `apply`. No logic. |
| `wezterm/modules/platform.lua` | The only OS branch. Exports shell, modifiers, temp dir, backdrop, nvim config dir. |
| `wezterm/modules/theme.lua` | Colours, font, padding, window chrome, bottom bar placement. |
| `wezterm/modules/plugins.lua` | `wezterm.plugin.require` calls, returns the plugin handles. |
| `wezterm/modules/icons.lua` | Process basename → glyph, colour, and `busy`/`shell` kind. Feeds tabline's `process_to_icon`. |
| `wezterm/modules/activity.lua` | Per-pane busy state machine, spinner frame maths, long-run notification decision. |
| `wezterm/modules/git.lua` | `git status --porcelain=v2 --branch` parser, per-repo cache, segment rendering. |
| `wezterm/modules/agent.lua` | AI agent state classification, transitions, notification decision. |
| `wezterm/modules/bar.lua` | tabline setup and the three custom components. The only formatter. |
| `wezterm/modules/keys.lua` | Leader, key table, smart-splits forwarding. |
| `wezterm/tests/run.lua` | Test runner. Discovers and runs `*_spec.lua`. |
| `wezterm/tests/harness.lua` | `describe`/`it`/`assert_eq` in ~40 lines. No dependency. |
| `wezterm/tests/stub_wezterm.lua` | Fake `wezterm` module registered via `package.preload`. |
| `wezterm/tests/*_spec.lua` | One spec per pure module. |
| `nvim/lua/plugins/smart-splits.lua` | `smart-splits.nvim` spec and its keymaps. |
| `nvim/lua/config/autocmds.lua` | Existing file; gains the OSC user-var autocmd group. |

---

### Task 1: Repository skeleton, test harness, and safe linking

Moves the two existing configs into the repo and links them back, with backups, before any rewrite happens. Ends with a green (empty) test run and a terminal that still works exactly as it did.

**Files:**
- Create: `wezterm/tests/harness.lua`
- Create: `wezterm/tests/run.lua`
- Create: `wezterm/tests/stub_wezterm.lua`
- Create: `wezterm/tests/smoke_spec.lua`
- Create: `.gitignore`
- Move: `~/.wezterm.lua` → `wezterm/wezterm.lua`
- Move: `%LOCALAPPDATA%\nvim` → `nvim/`

**Interfaces:**
- Consumes: nothing.
- Produces: `harness.describe(name, fn)`, `harness.it(name, fn)`, `harness.assert_eq(actual, expected, msg)`, `harness.assert_nil(v, msg)`, `harness.assert_true(v, msg)`, `harness.run() -> failures:number`. Specs are files named `*_spec.lua` under `wezterm/tests/` that return nothing and call `describe`/`it` at load time. `stub_wezterm` registers a table under `package.preload.wezterm`.

- [ ] **Step 1: Write the test harness**

Create `wezterm/tests/harness.lua`:

```lua
local M = { groups = {}, current = nil }

function M.describe(name, fn)
  M.current = { name = name, cases = {} }
  table.insert(M.groups, M.current)
  fn()
  M.current = nil
end

function M.it(name, fn)
  table.insert(M.current.cases, { name = name, fn = fn })
end

local function fail(msg, extra)
  error(msg .. (extra and ("\n      " .. extra) or ""), 2)
end

function M.assert_eq(actual, expected, msg)
  if actual ~= expected then
    fail(msg or "values differ",
      string.format("expected %s, got %s", tostring(expected), tostring(actual)))
  end
end

function M.assert_nil(value, msg)
  if value ~= nil then fail(msg or "expected nil", tostring(value)) end
end

function M.assert_true(value, msg)
  if not value then fail(msg or "expected truthy", tostring(value)) end
end

function M.run()
  local failures, total = 0, 0
  for _, group in ipairs(M.groups) do
    print(group.name)
    for _, case in ipairs(group.cases) do
      total = total + 1
      local ok, err = pcall(case.fn)
      if ok then
        print("  ok   " .. case.name)
      else
        failures = failures + 1
        print("  FAIL " .. case.name)
        print("       " .. tostring(err))
      end
    end
  end
  print(string.format("\n%d passed, %d failed, %d total", total - failures, failures, total))
  return failures
end

return M
```

- [ ] **Step 2: Write the wezterm stub**

Create `wezterm/tests/stub_wezterm.lua`. Only the surface the pure modules touch is stubbed; anything else should be absent so a module that reaches for it fails loudly in tests.

```lua
local stub = {
  target_triple = "x86_64-pc-windows-msvc",
  nerdfonts = setmetatable({}, { __index = function(_, k) return "<" .. k .. ">" end }),
  format = function(items) return items end,
  log_info = function() end,
  log_error = function() end,
}

package.preload["wezterm"] = function() return stub end

return stub
```

- [ ] **Step 3: Write the runner**

Create `wezterm/tests/run.lua`. It runs from the repo root; `arg[0]` is unreliable under `nvim -l`, so the spec list is explicit and grows as specs are added.

```lua
package.path = "wezterm/?.lua;wezterm/tests/?.lua;" .. package.path
require("stub_wezterm")

local harness = require("harness")
_G.describe = harness.describe
_G.it = harness.it
_G.assert_eq = harness.assert_eq
_G.assert_nil = harness.assert_nil
_G.assert_true = harness.assert_true

local specs = {
  "smoke_spec",
}

for _, name in ipairs(specs) do
  require(name)
end

os.exit(harness.run() == 0 and 0 or 1)
```

- [ ] **Step 4: Write the smoke spec**

Create `wezterm/tests/smoke_spec.lua`:

```lua
describe("harness", function()
  it("compares equal values", function()
    assert_eq(1 + 1, 2)
  end)
end)
```

- [ ] **Step 5: Run the tests and watch them pass**

Run from `~/.dotfiles`: `nvim -l wezterm/tests/run.lua`

Expected: `harness` / `ok compares equal values` / `1 passed, 0 failed, 1 total`, exit code 0.

- [ ] **Step 6: Move the existing configs into the repo**

The current `~/.wezterm.lua` becomes the starting `wezterm/wezterm.lua` untouched, so the terminal keeps working while the modules are built. PowerShell, from `~/.dotfiles`:

```powershell
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
New-Item -ItemType Directory -Force wezterm | Out-Null
Copy-Item "$HOME\.wezterm.lua" "wezterm\wezterm.lua"
Move-Item "$HOME\.wezterm.lua" "$HOME\.wezterm.lua.bak-$stamp"

Move-Item "$env:LOCALAPPDATA\nvim" "$PWD\nvim"
New-Item -ItemType Junction -Path "$env:LOCALAPPDATA\nvim" -Target "$PWD\nvim" | Out-Null

New-Item -ItemType Directory -Force "$HOME\.config" | Out-Null
New-Item -ItemType Junction -Path "$HOME\.config\wezterm" -Target "$PWD\wezterm" | Out-Null
```

- [ ] **Step 7: Verify the terminal still works from the new location**

Run: `wezterm -n --config-file "$HOME\.dotfiles\wezterm\wezterm.lua" start -- pwsh`

Expected: a new window opens with the current top tab bar and right status. Close it. If it fails, the junction or the copy is wrong — fix before continuing, because every later task assumes this path loads.

Also confirm Neovim still starts: `nvim --headless "+qa"` exits 0.

- [ ] **Step 8: Write .gitignore**

Create `.gitignore`:

```gitignore
wezterm/local.lua
*.bak-*
nvim/lazy-lock.json.bak
.superpowers/
```

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "chore: move wezterm and neovim configs into the dotfiles repo

The previous ~/.wezterm.lua is copied in verbatim and the original is
kept as a timestamped backup. Config directories are junctions back
into the repo, so the running terminal is unaffected.

Adds a dependency-free Lua test harness run with 'nvim -l'."
```

---

### Task 2: icons.lua — process to glyph table

**Files:**
- Create: `wezterm/modules/icons.lua`
- Create: `wezterm/tests/icons_spec.lua`
- Modify: `wezterm/tests/run.lua` (add `"icons_spec"` to `specs`)

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `icons.lookup(process) -> { glyph:string, color:string|nil, kind:"busy"|"shell" }` — never returns nil; accepts a full path, a bare name, any case, with or without `.exe`.
  - `icons.basename(path) -> string` — lowercased, directory and `.exe` stripped.
  - `icons.process_to_icon() -> table` mapping name → `{ glyph, color }` for tabline.
  - `icons.FALLBACK` — the entry returned for unknown processes.

- [ ] **Step 1: Write the failing test**

Create `wezterm/tests/icons_spec.lua`:

```lua
local icons = require("modules.icons")

describe("icons.basename", function()
  it("strips a windows path and the exe suffix", function()
    assert_eq(icons.basename("C:\\Users\\a\\.cargo\\bin\\Cargo.EXE"), "cargo")
  end)

  it("strips a posix path", function()
    assert_eq(icons.basename("/usr/local/bin/nvim"), "nvim")
  end)

  it("passes a bare name through", function()
    assert_eq(icons.basename("pwsh"), "pwsh")
  end)
end)

describe("icons.lookup", function()
  it("marks build tools as busy", function()
    assert_eq(icons.lookup("cargo").kind, "busy")
    assert_eq(icons.lookup("gradlew").kind, "busy")
    assert_eq(icons.lookup("docker").kind, "busy")
  end)

  it("marks shells and editors as shell", function()
    assert_eq(icons.lookup("pwsh").kind, "shell")
    assert_eq(icons.lookup("nvim").kind, "shell")
  end)

  it("falls back for unknown processes", function()
    local entry = icons.lookup("some-unknown-binary")
    assert_eq(entry.kind, "shell")
    assert_eq(entry.glyph, icons.FALLBACK.glyph)
  end)

  it("resolves a full path the same as a bare name", function()
    assert_eq(icons.lookup("C:\\bin\\cargo.exe").glyph, icons.lookup("cargo").glyph)
  end)
end)

describe("icons.process_to_icon", function()
  it("exports every entry with a glyph", function()
    local map = icons.process_to_icon()
    assert_true(map.cargo ~= nil)
    assert_true(map.cargo.glyph ~= nil)
    assert_nil(map.cargo.kind, "tabline must not receive the kind field")
  end)
end)
```

Add `"icons_spec"` to the `specs` list in `wezterm/tests/run.lua`.

- [ ] **Step 2: Run the test to verify it fails**

Run: `nvim -l wezterm/tests/run.lua`
Expected: FAIL — `module 'modules.icons' not found`.

- [ ] **Step 3: Write the implementation**

Create `wezterm/modules/icons.lua`. Glyphs are literal UTF-8; do not use `\u{}`.

```lua
local M = {}

M.FALLBACK = { glyph = "", color = "#727169", kind = "shell" }

local BUSY = "busy"
local SHELL = "shell"

M.entries = {
  cargo   = { glyph = "", color = "#E46876", kind = BUSY },
  rustc   = { glyph = "", color = "#E46876", kind = BUSY },
  rustup  = { glyph = "", color = "#E46876", kind = BUSY },
  node    = { glyph = "", color = "#98BB6C", kind = BUSY },
  npm     = { glyph = "", color = "#98BB6C", kind = BUSY },
  pnpm    = { glyph = "", color = "#98BB6C", kind = BUSY },
  yarn    = { glyph = "", color = "#98BB6C", kind = BUSY },
  tsc     = { glyph = "", color = "#7E9CD8", kind = BUSY },
  java    = { glyph = "", color = "#E6C384", kind = BUSY },
  javaw   = { glyph = "", color = "#E6C384", kind = BUSY },
  gradle  = { glyph = "", color = "#E6C384", kind = BUSY },
  gradlew = { glyph = "", color = "#E6C384", kind = BUSY },
  mvn     = { glyph = "", color = "#E6C384", kind = BUSY },
  kotlinc = { glyph = "", color = "#E6C384", kind = BUSY },
  python  = { glyph = "", color = "#7E9CD8", kind = BUSY },
  uv      = { glyph = "", color = "#7E9CD8", kind = BUSY },
  pip     = { glyph = "", color = "#7E9CD8", kind = BUSY },
  pytest  = { glyph = "", color = "#7E9CD8", kind = BUSY },
  go      = { glyph = "", color = "#7AA89F", kind = BUSY },
  docker  = { glyph = "", color = "#7E9CD8", kind = BUSY },
  make    = { glyph = "", color = "#C8C093", kind = BUSY },
  cmake   = { glyph = "", color = "#C8C093", kind = BUSY },
  ninja   = { glyph = "", color = "#C8C093", kind = BUSY },
  msbuild = { glyph = "", color = "#C8C093", kind = BUSY },
  git     = { glyph = "", color = "#E46876", kind = BUSY },

  pwsh       = { glyph = "", color = "#7E9CD8", kind = SHELL },
  powershell = { glyph = "", color = "#7E9CD8", kind = SHELL },
  cmd        = { glyph = "", color = "#C8C093", kind = SHELL },
  bash       = { glyph = "", color = "#C8C093", kind = SHELL },
  zsh        = { glyph = "", color = "#C8C093", kind = SHELL },
  fish       = { glyph = "", color = "#C8C093", kind = SHELL },
  wsl        = { glyph = "", color = "#E46876", kind = SHELL },
  ssh        = { glyph = "", color = "#7AA89F", kind = SHELL },
  nvim       = { glyph = "", color = "#98BB6C", kind = SHELL },
  vim        = { glyph = "", color = "#98BB6C", kind = SHELL },
  claude     = { glyph = "󰚩", color = "#98BB6C", kind = SHELL },
  kiro       = { glyph = "󰚩", color = "#98BB6C", kind = SHELL },
  copilot    = { glyph = "󰚩", color = "#98BB6C", kind = SHELL },
}

function M.basename(path)
  if not path or path == "" then return "" end
  local name = path:match("([^/\\]+)$") or path
  name = name:lower()
  name = name:gsub("%.exe$", "")
  return name
end

function M.lookup(process)
  return M.entries[M.basename(process)] or M.FALLBACK
end

function M.process_to_icon()
  local map = {}
  for name, entry in pairs(M.entries) do
    map[name] = { glyph = entry.glyph, color = entry.color }
  end
  return map
end

return M
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `nvim -l wezterm/tests/run.lua`
Expected: PASS, 9 total.

- [ ] **Step 5: Commit**

```bash
git add wezterm/modules/icons.lua wezterm/tests/icons_spec.lua wezterm/tests/run.lua
git commit -m "feat(wezterm): add the process to icon table

One table keyed by lowercased process basename carries the glyph, a
colour, and whether the process counts as work in progress. The same
table feeds tabline's process_to_icon, so tab icons and busy detection
cannot disagree."
```

---

### Task 3: activity.lua — busy state machine and spinner

**Files:**
- Create: `wezterm/modules/activity.lua`
- Create: `wezterm/tests/activity_spec.lua`
- Modify: `wezterm/tests/run.lua`

**Interfaces:**
- Consumes: `icons.lookup(process).kind` from Task 2.
- Produces:
  - `activity.SPINNER` — array of 8 single-cell strings.
  - `activity.frame(now:number) -> string` — `now` is seconds as a float; advances 8 frames per second.
  - `activity.new_store() -> table` — opaque per-window state.
  - `activity.update(store, pane_id:number, process:string|nil, now:number, focused:boolean) -> { busy:boolean, glyph:string|nil, elapsed:number|nil, notify:{title:string, body:string}|nil }`
  - `activity.NOTIFY_AFTER = 30`
  - `activity.format_duration(seconds:number) -> string` — `"12s"`, `"4m12s"`, `"1h04m"`.

- [ ] **Step 1: Write the failing test**

Create `wezterm/tests/activity_spec.lua`:

```lua
local activity = require("modules.activity")

describe("activity.frame", function()
  it("advances eight frames per second", function()
    assert_eq(activity.frame(0.0), activity.SPINNER[1])
    assert_eq(activity.frame(0.125), activity.SPINNER[2])
    assert_eq(activity.frame(1.0), activity.SPINNER[1])
  end)

  it("returns the same frame for every pane at the same instant", function()
    assert_eq(activity.frame(7.3), activity.frame(7.3))
  end)
end)

describe("activity.format_duration", function()
  it("formats seconds", function() assert_eq(activity.format_duration(12), "12s") end)
  it("formats minutes and seconds", function() assert_eq(activity.format_duration(252), "4m12s") end)
  it("formats hours and minutes", function() assert_eq(activity.format_duration(3840), "1h04m") end)
end)

describe("activity.update", function()
  it("reports a shell as not busy", function()
    local store = activity.new_store()
    local result = activity.update(store, 1, "pwsh", 100, true)
    assert_eq(result.busy, false)
    assert_nil(result.notify)
  end)

  it("reports a build tool as busy with a spinner glyph", function()
    local store = activity.new_store()
    local result = activity.update(store, 1, "cargo", 100, true)
    assert_eq(result.busy, true)
    assert_eq(result.glyph, activity.frame(100))
  end)

  it("notifies when a long run finishes in an unfocused tab", function()
    local store = activity.new_store()
    activity.update(store, 1, "cargo", 100, false)
    local result = activity.update(store, 1, "pwsh", 100 + 252, false)
    assert_eq(result.busy, false)
    assert_eq(result.elapsed, 252)
    assert_true(result.notify ~= nil, "expected a notification")
    assert_eq(result.notify.body, "cargo — 4m12s")
  end)

  it("stays silent when the run was short", function()
    local store = activity.new_store()
    activity.update(store, 1, "cargo", 100, false)
    local result = activity.update(store, 1, "pwsh", 129, false)
    assert_nil(result.notify)
  end)

  it("stays silent when the tab is focused", function()
    local store = activity.new_store()
    activity.update(store, 1, "cargo", 100, true)
    local result = activity.update(store, 1, "pwsh", 400, true)
    assert_nil(result.notify)
  end)

  it("notifies once, not on every later tick", function()
    local store = activity.new_store()
    activity.update(store, 1, "cargo", 100, false)
    activity.update(store, 1, "pwsh", 400, false)
    local again = activity.update(store, 1, "pwsh", 401, false)
    assert_nil(again.notify)
  end)

  it("tracks panes independently", function()
    local store = activity.new_store()
    activity.update(store, 1, "cargo", 100, false)
    activity.update(store, 2, "pwsh", 100, false)
    local one = activity.update(store, 1, "pwsh", 400, false)
    local two = activity.update(store, 2, "pwsh", 400, false)
    assert_true(one.notify ~= nil, "pane 1 should notify")
    assert_nil(two.notify, "pane 2 was never busy")
  end)

  it("treats a missing process name as not busy", function()
    local store = activity.new_store()
    assert_eq(activity.update(store, 1, nil, 100, true).busy, false)
  end)
end)
```

Add `"activity_spec"` to `specs`.

- [ ] **Step 2: Run the test to verify it fails**

Run: `nvim -l wezterm/tests/run.lua`
Expected: FAIL — `module 'modules.activity' not found`.

- [ ] **Step 3: Write the implementation**

Create `wezterm/modules/activity.lua`:

```lua
local icons = require("modules.icons")

local M = {}

M.SPINNER = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧" }
M.NOTIFY_AFTER = 30

function M.frame(now)
  local index = math.floor(now * 8) % #M.SPINNER
  return M.SPINNER[index + 1]
end

function M.format_duration(seconds)
  seconds = math.floor(seconds)
  if seconds < 60 then
    return string.format("%ds", seconds)
  end
  if seconds < 3600 then
    return string.format("%dm%02ds", math.floor(seconds / 60), seconds % 60)
  end
  return string.format("%dh%02dm", math.floor(seconds / 3600), math.floor((seconds % 3600) / 60))
end

function M.new_store()
  return { panes = {} }
end

function M.update(store, pane_id, process, now, focused)
  local entry = store.panes[pane_id]
  if not entry then
    entry = { busy = false, started_at = nil, name = nil }
    store.panes[pane_id] = entry
  end

  local busy = process ~= nil and icons.lookup(process).kind == "busy"
  local result = { busy = busy, glyph = nil, elapsed = nil, notify = nil }

  if busy then
    if not entry.busy then
      entry.busy = true
      entry.started_at = now
      entry.name = icons.basename(process)
    end
    result.glyph = M.frame(now)
    return result
  end

  if entry.busy then
    local elapsed = now - (entry.started_at or now)
    local name = entry.name
    entry.busy = false
    entry.started_at = nil
    entry.name = nil
    result.elapsed = elapsed
    if elapsed >= M.NOTIFY_AFTER and not focused then
      result.notify = {
        title = "wezterm",
        body = string.format("%s — %s", name, M.format_duration(elapsed)),
      }
    end
  end

  return result
end

return M
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `nvim -l wezterm/tests/run.lua`
Expected: PASS, 20 total.

- [ ] **Step 5: Commit**

```bash
git add wezterm/modules/activity.lua wezterm/tests/activity_spec.lua wezterm/tests/run.lua
git commit -m "feat(wezterm): add the per-pane activity state machine

Classifies the foreground process through the icon table, tracks the
idle-to-busy transition per pane, and decides when a finished run
deserves a notification. The spinner frame is derived from the clock
rather than a counter, so every pane turns in lockstep."
```

---

### Task 4: git.lua — porcelain v2 parser and segment

**Files:**
- Create: `wezterm/modules/git.lua`
- Create: `wezterm/tests/git_spec.lua`
- Modify: `wezterm/tests/run.lua`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `git.parse(text:string) -> { branch:string|nil, oid:string|nil, detached:boolean, ahead:number, behind:number, dirty:number }`
  - `git.render(info:table|nil) -> { text:string, color:string }|nil` — nil when `info` is nil, meaning "not a repo, hide the section".
  - `git.POLL_SECONDS = 4`
  - `git.cache_path(temp_dir:string, repo_key:string) -> string`
  - `git.repo_key(cwd:string) -> string` — a filename-safe hash of the cwd.

- [ ] **Step 1: Write the failing test**

Create `wezterm/tests/git_spec.lua`. The fixtures are real `--porcelain=v2 --branch` output.

```lua
local git = require("modules.git")

local CLEAN = table.concat({
  "# branch.oid cc3e0dbabc1234567890abcdef1234567890abcd",
  "# branch.head main",
  "# branch.upstream origin/main",
  "# branch.ab +0 -0",
}, "\n")

local DIRTY = table.concat({
  "# branch.oid cc3e0dbabc1234567890abcdef1234567890abcd",
  "# branch.head feat/wezterm-bar",
  "# branch.upstream origin/feat/wezterm-bar",
  "# branch.ab +2 -0",
  "1 .M N... 100644 100644 100644 aaa bbb wezterm/modules/bar.lua",
  "1 M. N... 100644 100644 100644 ccc ddd wezterm/modules/git.lua",
  "? wezterm/local.lua",
}, "\n")

local DETACHED = table.concat({
  "# branch.oid cc3e0dbabc1234567890abcdef1234567890abcd",
  "# branch.head (detached)",
}, "\n")

describe("git.parse", function()
  it("reads a clean branch", function()
    local info = git.parse(CLEAN)
    assert_eq(info.branch, "main")
    assert_eq(info.detached, false)
    assert_eq(info.dirty, 0)
    assert_eq(info.ahead, 0)
  end)

  it("counts changed and untracked files", function()
    local info = git.parse(DIRTY)
    assert_eq(info.branch, "feat/wezterm-bar")
    assert_eq(info.dirty, 3)
    assert_eq(info.ahead, 2)
    assert_eq(info.behind, 0)
  end)

  it("detects a detached head", function()
    local info = git.parse(DETACHED)
    assert_eq(info.detached, true)
    assert_eq(info.branch, nil)
    assert_eq(info.oid, "cc3e0dbabc1234567890abcdef1234567890abcd")
  end)

  it("returns zeroed counts for empty output", function()
    local info = git.parse("")
    assert_eq(info.dirty, 0)
    assert_eq(info.detached, false)
  end)
end)

describe("git.render", function()
  it("hides the section outside a repository", function()
    assert_nil(git.render(nil))
  end)

  it("shows a tick in aqua when clean", function()
    local seg = git.render(git.parse(CLEAN))
    assert_eq(seg.color, "#7AA89F")
    assert_true(seg.text:find("main", 1, true) ~= nil, "branch name missing")
    assert_true(seg.text:find("", 1, true) ~= nil, "clean marker missing")
  end)

  it("shows the dirty count in amber and wins over ahead", function()
    local seg = git.render(git.parse(DIRTY))
    assert_eq(seg.color, "#E6C384")
    assert_true(seg.text:find(" 3", 1, true) ~= nil, "dirty count missing")
    assert_true(seg.text:find(" 2", 1, true) ~= nil, "ahead count missing")
  end)

  it("shows only the ahead marker in blue when committed but unpushed", function()
    local info = git.parse(CLEAN)
    info.ahead = 2
    local seg = git.render(info)
    assert_eq(seg.color, "#7E9CD8")
    assert_true(seg.text:find(" 2", 1, true) ~= nil, "ahead count missing")
  end)

  it("shows a short hash in red when detached", function()
    local seg = git.render(git.parse(DETACHED))
    assert_eq(seg.color, "#E46876")
    assert_true(seg.text:find("cc3e0db", 1, true) ~= nil, "short hash missing")
  end)
end)

describe("git.repo_key", function()
  it("is stable and filename safe", function()
    local key = git.repo_key("C:\\Projects\\rust\\solstice")
    assert_eq(key, git.repo_key("C:\\Projects\\rust\\solstice"))
    assert_nil(key:match("[\\/:]"), "key must not contain path separators")
  end)

  it("differs between repositories", function()
    assert_true(git.repo_key("/a") ~= git.repo_key("/b"))
  end)
end)
```

Add `"git_spec"` to `specs`.

- [ ] **Step 2: Run the test to verify it fails**

Run: `nvim -l wezterm/tests/run.lua`
Expected: FAIL — `module 'modules.git' not found`.

- [ ] **Step 3: Write the implementation**

Create `wezterm/modules/git.lua`:

```lua
local M = {}

M.POLL_SECONDS = 4

local BRANCH_GLYPH = ""
local CLEAN_GLYPH = ""
local DIRTY_GLYPH = ""
local AHEAD_GLYPH = ""
local DETACHED_GLYPH = "󰜘"

local AQUA = "#7AA89F"
local AMBER = "#E6C384"
local BLUE = "#7E9CD8"
local RED = "#E46876"

function M.parse(text)
  local info = { branch = nil, oid = nil, detached = false, ahead = 0, behind = 0, dirty = 0 }
  for line in (text or ""):gmatch("[^\n]+") do
    local oid = line:match("^# branch%.oid (%S+)")
    local head = line:match("^# branch%.head (.+)$")
    local ahead, behind = line:match("^# branch%.ab %+(%d+) %-(%d+)")
    if oid then
      info.oid = oid
    elseif head then
      if head == "(detached)" then
        info.detached = true
      else
        info.branch = head
      end
    elseif ahead then
      info.ahead = tonumber(ahead)
      info.behind = tonumber(behind)
    elseif line:match("^[12u?] ") then
      info.dirty = info.dirty + 1
    end
  end
  return info
end

function M.render(info)
  if not info then return nil end

  if info.detached then
    local short = (info.oid or "0000000"):sub(1, 7)
    return { text = string.format("%s %s", DETACHED_GLYPH, short), color = RED }
  end

  local parts = { string.format("%s %s", BRANCH_GLYPH, info.branch or "?") }
  local color = AQUA

  if info.dirty > 0 then
    table.insert(parts, string.format("%s %d", DIRTY_GLYPH, info.dirty))
    color = AMBER
  end

  if info.ahead > 0 then
    table.insert(parts, string.format("%s %d", AHEAD_GLYPH, info.ahead))
    if color == AQUA then color = BLUE end
  end

  if info.dirty == 0 and info.ahead == 0 then
    table.insert(parts, CLEAN_GLYPH)
  end

  return { text = table.concat(parts, "  "), color = color }
end

function M.repo_key(cwd)
  local hash = 5381
  for i = 1, #cwd do
    hash = (hash * 33 + cwd:byte(i)) % 4294967296
  end
  return string.format("%08x", hash)
end

function M.cache_path(temp_dir, repo_key)
  return string.format("%s/wezterm-git-%s", temp_dir, repo_key)
end

return M
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `nvim -l wezterm/tests/run.lua`
Expected: PASS, 32 total.

- [ ] **Step 5: Commit**

```bash
git add wezterm/modules/git.lua wezterm/tests/git_spec.lua wezterm/tests/run.lua
git commit -m "feat(wezterm): parse git porcelain v2 and render the segment

One 'git status --porcelain=v2 --branch' call yields branch, ahead and
behind counts, and the dirty file count together, so the segment needs
no second invocation. Dirty wins the colour over unpushed; a detached
head shows the short hash in red."
```

---

### Task 5: agent.lua — AI state and notifications

**Files:**
- Create: `wezterm/modules/agent.lua`
- Create: `wezterm/tests/agent_spec.lua`
- Modify: `wezterm/tests/run.lua`

**Interfaces:**
- Consumes: `activity.frame`, `activity.format_duration` from Task 3.
- Produces:
  - `agent.classify(deck_status:string|nil, process:string|nil) -> "working"|"waiting"|"idle"|nil`
  - `agent.new_store() -> table`
  - `agent.update(store, state:string|nil, now:number, focused:boolean) -> { segment:{text:string,color:string}|nil, notify:{title:string,body:string}|nil }`
  - `agent.on_user_var(store, name:string, value:string)` — documented entry point for a CLI that later publishes exact state through an OSC user-var. Accepts `name == "agent-state"` with a value of `working`, `waiting`, or `idle`, and takes precedence over `classify` until the next `idle`.

- [ ] **Step 1: Write the failing test**

Create `wezterm/tests/agent_spec.lua`:

```lua
local agent = require("modules.agent")
local activity = require("modules.activity")

describe("agent.classify", function()
  it("trusts agent-deck when it reports a state", function()
    assert_eq(agent.classify("working", nil), "working")
    assert_eq(agent.classify("waiting", nil), "waiting")
    assert_eq(agent.classify("idle", nil), "idle")
  end)

  it("falls back to the process name for kiro and copilot", function()
    assert_eq(agent.classify(nil, "kiro"), "working")
    assert_eq(agent.classify(nil, "copilot"), "working")
  end)

  it("returns nil when no agent is present", function()
    assert_nil(agent.classify(nil, "pwsh"))
    assert_nil(agent.classify(nil, nil))
  end)
end)

describe("agent.update", function()
  it("renders working in green with a spinner", function()
    local store = agent.new_store()
    local result = agent.update(store, "working", 10, true)
    assert_eq(result.segment.color, "#98BB6C")
    assert_true(result.segment.text:find(activity.frame(10), 1, true) ~= nil, "spinner missing")
  end)

  it("renders waiting in amber with a static glyph", function()
    local store = agent.new_store()
    local result = agent.update(store, "waiting", 10, true)
    assert_eq(result.segment.color, "#E6C384")
    assert_true(result.segment.text:find("◔", 1, true) ~= nil, "waiting glyph missing")
  end)

  it("hides the segment when no agent is present", function()
    local store = agent.new_store()
    assert_nil(agent.update(store, nil, 10, true).segment)
  end)

  it("notifies on entering waiting, focused or not", function()
    local store = agent.new_store()
    agent.update(store, "working", 10, true)
    local result = agent.update(store, "waiting", 20, true)
    assert_true(result.notify ~= nil, "expected a waiting notification")
    assert_true(result.notify.body:find("input", 1, true) ~= nil, "body should mention input")
  end)

  it("notifies once per entry into waiting", function()
    local store = agent.new_store()
    agent.update(store, "waiting", 20, true)
    assert_nil(agent.update(store, "waiting", 21, true).notify)
  end)

  it("notifies with elapsed time when work finishes in an unfocused tab", function()
    local store = agent.new_store()
    agent.update(store, "working", 10, false)
    local result = agent.update(store, "idle", 10 + 252, false)
    assert_true(result.notify ~= nil, "expected a finished notification")
    assert_true(result.notify.body:find("4m12s", 1, true) ~= nil, "elapsed missing")
  end)

  it("stays silent when work finishes in the focused tab", function()
    local store = agent.new_store()
    agent.update(store, "working", 10, true)
    assert_nil(agent.update(store, "idle", 300, true).notify)
  end)
end)

describe("agent.on_user_var", function()
  it("overrides classification until the next idle", function()
    local store = agent.new_store()
    agent.on_user_var(store, "agent-state", "waiting")
    local result = agent.update(store, "working", 10, true)
    assert_eq(result.segment.color, "#E6C384")
  end)

  it("ignores unrelated variables", function()
    local store = agent.new_store()
    agent.on_user_var(store, "something-else", "waiting")
    assert_eq(agent.update(store, "working", 10, true).segment.color, "#98BB6C")
  end)
end)
```

Add `"agent_spec"` to `specs`.

- [ ] **Step 2: Run the test to verify it fails**

Run: `nvim -l wezterm/tests/run.lua`
Expected: FAIL — `module 'modules.agent' not found`.

- [ ] **Step 3: Write the implementation**

Create `wezterm/modules/agent.lua`:

```lua
local activity = require("modules.activity")
local icons = require("modules.icons")

local M = {}

local ROBOT = "󰚩"
local WAITING_GLYPH = "◔"
local IDLE_GLYPH = "○"

local GREEN = "#98BB6C"
local AMBER = "#E6C384"
local BLUE = "#7E9CD8"

local AGENT_PROCESSES = { claude = true, kiro = true, copilot = true }

function M.classify(deck_status, process)
  if deck_status == "working" or deck_status == "waiting" or deck_status == "idle" then
    return deck_status
  end
  if process and AGENT_PROCESSES[icons.basename(process)] then
    return "working"
  end
  return nil
end

function M.new_store()
  return { state = nil, started_at = nil, override = nil }
end

function M.on_user_var(store, name, value)
  if name ~= "agent-state" then return end
  if value == "working" or value == "waiting" or value == "idle" then
    store.override = value
  end
end

local function segment_for(state, now)
  if state == "working" then
    return { text = string.format("%s %s claude", ROBOT, activity.frame(now)), color = GREEN }
  elseif state == "waiting" then
    return { text = string.format("%s %s waiting", ROBOT, WAITING_GLYPH), color = AMBER }
  elseif state == "idle" then
    return { text = string.format("%s %s idle", ROBOT, IDLE_GLYPH), color = BLUE }
  end
  return nil
end

function M.update(store, state, now, focused)
  if store.override then
    state = store.override
    if state == "idle" then store.override = nil end
  end

  local previous = store.state
  local result = { segment = segment_for(state, now), notify = nil }

  if state == "working" and previous ~= "working" then
    store.started_at = now
  end

  if state == "waiting" and previous ~= "waiting" then
    result.notify = { title = "claude", body = "waiting for input" }
  end

  if previous == "working" and state ~= "working" and state ~= nil then
    local elapsed = now - (store.started_at or now)
    if not focused then
      result.notify = {
        title = "claude",
        body = string.format("finished — %s", activity.format_duration(elapsed)),
      }
    end
    store.started_at = nil
  end

  store.state = state
  return result
end

return M
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `nvim -l wezterm/tests/run.lua`
Expected: PASS, 42 total.

- [ ] **Step 5: Commit**

```bash
git add wezterm/modules/agent.lua wezterm/tests/agent_spec.lua wezterm/tests/run.lua
git commit -m "feat(wezterm): add AI agent state and notifications

agent-deck supplies exact state for Claude Code; kiro and copilot fall
back to process detection, which can only say working. Finishing is
derived from the working-to-idle transition, so no CLI hooks are
required. on_user_var is the documented entry point for a CLI that
later publishes exact state itself."
```

---

### Task 6: platform.lua and theme.lua — OS branches and the bottom bar

**Files:**
- Create: `wezterm/modules/platform.lua`
- Create: `wezterm/modules/theme.lua`
- Create: `wezterm/tests/platform_spec.lua`
- Modify: `wezterm/tests/run.lua`
- Modify: `wezterm/tests/stub_wezterm.lua` (make `target_triple` settable per test)

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `platform.detect(triple:string) -> { os:"windows"|"macos"|"linux", default_prog:table, mod_primary:string, temp_dir:string, nvim_config_dir:string, shell_cmd:function }`
  - `platform.current()` — `detect(wezterm.target_triple)`, memoised.
  - `platform.shell_cmd(os_name:string, command:string) -> table` — argv for `background_child_process`.
  - `theme.apply(config, plugins)` — applies colours, font, padding, backdrop, and bottom bar placement. Must be called **after** `plugins.tabline.apply_to_config(config)`.

- [ ] **Step 1: Make the stub's triple settable**

Modify `wezterm/tests/stub_wezterm.lua`, adding below the table definition:

```lua
function stub.__set_triple(triple)
  stub.target_triple = triple
end
```

- [ ] **Step 2: Write the failing test**

Create `wezterm/tests/platform_spec.lua`:

```lua
local platform = require("modules.platform")

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
```

Add `"platform_spec"` to `specs`.

- [ ] **Step 3: Run the test to verify it fails**

Run: `nvim -l wezterm/tests/run.lua`
Expected: FAIL — `module 'modules.platform' not found`.

- [ ] **Step 4: Write platform.lua**

Create `wezterm/modules/platform.lua`:

```lua
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
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `nvim -l wezterm/tests/run.lua`
Expected: PASS, 48 total.

- [ ] **Step 6: Write theme.lua**

Create `wezterm/modules/theme.lua`. No test — every line is a config assignment verified by the smoke run in Step 7.

```lua
local M = {}

function M.apply(config, plugins, platform)
  plugins.kanagawa.apply_to_config(config)

  config.font = require("wezterm").font("JetBrainsMono Nerd Font")
  config.font_size = 12.5

  config.window_background_opacity = 0.97
  config.window_padding = { left = 8, right = 8, top = 8, bottom = 8 }
  config.window_decorations = "RESIZE"

  if platform.os == "windows" then
    config.win32_system_backdrop = "Acrylic"
  elseif platform.os == "macos" then
    config.macos_window_background_blur = 30
  end

  config.inactive_pane_hsb = { saturation = 0.85, brightness = 0.75 }
  config.default_cursor_style = "BlinkingBar"
  config.cursor_blink_ease_in = "EaseInOut"
  config.cursor_blink_ease_out = "EaseInOut"
  config.cursor_blink_rate = 600

  config.scrollback_lines = 100000
  config.audible_bell = "Disabled"
  config.default_prog = platform.default_prog

  config.window_frame = {
    font = require("wezterm").font("JetBrainsMono Nerd Font", { weight = "Bold" }),
    font_size = 11.5,
  }

  -- Placement is WezTerm's, not tabline's, and tabline sets use_fancy_tab_bar
  -- itself, so this must run after tabline.apply_to_config.
  config.enable_tab_bar = true
  config.use_fancy_tab_bar = false
  config.hide_tab_bar_if_only_one_tab = false
  config.tab_bar_at_bottom = true

  config.status_update_interval = 120
end

return M
```

- [ ] **Step 7: Commit**

```bash
git add wezterm/modules/platform.lua wezterm/modules/theme.lua wezterm/tests/platform_spec.lua wezterm/tests/stub_wezterm.lua wezterm/tests/run.lua
git commit -m "feat(wezterm): add the platform branch and theme module

platform.lua is the only module that inspects the target triple; it
exports the default shell, the primary modifier (CMD on macOS), the
temp directory, and the background shell argv. theme.lua carries the
existing look plus inactive pane dimming, a blinking bar cursor, and
the bar moved to the bottom of the window."
```

---

### Task 7: plugins.lua and bar.lua — the visible bar

**Files:**
- Create: `wezterm/modules/plugins.lua`
- Create: `wezterm/modules/bar.lua`
- Rewrite: `wezterm/wezterm.lua`

**Interfaces:**
- Consumes: every module from Tasks 2–6.
- Produces:
  - `plugins.load() -> { kanagawa, tabline, agent_deck, resurrect, domains }`
  - `bar.apply(config, plugins, platform, state)` where `state = { activity = <store>, agent = <store>, git = <cache table> }`.

- [ ] **Step 1: Write plugins.lua**

Create `wezterm/modules/plugins.lua`:

```lua
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
```

- [ ] **Step 2: Write bar.lua**

Create `wezterm/modules/bar.lua`. This is the only module allowed to format.

```lua
local wezterm = require("wezterm")
local icons = require("modules.icons")
local activity = require("modules.activity")
local git = require("modules.git")
local agent = require("modules.agent")

local M = {}

local function now_seconds()
  return wezterm.time.now():format("%s") + 0
end

local function read_file(path)
  local handle = io.open(path, "r")
  if not handle then return nil end
  local text = handle:read("*a")
  handle:close()
  return text
end

local function refresh_git(state, platform, cwd)
  if not cwd then return nil end
  local key = git.repo_key(cwd)
  local entry = state.git[key]
  local now = now_seconds()

  if not entry then
    entry = { info = nil, polled_at = -math.huge, path = git.cache_path(platform.temp_dir, key) }
    state.git[key] = entry
  end

  if now - entry.polled_at >= git.POLL_SECONDS then
    entry.polled_at = now
    local command = string.format(
      'cd "%s" && git status --porcelain=v2 --branch > "%s" 2>&1',
      cwd, entry.path)
    wezterm.background_child_process(platform.shell_cmd(command))
  end

  local text = read_file(entry.path)
  if text and not text:find("not a git repository", 1, true) then
    entry.info = git.parse(text)
  elseif text then
    entry.info = nil
  end

  return entry.info
end

function M.apply(config, plugins, platform, state)
  plugins.tabline.setup({
    options = {
      icons_enabled = true,
      theme = "Kanagawa",
      section_separators = {
        left = wezterm.nerdfonts.pl_left_hard_divider,
        right = wezterm.nerdfonts.pl_right_hard_divider,
      },
      component_separators = {
        left = wezterm.nerdfonts.pl_left_soft_divider,
        right = wezterm.nerdfonts.pl_right_soft_divider,
      },
      tab_separators = {
        left = wezterm.nerdfonts.pl_left_hard_divider,
        right = wezterm.nerdfonts.pl_right_hard_divider,
      },
    },
    sections = {
      tabline_a = { "mode" },
      tabline_b = { "workspace" },
      tabline_c = {
        function(window, pane)
          local cwd_url = pane and pane:get_current_working_dir()
          local cwd = cwd_url and cwd_url.file_path or nil
          local segment = git.render(refresh_git(state, platform, cwd))
          if not segment then return "" end
          return wezterm.format({
            { Foreground = { Color = segment.color } },
            { Text = segment.text },
          })
        end,
      },
      tab_active = {
        "index",
        { "process", padding = { left = 0, right = 1 } },
        "tab",
        function(tab)
          local pane = tab.active_pane
          local result = activity.update(
            state.activity, pane.pane_id,
            pane.foreground_process_name, now_seconds(), tab.is_active)
          return result.busy and (" " .. result.glyph) or ""
        end,
        "zoomed",
      },
      tab_inactive = {
        "index",
        { "process", padding = { left = 0, right = 1 } },
        "tab",
        function(tab)
          local pane = tab.active_pane
          local result = activity.update(
            state.activity, pane.pane_id,
            pane.foreground_process_name, now_seconds(), tab.is_active)
          return result.busy and (" " .. result.glyph) or ""
        end,
        "zoomed",
      },
      tabline_x = {
        function(window, pane)
          local deck
          pcall(function() deck = plugins.agent_deck.get_status() end)
          local process = pane and pane:get_foreground_process_name() or nil
          local state_name = agent.classify(deck, process)
          local result = agent.update(state.agent, state_name, now_seconds(), true)
          if result.notify then
            window:toast_notification(result.notify.title, result.notify.body, nil, 6000)
          end
          if not result.segment then return "" end
          return wezterm.format({
            { Foreground = { Color = result.segment.color } },
            { Text = result.segment.text },
          })
        end,
      },
      tabline_y = { "cpu", "ram" },
      tabline_z = { "datetime" },
    },
    extensions = { "resurrect", "quick_domains" },
  })

  plugins.tabline.apply_to_config(config)

  wezterm.on("user-var-changed", function(_, _, name, value)
    agent.on_user_var(state.agent, name, value)
  end)

  wezterm.on("update-status", function(window)
    for _, tab in ipairs(window:mux_window():tabs_with_info()) do
      local pane = tab.tab:active_pane()
      local result = activity.update(
        state.activity, pane:pane_id(),
        pane:get_foreground_process_name(), now_seconds(), tab.is_active)
      if result.notify then
        window:toast_notification(result.notify.title, result.notify.body, nil, 6000)
      end
    end
  end)
end

return M
```

- [ ] **Step 3: Rewrite wezterm.lua**

Replace `wezterm/wezterm.lua` entirely:

```lua
package.path = (os.getenv("HOME") or os.getenv("USERPROFILE")) ..
  "/.dotfiles/wezterm/?.lua;" .. package.path

local wezterm = require("wezterm")
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

require("modules.bar").apply(config, plugins, platform, state)
require("modules.theme").apply(config, plugins, platform)
require("modules.keys").apply(config, plugins, platform)

local ok, overrides = pcall(dofile,
  (os.getenv("HOME") or os.getenv("USERPROFILE")) .. "/.dotfiles/wezterm/local.lua")
if ok and type(overrides) == "table" then
  for key, value in pairs(overrides) do config[key] = value end
end

return config
```

Note the order: `bar.apply` runs before `theme.apply` so that `theme.apply` gets the last word on `use_fancy_tab_bar` and `tab_bar_at_bottom`.

- [ ] **Step 4: Verify against a throwaway instance**

Task 8 writes `modules/keys.lua`, so this step will fail with `module 'modules.keys' not found` until then. Create a stub now so this task can be verified on its own — Task 8 replaces it:

```lua
-- wezterm/modules/keys.lua (temporary stub, replaced in Task 8)
local M = {}
function M.apply(config, plugins, platform) end
return M
```

Run: `wezterm -n --config-file "$HOME\.dotfiles\wezterm\wezterm.lua" start -- pwsh`

Expected: a window whose bar is at the **bottom**, showing mode, workspace, tabs with process icons, cpu/ram, and a clock. Run `cargo build` in a Rust directory and confirm the tab spinner animates.

**If the tab spinner does not animate** — the known risk in the spec — delete the anonymous function from `tab_active` and `tab_inactive` and add a static `""` marker driven by `result.busy` instead. Record which behaviour you observed in the commit message. Everything else stands either way.

- [ ] **Step 5: Commit**

```bash
git add wezterm/modules/plugins.lua wezterm/modules/bar.lua wezterm/modules/keys.lua wezterm/wezterm.lua
git commit -m "feat(wezterm): build the bottom bar on tabline.wez

Sections are mode, workspace, git, tabs, agent, cpu and ram, and the
clock. The three custom components read from the state providers and do
nothing but format. Git polling happens through a background process
writing to a temp file, so the status callback never blocks."
```

---

### Task 8: keys.lua — bindings, smart-splits, plugin actions

**Files:**
- Create: `wezterm/tests/keys_spec.lua`
- Replace: `wezterm/modules/keys.lua` (the stub from Task 7)
- Modify: `wezterm/tests/run.lua`

**Interfaces:**
- Consumes: `platform.mod_primary` from Task 6, `plugins.resurrect` and `plugins.domains` from Task 7.
- Produces:
  - `keys.build(mod_primary:string) -> table` — the `config.keys` array, pure and testable.
  - `keys.apply(config, plugins, platform)` — sets `leader`, `keys`, `mouse_bindings`, and registers plugin key tables.
  - `keys.is_nvim(process:string|nil) -> boolean` — used by smart-splits forwarding.

- [ ] **Step 1: Extend the stub with the action surface keys.lua needs**

Modify `wezterm/tests/stub_wezterm.lua`, adding before `package.preload`:

```lua
stub.action = setmetatable({}, {
  __index = function(_, name)
    return setmetatable({ __action = name }, {
      __call = function(_, arg) return { __action = name, arg = arg } end,
    })
  end,
})

stub.action_callback = function(fn) return { __action = "callback", fn = fn } end
```

- [ ] **Step 2: Write the failing test**

Create `wezterm/tests/keys_spec.lua`:

```lua
local keys = require("modules.keys")

local function find(list, key, mods)
  for _, entry in ipairs(list) do
    if entry.key == key and entry.mods == mods then return entry end
  end
  return nil
end

describe("keys.build", function()
  it("keeps leader pane navigation", function()
    local list = keys.build("CTRL|SHIFT")
    for _, k in ipairs({ "h", "j", "k", "l" }) do
      assert_true(find(list, k, "LEADER") ~= nil, "missing LEADER " .. k)
    end
  end)

  it("uses the primary modifier for tabs and splits", function()
    local list = keys.build("CTRL|SHIFT")
    assert_true(find(list, "t", "CTRL|SHIFT") ~= nil, "missing new tab")
    assert_true(find(list, "v", "CTRL|SHIFT") ~= nil, "missing vertical split")
  end)

  it("swaps to CMD on macos without moving the leader", function()
    local list = keys.build("CMD")
    assert_true(find(list, "t", "CMD") ~= nil, "new tab should use CMD")
    assert_true(find(list, "z", "LEADER") ~= nil, "zoom should stay on LEADER")
  end)

  it("binds the plugin actions", function()
    local list = keys.build("CTRL|SHIFT")
    assert_true(find(list, "s", "LEADER") ~= nil, "missing resurrect save")
    assert_true(find(list, "r", "LEADER") ~= nil, "missing resurrect restore")
    assert_true(find(list, "d", "LEADER") ~= nil, "missing domain picker")
  end)

  it("binds smart-splits navigation on plain CTRL", function()
    local list = keys.build("CTRL|SHIFT")
    for _, k in ipairs({ "h", "j", "k", "l" }) do
      assert_true(find(list, k, "CTRL") ~= nil, "missing CTRL " .. k)
    end
  end)
end)

describe("keys.is_nvim", function()
  it("detects neovim regardless of path or case", function()
    assert_true(keys.is_nvim("C:\\tools\\NVIM.EXE"))
    assert_true(keys.is_nvim("/usr/bin/nvim"))
  end)

  it("rejects shells", function()
    assert_eq(keys.is_nvim("pwsh"), false)
    assert_eq(keys.is_nvim(nil), false)
  end)
end)
```

Add `"keys_spec"` to `specs`.

- [ ] **Step 3: Run the test to verify it fails**

Run: `nvim -l wezterm/tests/run.lua`
Expected: FAIL — the stub `keys.lua` has no `build`.

- [ ] **Step 4: Write the implementation**

Replace `wezterm/modules/keys.lua`:

```lua
local wezterm = require("wezterm")
local icons = require("modules.icons")

local M = {}

local DIRECTIONS = { h = "Left", j = "Down", k = "Up", l = "Right" }

function M.is_nvim(process)
  if not process then return false end
  local name = icons.basename(process)
  return name == "nvim" or name == "vim"
end

local function split(direction)
  return wezterm.action_callback(function(window, pane)
    local cwd = pane:get_current_working_dir()
    local action = direction == "horizontal"
      and wezterm.action.SplitHorizontal({ cwd = cwd })
      or wezterm.action.SplitVertical({ cwd = cwd })
    window:perform_action(action, pane)
  end)
end

local function smart_split_nav(key)
  return wezterm.action_callback(function(window, pane)
    if M.is_nvim(pane:get_foreground_process_name()) then
      window:perform_action(
        wezterm.action.SendKey({ key = key, mods = "CTRL" }), pane)
    else
      window:perform_action(
        wezterm.action.ActivatePaneDirection(DIRECTIONS[key]), pane)
    end
  end)
end

function M.build(mod_primary)
  local list = {}

  for key, direction in pairs(DIRECTIONS) do
    table.insert(list, { key = key, mods = "LEADER",
      action = wezterm.action.ActivatePaneDirection(direction) })
    table.insert(list, { key = key, mods = "CTRL", action = smart_split_nav(key) })
  end

  table.insert(list, { key = "v", mods = mod_primary, action = split("vertical") })
  table.insert(list, { key = "h", mods = mod_primary, action = split("horizontal") })
  table.insert(list, { key = "t", mods = mod_primary,
    action = wezterm.action.SpawnTab("CurrentPaneDomain") })
  table.insert(list, { key = "[", mods = mod_primary,
    action = wezterm.action.ActivateTabRelative(-1) })
  table.insert(list, { key = "]", mods = mod_primary,
    action = wezterm.action.ActivateTabRelative(1) })
  table.insert(list, { key = "W", mods = mod_primary,
    action = wezterm.action.ShowLauncherArgs({ flags = "WORKSPACES" }) })

  table.insert(list, { key = "z", mods = "LEADER",
    action = wezterm.action.TogglePaneZoomState })
  table.insert(list, { key = "w", mods = "LEADER",
    action = wezterm.action.CloseCurrentPane({ confirm = false }) })
  table.insert(list, { key = "p", mods = "LEADER",
    action = wezterm.action.ShowLauncher })

  -- Plugin actions are replaced with real handles in apply(); build() stays
  -- pure so it can be tested without loading plugins.
  table.insert(list, { key = "s", mods = "LEADER", action = wezterm.action.Nop })
  table.insert(list, { key = "r", mods = "LEADER", action = wezterm.action.Nop })
  table.insert(list, { key = "d", mods = "LEADER", action = wezterm.action.Nop })

  return list
end

function M.apply(config, plugins, platform)
  config.leader = { key = "q", mods = "CTRL", timeout_milliseconds = 1000 }
  config.keys = M.build(platform.mod_primary)

  for _, entry in ipairs(config.keys) do
    if entry.mods == "LEADER" and entry.key == "s" then
      entry.action = wezterm.action_callback(function(window, pane)
        plugins.resurrect.state_manager.save_state(
          plugins.resurrect.workspace_state.get_workspace_state())
        window:toast_notification("resurrect", "workspace saved", nil, 3000)
      end)
    elseif entry.mods == "LEADER" and entry.key == "r" then
      entry.action = wezterm.action_callback(function(window, pane)
        plugins.resurrect.fuzzy_loader.fuzzy_load(window, pane, function(id)
          plugins.resurrect.state_manager.load_state(id, "workspace")
        end)
      end)
    elseif entry.mods == "LEADER" and entry.key == "d" then
      entry.action = plugins.domains.action.attach_domain
    end
  end

  config.mouse_bindings = {
    {
      event = { Down = { streak = 1, button = "Left" } },
      mods = "CTRL|SHIFT",
      action = wezterm.action.StartWindowDrag,
    },
  }
end

return M
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `nvim -l wezterm/tests/run.lua`
Expected: PASS, 55 total.

- [ ] **Step 6: Verify the bindings in a throwaway instance**

Run: `wezterm -n --config-file "$HOME\.dotfiles\wezterm\wezterm.lua" start -- pwsh`

Check by hand: `CTRL+q` then `s` toasts "workspace saved"; `CTRL+q` then `d` opens the domain picker; `CTRL+SHIFT+v` splits inheriting the cwd; `CTRL+h` moves panes outside Neovim.

- [ ] **Step 7: Commit**

```bash
git add wezterm/modules/keys.lua wezterm/tests/keys_spec.lua wezterm/tests/stub_wezterm.lua wezterm/tests/run.lua
git commit -m "feat(wezterm): add key bindings with smart-splits forwarding

build() stays pure so the whole key table can be asserted in tests;
apply() swaps in the plugin handles afterwards. CTRL+hjkl forwards to
Neovim when the pane is running it and switches panes otherwise. The
primary modifier is CMD on macOS while the leader stays CTRL+q
everywhere."
```

---

### Task 9: Neovim integration

**Files:**
- Create: `nvim/lua/plugins/smart-splits.lua`
- Modify: `nvim/lua/config/autocmds.lua`

**Interfaces:**
- Consumes: `keys.is_nvim` behaviour from Task 8 (the WezTerm side of the same keys).
- Produces: an OSC 1337 user-var named `nvim-file` carrying `"<filename>"` or `"<filename> ●"` when modified, and `""` when Neovim has no file open. `bar.lua` already listens through `user-var-changed`.

- [ ] **Step 1: Write the smart-splits plugin spec**

Create `nvim/lua/plugins/smart-splits.lua`:

```lua
return {
  "mrjones2014/smart-splits.nvim",
  lazy = false,
  opts = {
    at_edge = "stop",
    ignored_filetypes = { "nofile", "quickfix", "prompt" },
  },
  keys = {
    { "<C-h>", function() require("smart-splits").move_cursor_left() end, desc = "Move to left split" },
    { "<C-j>", function() require("smart-splits").move_cursor_down() end, desc = "Move to below split" },
    { "<C-k>", function() require("smart-splits").move_cursor_up() end, desc = "Move to above split" },
    { "<C-l>", function() require("smart-splits").move_cursor_right() end, desc = "Move to right split" },
  },
}
```

- [ ] **Step 2: Verify the plugin installs and is healthy**

Run: `nvim --headless "+Lazy! sync" +qa`
Then: `nvim --headless "+checkhealth smart-splits" +qa`

Expected: both exit 0 and the health output reports no errors. If `checkhealth` reports the multiplexer as undetected, that is expected when run headless outside WezTerm — verify inside a WezTerm pane instead.

- [ ] **Step 3: Add the user-var autocmd**

Append to `nvim/lua/config/autocmds.lua`:

```lua
-- Publish the current file to WezTerm as an OSC 1337 user var so the tab can
-- show the file name instead of a bare "nvim".
local wez_group = vim.api.nvim_create_augroup("WeztermUserVar", { clear = true })

local function publish_file()
  local name = vim.fn.expand("%:t")
  if name == "" then
    name = ""
  elseif vim.bo.modified then
    name = name .. " ●"
  end
  local encoded = vim.base64.encode(name)
  io.stdout:write(("\027]1337;SetUserVar=%s=%s\007"):format("nvim-file", encoded))
end

vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost", "BufModifiedSet" }, {
  group = wez_group,
  callback = publish_file,
})

vim.api.nvim_create_autocmd("VimLeavePre", {
  group = wez_group,
  callback = function()
    io.stdout:write(("\027]1337;SetUserVar=%s=%s\007"):format("nvim-file", ""))
  end,
})
```

- [ ] **Step 4: Verify the user var reaches WezTerm**

Open a WezTerm pane, run `nvim wezterm/modules/bar.lua`, and confirm the tab shows the file name. Modify the buffer without saving and confirm the `●` appears. Quit Neovim and confirm the tab reverts to the process name.

`vim.base64.encode` requires Neovim 0.10 or newer; this machine runs 0.12.4. If the check fails on an older Neovim, the autocmd is the only thing that breaks — `bar.lua` already falls back to the process name when the user var is absent.

- [ ] **Step 5: Commit**

```bash
git add nvim/lua/plugins/smart-splits.lua nvim/lua/config/autocmds.lua
git commit -m "feat(nvim): add smart-splits and publish the file name to wezterm

CTRL+hjkl now moves across Neovim splits and WezTerm panes with one set
of keys. An autocmd publishes the current file and its modified flag as
an OSC 1337 user var, which the tab renders instead of a bare 'nvim';
WezTerm falls back to the process name when the var is absent."
```

---

### Task 10: Full-state verification and README stub

**Files:**
- Create: `README.md`
- Modify: none

**Interfaces:**
- Consumes: everything.
- Produces: a README that the installer plan extends with the one-liners.

- [ ] **Step 1: Run the whole suite**

Run: `nvim -l wezterm/tests/run.lua`
Expected: 55 passed, 0 failed.

- [ ] **Step 2: Walk the five bar states**

In a throwaway instance (`wezterm -n --config-file "$HOME\.dotfiles\wezterm\wezterm.lua" start -- pwsh`), confirm each:

1. Idle in a repo — git segment aqua with the clean marker, no spinner.
2. `cargo build` running — tab spinner turns, process icon is the Rust glyph.
3. Claude Code working — robot segment green with a spinner.
4. Claude Code waiting — segment amber, a toast appears.
5. `cd` to a non-repo directory — git segment disappears entirely, no placeholder.

- [ ] **Step 3: Confirm the long-run notification**

Start a build longer than 30 seconds, switch to another tab before it finishes, and confirm one toast arrives naming the command and its duration. Repeat with the tab focused and confirm no toast.

- [ ] **Step 4: Write the README**

Create `README.md`:

```markdown
# dotfiles

WezTerm and Neovim configuration for Windows, macOS, and Linux.

- `wezterm/` — modular WezTerm config: bottom powerline bar via `tabline.wez`,
  per-process icons, an activity spinner, git state, AI agent state, and
  desktop notifications.
- `nvim/` — LazyVim, with `smart-splits.nvim` for unified pane navigation.
- `docs/specs/` — design documents. `docs/plans/` — implementation plans.

## Layout

Config directories are links back into this repo:

| Target | Points at |
| --- | --- |
| `~/.config/wezterm` | `wezterm/` |
| `~/.config/nvim` (macOS, Linux) | `nvim/` |
| `%LOCALAPPDATA%\nvim` (Windows) | `nvim/` |

Windows uses directory junctions, which need neither administrator rights nor
Developer Mode.

## Requirements

WezTerm **nightly**, Neovim 0.10 or newer, and JetBrainsMono Nerd Font.

## Local overrides

`wezterm/local.lua` is gitignored and loaded last. Return a table from it to
override any setting on a single machine.

## Tests

```
nvim -l wezterm/tests/run.lua
```

No dependencies — the harness is 40 lines of Lua and the runner is Neovim.
```

- [ ] **Step 5: Commit**

```bash
git add README.md
git commit -m "docs: add the repository readme

Covers the layout, the link targets per platform, the nightly WezTerm
requirement, the local.lua override hatch, and how to run the tests.
The installer plan extends this with the bootstrap one-liners."
```

---

## Self-Review

**Spec coverage.** Repository layout → Task 1. platform.lua → Task 6. theme.lua including bottom bar → Task 6. icons.lua → Task 2. activity.lua → Task 3. git.lua → Task 4. agent.lua → Task 5. bar.lua and the tabline section map → Task 7. keys.lua → Task 8. Plugins table → Task 7. Neovim integration → Task 9. Secrets and `local.lua` → Task 1 (`.gitignore`) and Task 7 (loader). Verification → Task 10. Bootstrap, catalog, resolver, and the installer are **deliberately absent** — they are the second plan.

**Type consistency.** `icons.lookup` returns `{glyph, color, kind}` in Task 2 and is consumed as `.kind` in Task 3 and `.glyph` in Task 7. `activity.update` returns `{busy, glyph, elapsed, notify}` in Task 3 and is consumed by both `bar.lua` handlers in Task 7. `git.render` returns `{text, color}` or nil in Task 4, consumed in Task 7. `agent.update` returns `{segment, notify}` in Task 5, consumed in Task 7. `platform.detect` returns the record used by `theme.apply` and `keys.apply` in Tasks 6–8. `keys.build(mod_primary)` in Task 8 matches `platform.mod_primary` from Task 6.

**Known gap, carried deliberately.** Whether an animated spinner inside a tab title repaints on the status timer is unverified until Task 7 Step 4 runs on a real WezTerm nightly. The fallback is written into that step, and it changes nothing outside those two anonymous functions.
