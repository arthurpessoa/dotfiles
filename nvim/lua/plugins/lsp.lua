return {

  {
    "mason-org/mason.nvim",
    build = ":MasonUpdate",
    config = true,
  },

  {
    "mason-org/mason-lspconfig.nvim",
    dependencies = {
      "neovim/nvim-lspconfig",
    },

    config = function()
      require("mason-lspconfig").setup({
        ensure_installed = {

          -- Java
          "jdtls",

          -- Kotlin
          "kotlin_language_server",

          -- Rust
          "rust_analyzer",

          -- General
          "lua_ls",
          "jsonls",
          "yamlls",
        },
      })
    end,
  },

  {
    "neovim/nvim-lspconfig",

    config = function()
      local lsp = require("lspconfig")

      lsp.jdtls.setup({
        settings = {
          java = {
            format = {
              enabled = true,
            },
          },
        },
      })

      lsp.kotlin_language_server.setup({})

      lsp.rust_analyzer.setup({
        settings = {
          ["rust-analyzer"] = {
            cargo = {
              allFeatures = true,
            },
            checkOnSave = {
              command = "clippy",
            },
          },
        },
      })
    end,
  },
}
