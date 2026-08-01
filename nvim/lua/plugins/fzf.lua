return {
  "ibhagwan/fzf-lua",
  dependencies = { "nvim-tree/nvim-web-devicons" },
  config = function()
    local fzf = require("fzf-lua")
    fzf.setup({})

    -- Keymaps
    vim.keymap.set("n", "<leader>ff", fzf.files, { desc = "Find Files" })
    vim.keymap.set("n", "<leader>fg", fzf.live_grep, { desc = "Live Grep" })
    vim.keymap.set("n", "<leader>fb", fzf.buffers, { desc = "Find Buffers" })
  end
}

