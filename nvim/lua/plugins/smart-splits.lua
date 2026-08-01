-- The Neovim half of the CTRL+hjkl bindings. WezTerm forwards those keys into
-- the pane when it is running Neovim (see wezterm/modules/keys.lua), and
-- smart-splits decides whether to move a Neovim split or hand the motion back
-- to the multiplexer at the edge.
return {
  "mrjones2014/smart-splits.nvim",
  lazy = false,
  opts = {
    at_edge = "stop",
    ignored_filetypes = { "nofile", "quickfix", "prompt" },
  },
  keys = {
    { "<C-h>", function() require("smart-splits").move_cursor_left() end, desc = "Move to left split" },
    { "<C-j>", function() require("smart-splits").move_cursor_down() end, desc = "Move to below split" },
    { "<C-k>", function() require("smart-splits").move_cursor_up() end, desc = "Move to above split" },
    { "<C-l>", function() require("smart-splits").move_cursor_right() end, desc = "Move to right split" },
  },
}
