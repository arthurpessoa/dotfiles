return {

  {
    "stevearc/conform.nvim",

    config = function()
      require("conform").setup({

        formatters_by_ft = {

          java = {
            "google-java-format",
          },

          kotlin = {
            "ktlint",
          },

          rust = {
            "rustfmt",
          },
        },
      })
    end,
  },
}
