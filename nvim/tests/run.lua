-- Run from the repository root: nvim -l nvim/tests/run.lua
--
-- The runner is Neovim itself, so specs may use vim.fs, vim.uv and the rest
-- of the standard library. No plugin is loaded: `nvim -l` skips init.lua, so
-- these specs cover the modules under nvim/lua/util, not plugin behaviour.
package.path = table.concat({
  "nvim/lua/?.lua",
  "nvim/tests/?.lua",
  "shared/?.lua", -- harness.lua lives here, shared with the wezterm suite
  package.path,
}, ";")

local harness = require("harness")
_G.describe = harness.describe
_G.it = harness.it
_G.assert_eq = harness.assert_eq
_G.assert_nil = harness.assert_nil
_G.assert_true = harness.assert_true

local specs = {
  "icons_spec",
  "jdk_spec",
  "dap_persist_spec",
}

for _, name in ipairs(specs) do
  require(name)
end

os.exit(harness.run() == 0 and 0 or 1)
