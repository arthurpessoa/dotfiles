return {

  {
    "olimorris/codecompanion.nvim",

    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-treesitter/nvim-treesitter",
    },

    config = function()
      require("codecompanion").setup({

        strategies = {

          chat = {
            adapter = "copilot",
          },

          inline = {
            adapter = "copilot",
          },
        },

        display = {
          chat = {
            window = {
              layout = "vertical",
              width = 0.4,
            },
          },
        },
      })

      vim.keymap.set("n", "<leader>ai", "<cmd>CodeCompanionChat<CR>")
    end,
  },
}
