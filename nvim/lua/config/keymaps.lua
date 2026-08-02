-- Keymaps are automatically loaded on the VeryLazy event.
-- Defaults: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
--
-- An IntelliJ vocabulary laid over LazyVim's, not in place of it: gd, gr,
-- <leader>ca and the rest keep working. Every key here is exactly two
-- characters after the leader, because <leader>ia and <leader>iaa cannot both
-- exist -- the shorter one wins after timeoutlen, so the longer one is
-- unreachable and the shorter one is slow. That was the bug in the previous
-- version of this file.
--
-- Debugging is deliberately absent: it lives on <leader>d from dap.core and on
-- the F-keys from lua/plugins/dap.lua.

local map = vim.keymap.set

-- config.icons seeds package.path with shared/ as a side effect of its module
-- body (see that file). Requiring it here explicitly -- rather than trusting
-- it already ran as a side effect of plugins/ui.lua having loaded first --
-- keeps this file correct even if load order ever changes; nothing else in
-- nvim/ seeds shared/ onto the path.
require("config.icons")
local u = require("glyph").u

-- U+F06E8 is md-lightbulb_on -- confirmed present in the JetBrainsMono Nerd
-- Font cmap. Built from its codepoint rather than pasted literally: glyphs in
-- the supplementary planes get flattened to ASCII spaces by anything in the
-- authoring pipeline that assumes text is safe to normalise.
local IDEA = u(0xf06e8) .. " IDEA"

local function desc(text)
  return { desc = IDEA .. ": " .. text }
end

-- Navigation ---------------------------------------------------------------

map("n", "<leader>ib", vim.lsp.buf.definition, desc("Go to Definition")) -- Ctrl+B
map("n", "<leader>ig", vim.lsp.buf.implementation, desc("Go to Implementation")) -- Ctrl+Alt+B
map("n", "<leader>it", vim.lsp.buf.type_definition, desc("Type Definition")) -- Ctrl+Shift+B
map("n", "<leader>iu", function()
  Snacks.picker.lsp_references()
end, desc("Find Usages")) -- Alt+F7

-- Refactor -----------------------------------------------------------------

map("n", "<leader>ir", vim.lsp.buf.rename, desc("Rename Symbol")) -- Shift+F6
map("n", "<leader>ia", vim.lsp.buf.code_action, desc("Code Action")) -- Alt+Enter
map("n", "<leader>ii", vim.lsp.buf.code_action, desc("Generate Code")) -- Alt+Insert

-- refactoring.nvim comes from the editor.refactoring extra and works in every
-- language it has a parser for; in Java, jdtls's own extract runs instead and
-- is reachable from <leader>cx.
--
-- The brief for this task assumed a generic require("refactoring").refactor
-- ("Extract Variable") API. That API does not exist in the installed
-- version (lua/refactoring.lua on both the locked commit and upstream
-- master exposes extract_var()/extract_func()/inline_var()/inline_func()
-- only, each returning an operatorfunc key sequence that must be fed back
-- via an expr mapping -- exactly the pattern LazyVim's own bundled
-- extras/editor/refactoring.lua uses for <leader>rx and <leader>rf).
-- Verified by reading the installed plugin source directly, not the brief.
map({ "n", "x" }, "<leader>iv", function()
  return require("refactoring").extract_var()
end, vim.tbl_extend("force", desc("Extract Variable"), { expr = true })) -- Ctrl+Alt+V
map({ "n", "x" }, "<leader>im", function()
  return require("refactoring").extract_func()
end, vim.tbl_extend("force", desc("Extract Method"), { expr = true })) -- Ctrl+Alt+M
map({ "n", "x" }, "<leader>ic", function()
  return require("refactoring").extract_var()
end, vim.tbl_extend("force", desc("Extract Constant"), { expr = true })) -- Ctrl+Alt+C

-- Code ---------------------------------------------------------------------

map("n", "<leader>il", function()
  require("conform").format({ async = true, lsp_fallback = true })
end, desc("Reformat Code")) -- Ctrl+Alt+L
map("n", "<leader>iO", function()
  -- jdtls has a dedicated organiser; everywhere else the server exposes it as
  -- a source action.
  if vim.bo.filetype == "java" then
    require("jdtls").organize_imports()
  else
    vim.lsp.buf.code_action({ context = { only = { "source.organizeImports" } }, apply = true })
  end
end, desc("Optimize Imports")) -- Ctrl+Alt+O

-- Documentation and diagnostics --------------------------------------------

map("n", "<leader>ih", vim.lsp.buf.hover, desc("Quick Documentation")) -- Ctrl+Q
map("n", "<leader>ip", vim.lsp.buf.signature_help, desc("Signature Help")) -- Ctrl+P
map("n", "<leader>ie", vim.diagnostic.open_float, desc("Show Error")) -- Ctrl+F1

-- Search -------------------------------------------------------------------

map("n", "<leader>is", function()
  Snacks.picker.smart()
end, desc("Search Everywhere")) -- Shift+Shift
map("n", "<leader>if", function()
  Snacks.picker.files()
end, desc("Find File")) -- Ctrl+Shift+N
map("n", "<leader>iF", function()
  Snacks.picker.grep()
end, desc("Find in Files")) -- Ctrl+Shift+F
map("n", "<leader>iA", function()
  Snacks.picker.keymaps()
end, desc("Find Action")) -- Ctrl+Shift+A
map("n", "<leader>iR", function()
  Snacks.picker.recent()
end, desc("Recent Files")) -- Ctrl+E
map("n", "<leader>io", function()
  Snacks.picker.lsp_symbols()
end, desc("File Structure")) -- Ctrl+F12
map("n", "<leader>iT", function()
  -- IntelliJ toggles between a class and its test; the nearest equivalent
  -- without a project model is to search for the file by name.
  Snacks.picker.files({ pattern = vim.fn.expand("%:t:r") })
end, desc("Go to Test")) -- Ctrl+Shift+T

-- History ------------------------------------------------------------------

map("n", "<leader>iH", function()
  Snacks.picker.git_log()
end, desc("Git History"))

-- Editor -------------------------------------------------------------------

-- Treesitter incremental selection, which the treesitter spec binds to
-- <C-space>. remap is on so this reaches that mapping rather than inserting a
-- literal control character.
map("n", "<leader>iw", "<C-space>", { desc = IDEA .. ": Expand Selection", remap = true }) -- Ctrl+W

map("n", "<leader>iz", function()
  Snacks.zen.zoom()
end, desc("Maximize Editor")) -- Ctrl+Shift+F12
