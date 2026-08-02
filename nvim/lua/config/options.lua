-- Options are automatically loaded before lazy.nvim startup.
-- Defaults: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua

local opt = vim.opt

-- wezterm/modules/theme.lua uses BlinkingBar at 600ms with an eased blink.
-- Neovim cannot ease, but matching the shape and the rate stops the cursor
-- changing character when focus moves between the shell and the editor.
opt.guicursor = table.concat({
  "n-v-c:block-Cursor/lCursor",
  "i-ci-ve:ver25-Cursor/lCursor",
  "r-cr:hor20",
  "o:hor50",
  "a:blinkwait600-blinkoff600-blinkon600",
}, ",")

-- Folds come from treesitter, closed only when asked for.
opt.foldlevel = 99
opt.foldmethod = "expr"
opt.foldexpr = "v:lua.vim.treesitter.foldexpr()"

-- Keep some context above and below the cursor, as an IDE would.
opt.scrolloff = 8
opt.sidescrolloff = 8

-- Diagnostics and git signs share one column rather than shifting the text
-- every time a sign appears.
opt.signcolumn = "yes"
