-- ai.copilot brings copilot.lua with a blink.cmp source, so suggestions arrive
-- in the same menu as LSP completions; ai.claudecode brings Claude Code.
-- Neither needs configuring here. codecompanion does: it keeps a second
-- adapter so a chat can be pointed at Anthropic directly rather than through
-- Copilot.
--
-- Keys deliberately avoid <leader>ac/<leader>aC: the ai.claudecode extra
-- already owns those ("Toggle Claude" / "Continue Claude"). codecompanion
-- gets <leader>ai/<leader>ao/<leader>ak instead, which are unclaimed under
-- the <leader>a ("+ai") group that claudecode/copilot already populate.
return {
  {
    "olimorris/codecompanion.nvim",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-treesitter/nvim-treesitter",
    },
    cmd = { "CodeCompanion", "CodeCompanionChat", "CodeCompanionActions" },
    keys = {
      { "<leader>ao", "<cmd>CodeCompanionChat Toggle<cr>", desc = "CodeCompanion Chat", mode = { "n", "v" } },
      { "<leader>ak", "<cmd>CodeCompanionActions<cr>", desc = "CodeCompanion Actions", mode = { "n", "v" } },
      { "<leader>ai", "<cmd>CodeCompanion<cr>", desc = "CodeCompanion Inline", mode = { "n", "v" } },
    },
    opts = {
      -- `interactions` is the current config root (codecompanion.nvim
      -- v19.22.0); the older `strategies` name still works via a
      -- backward-compat shim in config.lua but is due for removal in v20.
      interactions = {
        chat = { adapter = "copilot" },
        inline = { adapter = "copilot" },
      },
      -- Custom adapters must live under adapters.http (or adapters.acp), not
      -- as a top-level key: adapter resolution reads config.adapters.http[name].
      -- Absent ANTHROPIC_API_KEY, this adapter is simply not selectable;
      -- copilot stays the default chat/inline adapter either way.
      adapters = {
        http = {
          anthropic = function()
            return require("codecompanion.adapters").extend("anthropic", {
              env = { api_key = "ANTHROPIC_API_KEY" },
            })
          end,
        },
      },
      display = {
        chat = {
          window = { layout = "vertical", width = 0.4 },
        },
      },
    },
  },
}
