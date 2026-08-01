local wezterm = require("wezterm")
local icons = require("modules.icons")

local M = {}

-- WezTerm's own foreground process is the deepest one it can find in the pane's
-- process tree, which is the wrong end of it for anything that spawns helpers.
-- A Claude Code pane is pwsh -> claude -> {bash, python -m some_mcp_server}, and
-- the tab ends up named after whichever MCP server happens to sit deepest. What
-- the tab should name is the thing the user started, so the tree is walked back
-- up to the pane's root and the first process that is not a shell wins.

-- Only ever hosts something else, so it is never the answer unless it is all
-- there is. bash is here twice over: it is a shell in its own right and it is
-- also what Claude Code runs every command through.
M.SHELLS = {
  pwsh = true, powershell = true, cmd = true, conhost = true,
  bash = true, sh = true, dash = true, zsh = true, fish = true,
  wsl = true, wslhost = true, login = true, env = true,
}

-- Walking up stops here: above the pane's root process is WezTerm itself.
M.ROOTS = {
  ["wezterm-gui"] = true, wezterm = true, ["wezterm-mux-server"] = true,
}

-- A pane's tree is a handful of processes deep; the cap is only there so a
-- surprise cycle in the parent chain cannot spin.
M.MAX_DEPTH = 16

-- How long a resolved name stands before the tree is walked again.
--
-- Every lookup() is a wezterm.procinfo call, and on Windows that is a snapshot
-- of the whole system process table, not a read of one pid. A resolve is up to
-- MAX_DEPTH of them. The callers are worse than they look: update-status walks
-- one per tab, the agent segment walks one more, and format-tab-title walks two
-- per tab (the name and the busy marker) on every tab-bar repaint -- so a
-- three-tab window was taking around a hundred and sixty snapshots per 120ms
-- tick, on the GUI thread, which is what stalls the window while a pane is
-- spawning children. One walk per pane per second is enough for a tab title.
M.CACHE_SECONDS = 1.0

-- Panes come and go; the table is wiped rather than swept, since it is rebuilt
-- from one walk each and is only ever a few dozen entries.
local MAX_ENTRIES = 64

local cache = {}
local cache_count = 0

-- lookup(pid) answers `{ name = <basename>, ppid = <number> }`, or nil where
-- the process is gone. Returned root first, so the caller reads it the same
-- direction the user built it: shell, then what they typed, then its children.
function M.chain(pid, lookup)
  local names, seen = {}, {}
  local current = pid

  for _ = 1, M.MAX_DEPTH do
    if not current or seen[current] then break end
    seen[current] = true

    local info = lookup(current)
    if not info or not info.name or info.name == "" then break end
    if M.ROOTS[info.name] then break end

    table.insert(names, 1, info.name)
    current = info.ppid
  end

  return names
end

-- The shallowest process that is not a shell: `pwsh -> claude -> bash` is
-- claude, `pwsh -> cargo` is cargo, and a pane sitting at a prompt is its own
-- shell. A shell started from a shell falls back to the inner one rather than
-- naming the tab after the outer.
function M.pick(chain)
  for _, name in ipairs(chain) do
    if not M.SHELLS[name] then return name end
  end
  return chain[#chain] or ""
end

local function now_seconds()
  return tonumber(wezterm.time.now():format("%s%.3f"))
end

-- compute() is only called where there is no fresh answer for this pane. A nil
-- pane_id (a pane that has gone away mid-tick) is never cached.
function M.cached(pane_id, compute)
  if pane_id == nil then return compute() end

  local entry = cache[pane_id]
  local now = now_seconds()
  if entry and (now - entry.at) < M.CACHE_SECONDS then
    return entry.name
  end

  local name = compute()
  if not entry then
    if cache_count >= MAX_ENTRIES then
      cache, cache_count = {}, 0
    end
    cache_count = cache_count + 1
  end
  cache[pane_id] = { name = name, at = now }
  return name
end

function M.reset_cache()
  cache, cache_count = {}, 0
end

function M.lookup(pid)
  local info = wezterm.procinfo.get_info_for_pid(pid)
  if not info then return nil end
  return { name = icons.basename(info.executable or info.name), ppid = info.ppid }
end

-- Everything below talks to WezTerm and is therefore untested; the parts worth
-- testing are chain() and pick() above, which are pure.

function M.resolve_uncached(pane)
  if not pane then return "" end

  local ok, info = pcall(function() return pane:get_foreground_process_info() end)
  if ok and info and info.pid then
    local name = M.pick(M.chain(info.pid, M.lookup))
    if name ~= "" then return name end
  end

  -- No process info: a remote domain, or the process exited mid-call.
  local named, raw = pcall(function() return pane:get_foreground_process_name() end)
  return named and icons.basename(raw) or ""
end

function M.resolve(pane)
  if not pane then return "" end
  local ok, pane_id = pcall(function() return pane:pane_id() end)
  return M.cached(ok and pane_id or nil, function() return M.resolve_uncached(pane) end)
end

-- format-tab-title is handed PaneInformation, which carries the process name
-- but no pid, so the real pane is fetched to get at the tree. The plain name is
-- the fallback, minus its ".exe" -- which is the other half of why tabs read
-- "python.exe" today.
--
-- The cache is consulted from the pane id PaneInformation already carries, so a
-- hit costs neither the mux lookup nor the walk. Both callers of this end up on
-- the same cache entry as M.resolve, which is the point: the status tick and
-- the two tab-bar components ask about the same pane within milliseconds.
function M.for_pane_info(pane_info)
  if not pane_info then return "" end

  return M.cached(pane_info.pane_id, function()
    local ok, pane = pcall(wezterm.mux.get_pane, pane_info.pane_id)
    if ok and pane then
      local name = M.resolve_uncached(pane)
      if name ~= "" then return name end
    end
    return icons.basename(pane_info.foreground_process_name)
  end)
end

return M
