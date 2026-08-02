-- Reading a change someone else wrote -- including the ones a model wrote.
-- gitsigns and trouble are LazyVim's; diffview is the one new plugin, because
-- nothing already installed shows a commit range or a file's history side by
-- side.
--
-- Keymaps deliberately deviate from the original brief:
--   <leader>gD -> <leader>gW  (gD is already "Git Diff (origin)", a Snacks
--                              picker key from LazyVim's base config)
--   <leader>gL -> <leader>gR  (gL is already "Git Log (cwd)", also from
--                              LazyVim's base keymaps.lua)
-- <leader>gH and <leader>gQ were free and are used as proposed. Checked
-- against LazyVim's config/keymaps.lua, its gitsigns/trouble specs, and the
-- enabled extras (util.octo, util.gh, lang.git) via a live keymap dump, not
-- just source reading -- LazyVim's own safe_keymap_set skips keys already
-- claimed by a plugin's `keys` table, so grepping the source alone under-
-- reports what's actually bound.
--
-- No gitsigns spec here: LazyVim's own gitsigns spec (in
-- lazyvim/plugins/editor.lua) already binds ]h [h <leader>ghs <leader>ghr
-- <leader>ghu <leader>ghp <leader>ghb <leader>ghB -- everything this task
-- asked for -- plus ]H [H <leader>ghS <leader>ghR <leader>ghd <leader>ghD ih,
-- and its ]h/[h fall through to native ]c/[c when vim.wo.diff is set (true
-- inside a diffview pane). opts tables merge key by key: opts.on_attach is a
-- single function value, so redeclaring it here would REPLACE LazyVim's,
-- silently dropping all of the above. Nothing to add.
return {
  {
    "sindrets/diffview.nvim",
    dependencies = { "nvim-lua/plenary.nvim" },
    cmd = { "DiffviewOpen", "DiffviewFileHistory", "DiffviewClose" },
    keys = {
      { "<leader>gW", "<cmd>DiffviewOpen<cr>", desc = "Diffview: Working Tree" },
      { "<leader>gH", "<cmd>DiffviewFileHistory %<cr>", desc = "Diffview: File History" },
      { "<leader>gR", "<cmd>DiffviewFileHistory<cr>", desc = "Diffview: Branch History" },
      { "<leader>gQ", "<cmd>DiffviewClose<cr>", desc = "Diffview: Close" },
    },
    opts = {
      enhanced_diff_hl = true,
      view = {
        default = { layout = "diff2_horizontal" },
        merge_tool = { layout = "diff3_mixed" },
      },
    },
  },

  {
    "folke/trouble.nvim",
    keys = {
      {
        "<leader>rr",
        function()
          -- One key for "show me what changed and what it broke": the diff
          -- on one side, and the diagnostics for the changed files on the
          -- other. `Trouble ... filter.buf=0` would filter to whatever
          -- buffer is current *after* DiffviewOpen runs -- the diffview file
          -- panel, not a real source buffer -- so it would show nothing
          -- useful. Instead, resolve the changed files from git directly and
          -- filter diagnostics against that set.
          local root = LazyVim.root.git()
          local files = vim.fn.systemlist({ "git", "-C", root, "diff", "--name-only", "HEAD" })
          if vim.v.shell_error ~= 0 or #files == 0 then
            vim.notify("Review: no changed files", vim.log.levels.INFO)
            return
          end

          local win32 = vim.fn.has("win32") == 1
          local changed = {}
          for _, f in ipairs(files) do
            local abs = vim.fs.normalize(root .. "/" .. f)
            changed[win32 and abs:lower() or abs] = true
          end

          vim.cmd("DiffviewOpen")

          require("trouble").open({
            mode = "diagnostics",
            filter = function(items)
              return vim.tbl_filter(function(item)
                local fname = item.filename and vim.fs.normalize(item.filename)
                if not fname then
                  return false
                end
                return changed[win32 and fname:lower() or fname] == true
              end, items)
            end,
          })
        end,
        desc = "Review: Diff + Diagnostics",
      },
    },
  },
}
