local keys = require("modules.keys")

local function find(list, key, mods)
  for _, entry in ipairs(list) do
    if entry.key == key and entry.mods == mods then return entry end
  end
  return nil
end

describe("keys.build", function()
  it("keeps leader pane navigation", function()
    local list = keys.build("CTRL|SHIFT")
    for _, k in ipairs({ "h", "j", "k", "l" }) do
      assert_true(find(list, k, "LEADER") ~= nil, "missing LEADER " .. k)
    end
  end)

  it("uses the primary modifier for tabs and splits", function()
    local list = keys.build("CTRL|SHIFT")
    assert_true(find(list, "t", "CTRL|SHIFT") ~= nil, "missing new tab")
    assert_true(find(list, "v", "CTRL|SHIFT") ~= nil, "missing vertical split")
  end)

  it("swaps to CMD on macos without moving the leader", function()
    local list = keys.build("CMD")
    assert_true(find(list, "t", "CMD") ~= nil, "new tab should use CMD")
    assert_true(find(list, "z", "LEADER") ~= nil, "zoom should stay on LEADER")
  end)

  it("binds the plugin actions", function()
    local list = keys.build("CTRL|SHIFT")
    assert_true(find(list, "s", "LEADER") ~= nil, "missing resurrect save")
    assert_true(find(list, "r", "LEADER") ~= nil, "missing resurrect restore")
    assert_true(find(list, "d", "LEADER") ~= nil, "missing domain picker")
  end)

  -- The split actions are built at press time inside a callback, so the only
  -- way to see which one a key performs is to run the callback.
  local function performed(entry)
    local action
    local window = { perform_action = function(_self, act) action = act end }
    local pane = { get_current_working_dir = function() return "/tmp" end }
    entry.action.fn(window, pane)
    return action.__action
  end

  it("puts the new pane where the key says it goes", function()
    local list = keys.build("CTRL|SHIFT")
    -- WezTerm reads its own names the other way round from vim and tmux:
    -- SplitHorizontal is the one that puts the new pane to the right.
    assert_eq(performed(find(list, "v", "CTRL|SHIFT")), "SplitHorizontal")
    assert_eq(performed(find(list, "h", "CTRL|SHIFT")), "SplitVertical")
  end)

  it("binds smart-splits navigation on plain CTRL", function()
    local list = keys.build("CTRL|SHIFT")
    for _, k in ipairs({ "h", "j", "k", "l" }) do
      assert_true(find(list, k, "CTRL") ~= nil, "missing CTRL " .. k)
    end
  end)
end)

-- The plugin handles cannot be exercised for real here, so apply() is checked
-- against fakes: what matters is which surface it reaches for, since both
-- plugins changed shape after the plan was written.
local function fake_plugins(log)
  return {
    resurrect = {
      state_manager = { save_state = function() end, load_state = function() return {} end },
      workspace_state = { get_workspace_state = function() return {} end,
        restore_workspace = function() end },
      fuzzy_loader = { fuzzy_load = function() end },
    },
    domains = {
      -- The real plugin appends one entry per configured key to config.keys.
      apply_to_config = function(config, opts)
        log.domain_opts = opts
        for name, key in pairs(opts.keys) do
          table.insert(config.keys, { key = key.key, mods = key.mods, action = name })
        end
      end,
    },
  }
end

describe("keys.apply", function()
  local function applied()
    local log = {}
    local config = {}
    keys.apply(config, fake_plugins(log), { mod_primary = "CTRL|SHIFT" })
    return config, log
  end

  it("lets quick_domains bind its own picker on the leader", function()
    local config, log = applied()
    assert_eq(log.domain_opts.keys.attach.key, "d")
    assert_eq(log.domain_opts.keys.attach.mods, "LEADER")
  end)

  it("gives the plugin's splits the same keys as this config's own", function()
    local _config, log = applied()
    -- quick_domains names its splits after WezTerm's actions, so its hsplit is
    -- the one that opens beside -- which is what V does everywhere else here.
    assert_eq(log.domain_opts.keys.hsplit.key, "V")
    assert_eq(log.domain_opts.keys.vsplit.key, "H")
  end)

  it("leaves the plugin no key that collides with an existing binding", function()
    local config, log = applied()
    for name, key in pairs(log.domain_opts.keys) do
      assert_true(key.mods == "LEADER", name .. " should sit behind the leader")
      local seen = 0
      for _, entry in ipairs(config.keys) do
        if entry.key == key.key and entry.mods == key.mods then seen = seen + 1 end
      end
      assert_eq(seen, 1, "quick_domains " .. name .. " should be bound exactly once")
    end
  end)

  it("replaces every placeholder with a real action", function()
    local config = applied()
    for _, entry in ipairs(config.keys) do
      assert_true(entry.action ~= nil, "binding left without an action")
      assert_true(type(entry.action) ~= "table" or entry.action.__action ~= "Nop",
        (entry.key or "?") .. " is still a placeholder")
    end
  end)

  it("keeps the leader on CTRL q", function()
    local config = applied()
    assert_eq(config.leader.key, "q")
    assert_eq(config.leader.mods, "CTRL")
  end)
end)

describe("keys.is_nvim", function()
  it("detects neovim regardless of path or case", function()
    assert_true(keys.is_nvim("C:\\tools\\NVIM.EXE"))
    assert_true(keys.is_nvim("/usr/bin/nvim"))
  end)

  it("rejects shells", function()
    assert_eq(keys.is_nvim("pwsh"), false)
    assert_eq(keys.is_nvim(nil), false)
  end)
end)
