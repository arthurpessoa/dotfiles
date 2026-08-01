return {

  {
    "simrat39/rust-tools.nvim",

    dependencies = {
      "neovim/nvim-lspconfig",
    },

    config = function()
      require("rust-tools").setup({

        server = {

          settings = {

            ["rust-analyzer"] = {

              cargo = {
                allFeatures = true,
              },

              procMacro = {
                enable = true,
              },

              checkOnSave = {
                command = "clippy",
              },
            },
          },
        },
      })
    end,
  },
}
