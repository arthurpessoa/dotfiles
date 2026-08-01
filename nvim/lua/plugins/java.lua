return {

  {
    "mfussenegger/nvim-jdtls",

    ft = "java",

    config = function()
      vim.cmd([[
autocmd FileType java lua require('jdtls').start_or_attach({})
]])
    end,
  },
}
