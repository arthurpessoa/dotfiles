local wezterm = require("wezterm")
local process = require("modules.process")

-- chain() and pick() are the pure half of the module and are exercised through
-- a fake lookup table. cached() is the other thing worth asserting: every call
-- it lets through is a wezterm.procinfo walk on the GUI thread, so what matters
-- is how many of them it does not let through.

local function tree(entries)
  return function(pid) return entries[pid] end
end

describe("process.chain", function()
  it("reads root first and stops below wezterm", function()
    local lookup = tree({
      [4] = { name = "bash", ppid = 3 },
      [3] = { name = "claude", ppid = 2 },
      [2] = { name = "pwsh", ppid = 1 },
      [1] = { name = "wezterm-gui", ppid = 0 },
    })
    local chain = process.chain(4, lookup)
    assert_eq(table.concat(chain, " "), "pwsh claude bash")
  end)

  it("stops rather than spinning on a cycle in the parent chain", function()
    local lookup = tree({
      [2] = { name = "a", ppid = 1 },
      [1] = { name = "b", ppid = 2 },
    })
    assert_eq(#process.chain(2, lookup), 2)
  end)
end)

describe("process.pick", function()
  it("takes the shallowest process that is not a shell", function()
    assert_eq(process.pick({ "pwsh", "claude", "bash" }), "claude")
  end)

  it("falls back to the innermost shell for a pane at a prompt", function()
    assert_eq(process.pick({ "pwsh", "bash" }), "bash")
  end)

  it("answers empty for an empty chain", function()
    assert_eq(process.pick({}), "")
  end)
end)

describe("process.cached", function()
  local calls

  local function counted(name)
    return function()
      calls = calls + 1
      return name
    end
  end

  local function fresh()
    wezterm.__reset()
    process.reset_cache()
    calls = 0
  end

  it("walks once for repeated asks about the same pane", function()
    fresh()
    -- The shape of a single status tick: the tick itself, the agent segment and
    -- the tab bar's two components all ask about the same pane.
    for _ = 1, 4 do
      assert_eq(process.cached(7, counted("claude")), "claude")
    end
    assert_eq(calls, 1)
  end)

  it("walks again once the entry is stale", function()
    fresh()
    process.cached(7, counted("claude"))
    wezterm.__advance(process.CACHE_SECONDS + 0.01)
    process.cached(7, counted("nvim"))
    assert_eq(calls, 2)
    assert_eq(process.cached(7, counted("nvim")), "nvim")
  end)

  it("keeps panes apart", function()
    fresh()
    assert_eq(process.cached(1, counted("claude")), "claude")
    assert_eq(process.cached(2, counted("nvim")), "nvim")
    assert_eq(process.cached(1, counted("wrong")), "claude")
    assert_eq(calls, 2)
  end)

  it("never caches a pane that has no id", function()
    fresh()
    process.cached(nil, counted("claude"))
    process.cached(nil, counted("claude"))
    assert_eq(calls, 2)
  end)
end)
