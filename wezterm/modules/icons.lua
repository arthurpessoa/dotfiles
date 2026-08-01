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
