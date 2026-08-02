-- dap.core supplies nvim-dap, dap-ui, virtual text and the <leader>d* maps,
-- including <leader>dB for a conditional breakpoint. This adds the breakpoint
-- kinds it leaves out, the signs, the IntelliJ F-keys and the persistence.
--
-- The sign characters are Unicode geometric shapes, not Nerd Font glyphs:
-- U+25CF is the same character wezterm/modules/bar.lua uses for its busy
-- marker, so it is already proven to render, and none of these depend on the
-- font being a patched one.
--
-- Their colours are links to groups the colorscheme already defines rather
-- than literal hexes, so the signs follow a theme change without this file
-- knowing anything about the palette.
local function sign(name, text, hl, numhl)
  vim.fn.sign_define(name, { text = text, texthl = hl, numhl = numhl or "" })
end

return {
  {
    "mfussenegger/nvim-dap",
    optional = true,
    keys = {
      {
        "<leader>dL",
        function()
          require("dap").set_breakpoint(nil, nil, vim.fn.input("Log message (use {expr} to interpolate): "))
        end,
        desc = "Breakpoint Log Message",
      },
      {
        "<leader>dh",
        function()
          require("dap").set_breakpoint(nil, vim.fn.input("Stop on hit count: "), nil)
        end,
        desc = "Breakpoint Hit Count",
      },
      {
        "<leader>dx",
        function()
          require("dap").clear_breakpoints()
          vim.notify("All breakpoints cleared", vim.log.levels.INFO)
        end,
        desc = "Clear All Breakpoints",
      },
      {
        "<leader>d?",
        function()
          require("dap").list_breakpoints()
          vim.cmd("copen")
        end,
        desc = "List Breakpoints",
      },

      -- IntelliJ's debugger keys. None of F5 through F12 is bound by Neovim
      -- by default, so these take nothing away.
      {
        "<F5>",
        function()
          require("dap").continue()
        end,
        desc = "Debug: Continue",
      },
      {
        "<F9>",
        function()
          require("dap").continue()
        end,
        desc = "Debug: Resume (IDEA)",
      },
      {
        "<F8>",
        function()
          require("dap").step_over()
        end,
        desc = "Debug: Step Over (IDEA)",
      },
      {
        "<F7>",
        function()
          require("dap").step_into()
        end,
        desc = "Debug: Step Into (IDEA)",
      },
      {
        "<S-F8>",
        function()
          require("dap").step_out()
        end,
        desc = "Debug: Step Out (IDEA)",
      },
      {
        "<C-F8>",
        function()
          require("dap").toggle_breakpoint()
        end,
        desc = "Debug: Toggle Breakpoint (IDEA)",
      },
      {
        "<C-S-F8>",
        function()
          require("dap").set_breakpoint(vim.fn.input("Breakpoint condition: "))
        end,
        desc = "Debug: Conditional Breakpoint (IDEA)",
      },
      {
        "<C-F2>",
        function()
          require("dap").terminate()
        end,
        desc = "Debug: Terminate (IDEA)",
      },
    },
    config = function()
      -- This `config` is allowed: dap.core declares nvim-dap with an opts
      -- table, and LazyVim's own spec runs first. Signs and autocmds are not
      -- expressible as opts, which is the only reason a function is used here.
      local function link(from, to)
        vim.api.nvim_set_hl(0, from, { link = to, default = false })
      end

      link("DapBreakpoint", "DiagnosticError")
      link("DapBreakpointCondition", "DiagnosticWarn")
      link("DapLogPoint", "DiagnosticInfo")
      link("DapBreakpointRejected", "Comment")
      link("DapStopped", "DiagnosticOk")
      link("DapStoppedLine", "Visual")

      sign("DapBreakpoint", "●", "DapBreakpoint")
      sign("DapBreakpointCondition", "◆", "DapBreakpointCondition")
      sign("DapLogPoint", "◆", "DapLogPoint")
      sign("DapBreakpointRejected", "○", "DapBreakpointRejected")
      sign("DapStopped", "▶", "DapStopped", "DapStoppedLine")

      require("util.dap_persist").setup()
    end,
  },

  -- The panels dock rather than displacing an editor split. ui.edgy owns the
  -- placement; dap.core already opens and closes them with the session.
  {
    "folke/edgy.nvim",
    optional = true,
    opts = function(_, opts)
      opts.left = opts.left or {}
      opts.bottom = opts.bottom or {}
      vim.list_extend(opts.left, {
        { ft = "dapui_scopes", size = { height = 0.25 } },
        { ft = "dapui_breakpoints", size = { height = 0.2 } },
        { ft = "dapui_stacks", size = { height = 0.25 } },
        { ft = "dapui_watches", size = { height = 0.25 } },
      })
      vim.list_extend(opts.bottom, {
        { ft = "dap-repl", size = { height = 0.3 } },
        { ft = "dapui_console", size = { height = 0.3 } },
      })
      return opts
    end,
  },
}
