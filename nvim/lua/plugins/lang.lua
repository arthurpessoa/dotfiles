-- Everything about these languages that LazyVim's extras get right is left to
-- the extras. What is here is the two places this machine disagrees.
local jdk = require("util.jdk")

return {
  -- jdtls will not start on a JDK older than 21, and `jdtls` on this machine
  -- resolves java from PATH, which is 17. Handing it an explicit java and the
  -- full runtime list is what makes Java work at all.
  {
    "mfussenegger/nvim-jdtls",
    opts = function(_, opts)
      local java = jdk.jdtls_java()
      if java then
        -- cmd[1] is mason's jdtls launcher (a Python script), not java itself
        -- -- it parses --jvm-arg=... and its own -configuration/-data, then
        -- picks a java of its own (PATH, or $JAVA_HOME if that resolves).
        -- Overwriting cmd[1] with a raw java binary breaks that parsing, since
        -- java does not understand --jvm-arg=. --java-executable is the flag
        -- the launcher exposes for pointing it at a specific java instead.
        opts.cmd = opts.cmd or { vim.fn.exepath("jdtls") }
        table.insert(opts.cmd, "--java-executable=" .. java)
      else
        vim.notify(
          "No JDK " .. jdk.JDTLS_MIN_MAJOR .. "+ found; jdtls will use PATH java and may fail to start",
          vim.log.levels.WARN
        )
      end

      opts.jdtls = vim.tbl_deep_extend("force", opts.jdtls or {}, {
        settings = {
          java = {
            configuration = { runtimes = jdk.runtimes() },
            format = { enabled = true },
          },
        },
      })
      return opts
    end,
  },

  -- rustaceanvim comes from lang.rust. Only the check command differs from its
  -- default, and the modern schema is check.command, not checkOnSave.command.
  {
    "mrcjkb/rustaceanvim",
    opts = {
      server = {
        default_settings = {
          ["rust-analyzer"] = {
            cargo = { allFeatures = true },
            check = { command = "clippy" },
          },
        },
      },
    },
  },

  -- lang.kotlin defines a `kotlin` dap adapter but its mason list has only
  -- ktlint, so the adapter has nothing to run.
  {
    "mason-org/mason.nvim",
    opts = { ensure_installed = { "kotlin-debug-adapter" } },
  },

  {
    "mfussenegger/nvim-jdtls",
    optional = true,
    init = function()
      vim.api.nvim_create_user_command("JdkList", function()
        local jdk = require("util.jdk")
        local lines = { "Discovered JDKs, newest first:", "" }
        for _, install in ipairs(jdk.discover()) do
          table.insert(lines, string.format("  %-8s %s", install.version, install.path))
        end
        table.insert(lines, "")
        table.insert(lines, "jdtls runs on: " .. (jdk.jdtls_java() or "PATH java (none new enough found)"))
        vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
      end, { desc = "List the JDKs jdk.lua discovered" })
    end,
  },
}
