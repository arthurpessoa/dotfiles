local u = require("glyph").u
local p = require("palette").wave

local M = {}

-- "busy" marks a process whose presence means work is happening, which is what
-- the tab's activity marker and the notification on busy -> idle key off.
-- "shell" is everything else: an interactive process the user is sitting in.
local BUSY = "busy"
local SHELL = "shell"

M.FALLBACK = { glyph = u(0xf018d), color = p.gray, kind = SHELL }

M.entries = {
  -- Rust
  cargo = { glyph = u(0xe7a8), color = p.red, kind = BUSY },
  rustc = { glyph = u(0xe7a8), color = p.red, kind = BUSY },
  rustup = { glyph = u(0xe7a8), color = p.red, kind = BUSY },

  -- JavaScript and TypeScript
  node = { glyph = u(0xf0399), color = p.green, kind = BUSY },
  npm = { glyph = u(0xf06f7), color = p.green, kind = BUSY },
  pnpm = { glyph = u(0xf06f7), color = p.green, kind = BUSY },
  yarn = { glyph = u(0xe8ec), color = p.green, kind = BUSY },
  tsc = { glyph = u(0xf06e6), color = p.blue, kind = BUSY },

  -- JVM
  java = { glyph = u(0xe738), color = p.yellow, kind = BUSY },
  javaw = { glyph = u(0xe738), color = p.yellow, kind = BUSY },
  gradle = { glyph = u(0xe7f2), color = p.yellow, kind = BUSY },
  gradlew = { glyph = u(0xe7f2), color = p.yellow, kind = BUSY },
  mvn = { glyph = u(0xe82c), color = p.yellow, kind = BUSY },
  kotlinc = { glyph = u(0xe81b), color = p.yellow, kind = BUSY },

  -- Python
  python = { glyph = u(0xe73c), color = p.blue, kind = BUSY },
  uv = { glyph = u(0xe73c), color = p.blue, kind = BUSY },
  pip = { glyph = u(0xe73c), color = p.blue, kind = BUSY },
  pytest = { glyph = u(0xe73c), color = p.blue, kind = BUSY },

  -- Other toolchains
  go = { glyph = u(0xe724), color = p.aqua, kind = BUSY },
  docker = { glyph = u(0xe7b0), color = p.blue, kind = BUSY },
  make = { glyph = u(0xe673), color = p.white, kind = BUSY },
  cmake = { glyph = u(0xe794), color = p.white, kind = BUSY },
  ninja = { glyph = u(0xf0774), color = p.white, kind = BUSY },
  msbuild = { glyph = u(0xf0610), color = p.white, kind = BUSY },
  git = { glyph = u(0xe702), color = p.red, kind = BUSY },

  -- Shells and editors
  pwsh = { glyph = u(0xf0a0a), color = p.blue, kind = SHELL },
  powershell = { glyph = u(0xf0a0a), color = p.blue, kind = SHELL },
  cmd = { glyph = u(0xf05b3), color = p.white, kind = SHELL },
  bash = { glyph = u(0xebca), color = p.white, kind = SHELL },
  zsh = { glyph = u(0xe691), color = p.white, kind = SHELL },
  fish = { glyph = u(0xf023a), color = p.white, kind = SHELL },
  wsl = { glyph = u(0xf31a), color = p.red, kind = SHELL },
  ssh = { glyph = u(0xf08c0), color = p.aqua, kind = SHELL },
  nvim = { glyph = u(0xe6ae), color = p.green, kind = SHELL },
  vim = { glyph = u(0xe62b), color = p.green, kind = SHELL },
  claude = { glyph = u(0xf06a9), color = p.green, kind = SHELL },
  kiro = { glyph = u(0xf06a9), color = p.green, kind = SHELL },
  copilot = { glyph = u(0xf06a9), color = p.green, kind = SHELL },

  -- Filetype-only entries. Nothing spawns these as a process, but Neovim
  -- needs them to colour buffers and the picker, so they live here to stay in
  -- step with the process icons above.
  lua = { glyph = u(0xe620), color = p.blue, kind = SHELL },
  markdown = { glyph = u(0xe73e), color = p.white, kind = SHELL },
  json = { glyph = u(0xe60b), color = p.yellow, kind = SHELL },
  yaml = { glyph = u(0xe6a8), color = p.violet, kind = SHELL },
  toml = { glyph = u(0xe6b2), color = p.orange, kind = SHELL },
  kotlin = { glyph = u(0xe81b), color = p.yellow, kind = SHELL },
  typescript = { glyph = u(0xf06e6), color = p.blue, kind = SHELL },
  javascript = { glyph = u(0xf0399), color = p.yellow, kind = SHELL },
  rust = { glyph = u(0xe7a8), color = p.red, kind = SHELL },
}

function M.basename(path)
  if not path or path == "" then
    return ""
  end
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
