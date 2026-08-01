return {
  "rebelot/kanagawa.nvim",
  lazy = false,    -- Load immediately during startup
  priority = 1000, -- Ensure it loads before other plugins
  config = function()
    -- Setup options (optional)
    require("kanagawa").setup({
      compile = false,
      undercurl = true,
      commentStyle = { italic = true },
    })
    
    -- Load the colorscheme
    vim.cmd("colorscheme kanagawa")
  end,
}
