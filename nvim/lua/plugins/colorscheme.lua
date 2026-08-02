-- Kanagawa wave, the same theme wezterm/modules/theme.lua applies to the
-- terminal, applied the way LazyVim expects so that lualine, bufferline and
-- noice all derive from it. The old kanagawa.lua called vim.cmd("colorscheme")
-- from a config function, which ran after LazyVim had already chosen
-- tokyonight -- the editor changed colour, the components did not.
return {
  {
    "rebelot/kanagawa.nvim",
    lazy = false,
    priority = 1000,
    opts = {
      compile = false,
      undercurl = true,
      commentStyle = { italic = true },
      keywordStyle = { italic = false },
      theme = "wave",
      background = { dark = "wave" },

      -- wezterm dims an unfocused pane with inactive_pane_hsb; this is the
      -- same idea one level down, for splits inside a single pane.
      dimInactive = true,

      -- The terminal is at window_background_opacity 0.97 over a platform
      -- backdrop. Painting an opaque background here would cover it.
      transparent = true,
    },
  },
  {
    "LazyVim/LazyVim",
    opts = { colorscheme = "kanagawa" },
  },
}
