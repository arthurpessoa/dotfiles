-- lua/plugins/treesitter.lua

return {
  {
    "nvim-treesitter/nvim-treesitter",
    branch = "master",
    build = ":TSUpdate",
    event = { "BufReadPost", "BufNewFile" },
    cmd = {
      "TSUpdateSync",
      "TSUpdate",
      "TSInstall",
    },
    keys = {
      {
        "<c-space>",
        desc = "Increment Selection",
      },
      {
        "<bs>",
        desc = "Decrement Selection",
        mode = "x",
      },
    },
    opts = {
      highlight = {
        enable = true,
      },

      indent = {
        enable = true,
      },

      ensure_installed = {
        "bash",
        "c",
        "diff",
        "html",
        "javascript",
        "jsdoc",
        "json",
        "jsonc",
        "lua",
        "luadoc",
        "luap",
        "markdown",
        "markdown_inline",
        "printf",
        "python",
        "query",
        "regex",
        "toml",
        "tsx",
        "typescript",
        "vim",
        "vimdoc",
        "xml",
        "yaml",

        -- Java stack
        "java",
        "kotlin",
        "rust",
      },

      incremental_selection = {
        enable = true,

        keymaps = {
          init_selection = "<c-space>",
          node_incremental = "<c-space>",
          scope_incremental = false,
          node_decremental = "<bs>",
        },
      },
    },
  },

  ----------------------------------------------------------
  -- Mason tools
  ----------------------------------------------------------

  {
    "mason/mason.nvim",
    opts = {
      ensure_installed = {
        "tree-sitter-cli",
      },
    },
  },
}
