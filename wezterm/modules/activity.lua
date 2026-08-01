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
