-- The Neovim half of the shared icon registry.
--
-- mini.icons already ships tables for extensions, filetypes, exact file names,
-- directories, LSP kinds and operating systems, and LazyVim already defines
-- diagnostic, git and DAP icons. Neither is redefined here. What is here is
-- the override: the languages whose glyph and colour must match the WezTerm
-- tab bar, which draws from the same shared/icons.lua.
local M = {}

-- shared/ sits beside nvim/ in the repository, and stdpath("config") is the
-- junction %LOCALAPPDATA%\nvim points at it through. Windows resolves ".." on
-- a junction lexically, so the real path has to be asked for explicitly.
local function shared_dir()
  local config = vim.fn.stdpath("config")
  local real = vim.uv.fs_realpath(config) or config
  return vim.fs.dirname(real:gsub("\\", "/")) .. "/shared"
end

-- A missing shared/ means the repository is not intact -- the config was copied
-- rather than linked, or the clone is partial. That is not a state to paper
-- over with a second copy of the palette: a duplicate here would be one more
-- thing to drift, which is the problem shared/ exists to solve. Fail loudly
-- and name the path that was looked for.
local function load_shared()
  local dir = shared_dir()
  if not vim.uv.fs_stat(dir .. "/icons.lua") then
    error("shared/icons.lua not found at " .. dir .. " -- is the nvim config linked into the dotfiles repo?", 0)
  end
  package.path = dir .. "/?.lua;" .. package.path
  return { icons = require("icons"), palette = require("palette").wave }
end

local shared = load_shared()

M.palette = shared.palette
M.entries = shared.icons.entries

-- Which registry entry colours which Neovim filetype. A filetype not listed
-- here keeps whatever mini.icons already gives it.
local FILETYPE = {
  java = "java",
  kotlin = "kotlin",
  rust = "rust",
  python = "python",
  typescript = "typescript",
  typescriptreact = "typescript",
  javascript = "javascript",
  javascriptreact = "javascript",
  lua = "lua",
  markdown = "markdown",
  json = "json",
  jsonc = "json",
  yaml = "yaml",
  toml = "toml",
  dockerfile = "docker",
  go = "go",
  sh = "bash",
  bash = "bash",
  ps1 = "pwsh",
}

local EXTENSION = {
  java = "java",
  kt = "kotlin",
  kts = "kotlin",
  rs = "rust",
  py = "python",
  ts = "typescript",
  tsx = "typescript",
  js = "javascript",
  jsx = "javascript",
  lua = "lua",
  md = "markdown",
  json = "json",
  yaml = "yaml",
  yml = "yaml",
  toml = "toml",
  go = "go",
  sh = "bash",
  ps1 = "pwsh",
}

-- One highlight group per registry entry, so mini.icons can point at them.
local function ensure_highlights()
  for name, entry in pairs(M.entries) do
    vim.api.nvim_set_hl(0, "SharedIcon" .. name, { fg = entry.color })
  end
end

-- mini.icons takes overrides as opts; this returns the two tables its
-- `extension` and `filetype` keys want.
function M.mini_icons_opts()
  local extension, filetype = {}, {}
  for ext, key in pairs(EXTENSION) do
    local entry = M.entries[key]
    if entry then
      extension[ext] = { glyph = entry.glyph, hl = "SharedIcon" .. key }
    end
  end
  for ft, key in pairs(FILETYPE) do
    local entry = M.entries[key]
    if entry then
      filetype[ft] = { glyph = entry.glyph, hl = "SharedIcon" .. key }
    end
  end
  return { extension = extension, filetype = filetype }
end

function M.setup()
  ensure_highlights()
  -- Colours are cleared by a colorscheme change, so they are put back.
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = vim.api.nvim_create_augroup("SharedIcons", { clear = true }),
    callback = ensure_highlights,
  })

  vim.api.nvim_create_user_command("IconAudit", function()
    local lines = { "Shared icon registry -- glyph, name, colour", "" }
    local names = vim.tbl_keys(M.entries)
    table.sort(names)
    for _, name in ipairs(names) do
      local entry = M.entries[name]
      table.insert(lines, string.format("  %s   %-12s %s", entry.glyph, name, entry.color))
    end
    table.insert(lines, "")
    table.insert(lines, "A blank cell above is a glyph the font does not have.")
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false
    vim.cmd("vsplit")
    vim.api.nvim_win_set_buf(0, buf)
  end, { desc = "Render every shared icon for a visual check" })
end

return M
