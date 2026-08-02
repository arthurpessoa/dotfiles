local M = {}

M.POLL_SECONDS = 4

-- Glyphs are built from codepoints, never written as literal characters:
-- Private Use Area glyphs (U+E000-F8FF) get silently stripped in transit and
-- land as empty strings. See Task 2's fix round. Derive each codepoint from
-- wezterm.nerdfonts by name rather than typing it from memory.
local u = require("glyph").u

local BRANCH_GLYPH = u(0xe725)    -- nf-dev-git-branch
local CLEAN_GLYPH = u(0xf00c)     -- nf-fa-check, a check mark
local DIRTY_GLYPH = u(0xf040)     -- nf-fa-pencil, a pencil
local AHEAD_GLYPH = u(0xf062)     -- nf-fa-arrow_up, an upward arrow
local DETACHED_GLYPH = u(0xf0718) -- kept from the brief's literal character

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
