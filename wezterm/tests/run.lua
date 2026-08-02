package.path = "wezterm/?.lua;wezterm/tests/?.lua;shared/?.lua;" .. package.path
require("stub_wezterm")

local harness = require("harness")
_G.describe = harness.describe
_G.it = harness.it
_G.assert_eq = harness.assert_eq
_G.assert_nil = harness.assert_nil
_G.assert_true = harness.assert_true

local specs = {
  "smoke_spec",
  "icons_spec",
  "activity_spec",
  "glyph_spec",
  "git_spec",
  "agent_spec",
  "platform_spec",
  "process_spec",
  "keys_spec",
  "plugins_spec",
  "bar_spec",
  "shared_spec",
  "nvim_state_spec",
}

for _, name in ipairs(specs) do
  require(name)
end

os.exit(harness.run() == 0 and 0 or 1)
