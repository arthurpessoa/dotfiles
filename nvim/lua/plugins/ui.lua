-- Appearance, matched to the WezTerm bar directly beneath it: the same
-- powerline separators, the same section order, the same spinner cadence, and
-- buffers along the top because wezterm puts its own tabs at the bottom.
--
-- shared/ is seeded onto package.path here directly, the same pattern
-- config/keymaps.lua:16-22 documents, rather than relying on
-- require("config.icons") below to have already mutated the global
-- package.path as a side effect of its own module body. That side channel is
-- what this file depended on before: require("glyph") only resolved because
-- config.icons happened to be required first. Reordering those two lines, or
-- refactoring config.icons to stop mutating package.path, would have broken
-- this file with no indication why.
local function shared_dir()
  local config = vim.fn.stdpath("config")
  local real = vim.uv.fs_realpath(config) or config
  return vim.fs.dirname(real:gsub("\\", "/")) .. "/shared"
end
package.path = shared_dir() .. "/?.lua;" .. package.path

local icons = require("config.icons")

-- Nerd Font glyphs live in the Private Use Area and the supplementary planes;
-- both get mangled by anything that assumes text is safe to normalise, which
-- is exactly what happened to every literal glyph pasted into this file's
-- first draft. Codepoints are encoded at load time instead, the same defence
-- shared/glyph.lua exists for on the wezterm side. See that file for the
-- Lua 5.1-safe encoder this requires.
local u = require("glyph").u

return {
  -- mini.icons is LazyVim's icon provider; these are the overrides that keep
  -- it in step with the wezterm tab bar.
  {
    "nvim-mini/mini.icons",
    opts = function(_, opts)
      icons.setup()
      return vim.tbl_deep_extend("force", opts or {}, icons.mini_icons_opts())
    end,
  },

  {
    "akinsho/bufferline.nvim",
    opts = {
      options = {
        -- wezterm's tab bar is at the bottom (tab_bar_at_bottom = true), so
        -- buffers go along the top rather than stacking two bars together.
        separator_style = "slant",
        always_show_bufferline = true,
        diagnostics = "nvim_lsp",
        diagnostics_indicator = function(count, level)
          -- Same glyphs LazyVim.config.icons.diagnostics.Error/Warn use.
          local prefix = level:match("error") and (u(0xf057) .. " ") or (u(0xf071) .. " ")
          return prefix .. count
        end,
        offsets = {
          { filetype = "snacks_layout_box", text = "Explorer", highlight = "Directory", separator = true },
          { filetype = "neo-tree", text = "Explorer", highlight = "Directory", separator = true },
        },
      },
    },
  },

  {
    "nvim-lualine/lualine.nvim",
    opts = function(_, opts)
      -- The same separators tabline draws in the wezterm bar: pl_left_hard_
      -- divider and its three companions.
      opts.options = opts.options or {}
      opts.options.section_separators = { left = "", right = "" }
      opts.options.component_separators = { left = "", right = "" }
      opts.options.globalstatus = true

      opts.sections = opts.sections or {}
      opts.sections.lualine_x = opts.sections.lualine_x or {}

      -- Which language servers are attached. LazyVim shows progress; this
      -- shows what is actually running, which is what you want when a server
      -- silently failed to start. This is the only genuinely additive
      -- segment here: LazyVim's own lualine_x already carries a DAP status
      -- (lazyvim/plugins/ui.lua, guarded with `package.loaded["dap"] and
      -- ...` so it never force-loads the debugger) and a noice mode segment
      -- that already renders "recording @q" while a macro is being recorded
      -- (noice/config/status.lua's `mode` filter is Msg.events.showmode,
      -- the same event a bare :h showmode uses). table.insert(...,1,...)
      -- PREPENDS to LazyVim's existing lualine_x rather than replacing it --
      -- lazy.nvim only replaces non-table opts.sections.lualine_x wholesale,
      -- and this one is already a table by the time this function runs, so
      -- duplicate DAP and macro-recording segments here used to render
      -- twice: ours plus LazyVim's own equivalents further along the list.
      table.insert(opts.sections.lualine_x, 1, {
        function()
          local names = {}
          for _, client in ipairs(vim.lsp.get_clients({ bufnr = 0 })) do
            table.insert(names, client.name)
          end
          if #names == 0 then
            return ""
          end
          return u(0xf233) .. " " .. table.concat(names, " ")
        end,
        color = { fg = icons.palette.aqua },
      })

      return opts
    end,
  },

  {
    "b0o/incline.nvim",
    event = "VeryLazy",
    opts = function()
      return {
        window = { margin = { vertical = 0, horizontal = 1 } },
        hide = { cursorline = true },
        render = function(props)
          local name = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(props.buf), ":t")
          if name == "" then
            name = "[No Name]"
          end
          local ft_icon, ft_color = require("mini.icons").get("file", name)
          local modified = vim.bo[props.buf].modified
          return {
            { " " },
            { ft_icon .. " ", group = ft_color },
            { name, gui = modified and "bold,italic" or "bold" },
            { modified and " ●" or "", guifg = icons.palette.yellow },
            { " " },
          }
        end,
      }
    end,
  },

  {
    "folke/snacks.nvim",
    opts = {
      dashboard = {
        preset = {
          -- A superset of LazyVim's own default list (lazy.nvim replaces
          -- non-empty array-valued opts wholesale rather than merging them by
          -- index, so overriding this key loses every entry LazyVim shipped
          -- unless they are repeated here). Every LazyVim default -- f, n, g,
          -- r, c, s, x, l, q -- is kept; "p" (Projects) is the one addition.
          -- Glyphs are byte-identical to LazyVim's own default list (read
          -- from lazyvim/plugins/ui.lua, not retyped) for the eight keys we
          -- share with it; "p" (cod-project, U+EB30) is the one addition,
          -- verified present in the JetBrainsMono Nerd Font cmap.
          keys = {
            { icon = u(0xf002) .. " ", key = "f", desc = "Find File", action = ":lua Snacks.dashboard.pick('files')" },
            { icon = u(0xf15b) .. " ", key = "n", desc = "New File", action = ":ene | startinsert" },
            {
              icon = u(0xf022) .. " ",
              key = "g",
              desc = "Find Text",
              action = ":lua Snacks.dashboard.pick('live_grep')",
            },
            {
              icon = u(0xf0c5) .. " ",
              key = "r",
              desc = "Recent Files",
              action = ":lua Snacks.dashboard.pick('oldfiles')",
            },
            {
              icon = u(0xf423) .. " ",
              key = "c",
              desc = "Config",
              action = ":lua Snacks.dashboard.pick('files', {cwd = vim.fn.stdpath('config')})",
            },
            { icon = u(0xeb30) .. " ", key = "p", desc = "Projects", action = ":lua Snacks.picker.projects()" },
            { icon = u(0xe348) .. " ", key = "s", desc = "Restore Session", section = "session" },
            { icon = u(0xea8c) .. " ", key = "x", desc = "Lazy Extras", action = ":LazyExtras" },
            { icon = u(0xf04b2) .. " ", key = "l", desc = "Lazy", action = ":Lazy" },
            { icon = u(0xf426) .. " ", key = "q", desc = "Quit", action = ":qa" },
          },
        },
      },
      indent = { enabled = true },
      scroll = { enabled = true },
    },
  },

  -- The spinner LSP progress uses, matched to the wezterm activity spinner so
  -- the two never appear to run at different speeds.
  {
    "folke/noice.nvim",
    opts = function(_, opts)
      opts.lsp = opts.lsp or {}
      opts.lsp.progress = vim.tbl_deep_extend("force", opts.lsp.progress or {}, {
        enabled = true,
        format = {
          { "{spinner} ", hl_group = "NoiceLspProgressSpinner" },
          { "{data.progress.title} " },
        },
        throttle = 1000 / 8, -- eight frames a second, as in wezterm
      })
      opts.throttle = 1000 / 8
      return opts
    end,
  },

  -- The IDEA group's icon is U+F06E8 (md-lightbulb_on), the same codepoint
  -- config/keymaps.lua builds its own IDEA label from. The review group's
  -- icon is U+F4AF (oct-code_review) -- fitting for the diffview/trouble
  -- combo bound under it in plugins/review.lua. Both built from codepoints,
  -- not pasted literally: the first draft of this task's brief had them as
  -- literal glyphs, and supplementary-plane glyphs pasted into these files
  -- get flattened to ASCII spaces in transit. Both confirmed present in the
  -- JetBrainsMono Nerd Font cmap.
  {
    "folke/which-key.nvim",
    opts = {
      spec = {
        { "<leader>i", group = u(0xf06e8) .. " IDEA", icon = { icon = u(0xf06e8) .. " ", color = "yellow" } },
        { "<leader>r", group = "review", icon = { icon = u(0xf4af) .. " ", color = "green" } },
      },
    },
  },
}
