local M = {}

-- UTF-8 codepoint encoding lives in modules/glyph.lua — shared with git.lua,
-- which must not depend on icons.lua for an unrelated concern.
local u = require("modules.glyph").u

M.FALLBACK = { glyph = u(0xf018d), color = "#727169", kind = "shell" }

local BUSY = "busy"
local SHELL = "shell"

M.entries = {
  cargo   = { glyph = u(0xe7a8), color = "#E46876", kind = BUSY },
  rustc   = { glyph = u(0xe7a8), color = "#E46876", kind = BUSY },
  rustup  = { glyph = u(0xe7a8), color = "#E46876", kind = BUSY },
  node    = { glyph = u(0xf0399), color = "#98BB6C", kind = BUSY },
  npm     = { glyph = u(0xf06f7), color = "#98BB6C", kind = BUSY },
  pnpm    = { glyph = u(0xf06f7), color = "#98BB6C", kind = BUSY },
  yarn    = { glyph = u(0xe8ec), color = "#98BB6C", kind = BUSY },
  tsc     = { glyph = u(0xf06e6), color = "#7E9CD8", kind = BUSY },
  java    = { glyph = u(0xe738), color = "#E6C384", kind = BUSY },
  javaw   = { glyph = u(0xe738), color = "#E6C384", kind = BUSY },
  gradle  = { glyph = u(0xe7f2), color = "#E6C384", kind = BUSY },
  gradlew = { glyph = u(0xe7f2), color = "#E6C384", kind = BUSY },
  mvn     = { glyph = u(0xe82c), color = "#E6C384", kind = BUSY },
  kotlinc = { glyph = u(0xe81b), color = "#E6C384", kind = BUSY },
  python  = { glyph = u(0xe73c), color = "#7E9CD8", kind = BUSY },
  uv      = { glyph = u(0xe73c), color = "#7E9CD8", kind = BUSY },
  pip     = { glyph = u(0xe73c), color = "#7E9CD8", kind = BUSY },
  pytest  = { glyph = u(0xe73c), color = "#7E9CD8", kind = BUSY },
  go      = { glyph = u(0xe724), color = "#7AA89F", kind = BUSY },
  docker  = { glyph = u(0xe7b0), color = "#7E9CD8", kind = BUSY },
  make    = { glyph = u(0xe673), color = "#C8C093", kind = BUSY },
  cmake   = { glyph = u(0xe794), color = "#C8C093", kind = BUSY },
  ninja   = { glyph = u(0xf0774), color = "#C8C093", kind = BUSY },
  msbuild = { glyph = u(0xf0610), color = "#C8C093", kind = BUSY },
  git     = { glyph = u(0xe702), color = "#E46876", kind = BUSY },

  pwsh       = { glyph = u(0xf0a0a), color = "#7E9CD8", kind = SHELL },
  powershell = { glyph = u(0xf0a0a), color = "#7E9CD8", kind = SHELL },
  cmd        = { glyph = u(0xf05b3), color = "#C8C093", kind = SHELL },
  bash       = { glyph = u(0xebca), color = "#C8C093", kind = SHELL },
  zsh        = { glyph = u(0xe691), color = "#C8C093", kind = SHELL },
  fish       = { glyph = u(0xf023a), color = "#C8C093", kind = SHELL },
  wsl        = { glyph = u(0xf31a), color = "#E46876", kind = SHELL },
  ssh        = { glyph = u(0xf08c0), color = "#7AA89F", kind = SHELL },
  nvim       = { glyph = u(0xe6ae), color = "#98BB6C", kind = SHELL },
  vim        = { glyph = u(0xe62b), color = "#98BB6C", kind = SHELL },
  claude     = { glyph = u(0xf06a9), color = "#98BB6C", kind = SHELL },
  kiro       = { glyph = u(0xf06a9), color = "#98BB6C", kind = SHELL },
  copilot    = { glyph = u(0xf06a9), color = "#98BB6C", kind = SHELL },
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
