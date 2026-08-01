return {

  {
    "mfussenegger/nvim-dap",

    dependencies = {

      "rcarriga/nvim-dap-ui",

      "theHamsta/nvim-dap-virtual-text",
    },

    config = function()
      local dap = require("dap")

      vim.keymap.set("n", "<F5>", dap.continue)

      vim.keymap.set("n", "<F10>", dap.step_over)
    end,
  },
}
