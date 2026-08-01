return {

  ----------------------------------------------------------
  -- Mason
  ----------------------------------------------------------

  {
    "mason-org/mason.nvim",
    opts = {},
  },


  ----------------------------------------------------------
  -- Auto install external tools
  ----------------------------------------------------------

  {
    "WhoIsSethDaniel/mason-tool-installer.nvim",

    dependencies = {
      "mason-org/mason.nvim",
    },

    opts = {

      ensure_installed = {


        --------------------------------------------------
        -- Formatters
        --------------------------------------------------

        "stylua",
        "prettier",


        --------------------------------------------------
        -- Linters
        --------------------------------------------------

        "eslint_d",


        --------------------------------------------------
        -- Languages
        --------------------------------------------------

        "jdtls",
        "kotlin-language-server",
        "rust-analyzer",
        "lua-language-server",

      },


      auto_update = true,

      run_on_start = true,

    },

  },

}
