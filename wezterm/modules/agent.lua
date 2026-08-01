local activity = require("modules.activity")
local icons = require("modules.icons")
local glyph = require("modules.glyph")

local M = {}

-- Glyphs are built from codepoints, never written as literal characters:
-- Private Use Area and supplementary-plane glyphs get silently stripped or
-- mangled in transit and land as empty strings. See git.lua / icons.lua.
local ROBOT = glyph.u(0xf06a9) -- nf-md-robot, same codepoint icons.lua uses for claude
local WAITING_GLYPH = glyph.u(0x25d4) -- circle with upper right quadrant black
local IDLE_GLYPH = glyph.u(0x25cb) -- white circle

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
