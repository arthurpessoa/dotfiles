local persist = require("util.dap_persist")

describe("dap_persist.encode", function()
  local function name_of(bufnr)
    return ({ [1] = "/proj/A.java", [2] = "/proj/B.rs" })[bufnr]
  end

  it("keys breakpoints by file name", function()
    local out = persist.encode({ [1] = { { line = 10 } } }, name_of)
    assert_true(out["/proj/A.java"] ~= nil)
    assert_eq(out["/proj/A.java"][1].line, 10)
  end)

  it("keeps the condition, log message and hit condition", function()
    local out = persist.encode({
      [1] = { { line = 4, condition = "i > 3", logMessage = "i={i}", hitCondition = "5" } },
    }, name_of)
    local bp = out["/proj/A.java"][1]
    assert_eq(bp.condition, "i > 3")
    assert_eq(bp.logMessage, "i={i}")
    assert_eq(bp.hitCondition, "5")
  end)

  it("drops buffers with no name, which are scratch and cannot be restored", function()
    local out = persist.encode({ [9] = { { line = 1 } } }, function()
      return ""
    end)
    assert_nil(next(out))
  end)

  it("drops files whose breakpoint list is empty", function()
    local out = persist.encode({ [1] = {} }, name_of)
    assert_nil(next(out))
  end)
end)

describe("dap_persist.decode", function()
  it("flattens the file map back into a list", function()
    local list = persist.decode({
      ["/proj/A.java"] = { { line = 10, condition = "x" } },
      ["/proj/B.rs"] = { { line = 2 } },
    })
    assert_eq(#list, 2)
    local by_file = {}
    for _, entry in ipairs(list) do
      by_file[entry.file] = entry
    end
    assert_eq(by_file["/proj/A.java"].line, 10)
    assert_eq(by_file["/proj/A.java"].opts.condition, "x")
    assert_eq(by_file["/proj/B.rs"].line, 2)
  end)

  it("survives a round trip", function()
    local original = { ["/proj/A.java"] = { { line = 7, condition = "n == 0" } } }
    local list = persist.decode(original)
    local rebuilt = {}
    for _, entry in ipairs(list) do
      rebuilt[entry.file] = rebuilt[entry.file] or {}
      table.insert(rebuilt[entry.file], vim.tbl_extend("force", { line = entry.line }, entry.opts))
    end
    assert_eq(rebuilt["/proj/A.java"][1].line, 7)
    assert_eq(rebuilt["/proj/A.java"][1].condition, "n == 0")
  end)

  it("returns an empty list for empty data", function()
    assert_eq(#persist.decode({}), 0)
    assert_eq(#persist.decode(nil), 0)
  end)
end)

-- These exercise M.setup() itself -- the wiring -- not the pure encode/
-- decode/state_path functions above, which could not have caught C1: they
-- never touch an autocmd or the VeryLazy timing bug that made restore dead
-- on every real session. `nvim -l` never loads plugins/dap.lua (no init=,
-- no `User LazyLoad`), so "dap" and "dap.breakpoints" are stubbed via
-- package.preload -- real modules would not be requirable in this runner
-- regardless of the bug under test.
describe("dap_persist.setup wiring (C1)", function()
  -- Every test below calls M.setup(), which registers REAL autocmds in the
  -- DapPersist augroup. Left unmanaged between tests, an autocmd one test
  -- registers can survive to fire during a LATER test -- e.g. a `cd` in a
  -- following test firing a stale DirChanged listener whose `last_root`
  -- closure still points at whatever cwd was active when THIS test's
  -- setup() ran, which, absent an explicit cd, is the real invocation
  -- directory. That is not hypothetical: it happened here, on the first
  -- version of this spec, and silently overwrote this repository's own real
  -- dap-breakpoints state file with a later test's fixture data while
  -- `nvim -l nvim/tests/run.lua` still reported all green.
  --
  -- isolated() gives every test here two independent guarantees, so a
  -- failure in either alone still cannot touch a real file:
  --   1. vim.fn.stdpath("state") is redirected to a fresh temp directory
  --      for the duration of the test, so even a stale autocmd from a
  --      PRIOR test firing here can only write inside that temp directory.
  --   2. the DapPersist augroup is cleared when the test ends -- pass or
  --      fail -- so no autocmd THIS test's setup() registered survives to
  --      fire during a later one.
  local function isolated(fn)
    local orig_stdpath = vim.fn.stdpath
    local tmp_state = vim.fn.tempname()
    vim.fn.mkdir(tmp_state, "p")
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.fn.stdpath = function(what)
      if what == "state" then
        return tmp_state
      end
      return orig_stdpath(what)
    end

    local ok, err = pcall(fn, tmp_state)

    -- Flush anything the test scheduled (e.g. setup()'s own vim.schedule'd
    -- load()) while stdpath is still redirected, so a late callback can't
    -- land after the real path is restored below.
    vim.wait(200, function()
      return false
    end, 10)

    vim.fn.stdpath = orig_stdpath
    vim.api.nvim_create_augroup("DapPersist", { clear = true })
    vim.fn.delete(tmp_state, "rf")

    if not ok then
      error(err, 0)
    end
  end

  local function install_dap_stub(by_buf, calls)
    package.preload["dap"] = function()
      return {
        clear_breakpoints = function()
          calls.cleared = (calls.cleared or 0) + 1
        end,
      }
    end
    package.preload["dap.breakpoints"] = function()
      return {
        get = function()
          return by_buf
        end,
        set = function(opts, bufnr, lnum)
          table.insert(calls.set, { opts = opts, bufnr = bufnr, lnum = lnum })
        end,
      }
    end
  end

  local function remove_dap_stub()
    package.loaded["dap"] = nil
    package.loaded["dap.breakpoints"] = nil
    package.preload["dap"] = nil
    package.preload["dap.breakpoints"] = nil
  end

  it("calls load() itself instead of waiting for VeryLazy, which has already fired", function()
    isolated(function()
      -- This is the actual C1 regression: setup() used to register its
      -- restore on `User VeryLazy`, an event that -- by the time setup()
      -- can possibly run -- has already fired exactly once and will never
      -- fire again. Nothing in this test ever fires a VeryLazy autocmd; if
      -- setup() regresses to depending on one, `called` stays false and
      -- this times out.
      local p = require("util.dap_persist")
      local orig_load = p.load
      local called = false
      p.load = function(...)
        called = true
      end

      p.setup()
      vim.wait(500, function()
        return called
      end, 10)

      p.load = orig_load
      assert_true(called, "setup() must reach load() on its own; nothing else will fire VeryLazy in time")
    end)
  end)

  it("registers DirChanged and VimLeavePre, and no dead VeryLazy listener", function()
    isolated(function()
      local p = require("util.dap_persist")
      p.setup()

      local autocmds = vim.api.nvim_get_autocmds({ group = "DapPersist" })
      local events = {}
      for _, a in ipairs(autocmds) do
        events[a.event] = (events[a.event] or 0) + 1
        if a.event == "User" then
          assert_true(a.pattern ~= "VeryLazy", "a User/VeryLazy autocmd is exactly the dead wiring C1 removes")
        end
      end
      assert_true(events["VimLeavePre"] ~= nil, "VimLeavePre autocmd missing")
      assert_true(events["DirChanged"] ~= nil, "DirChanged autocmd missing -- restore on project switch is absent")
    end)
  end)

  it("a save -> DirChanged -> load cycle moves breakpoints into the right project's file, not the new cwd's", function()
    isolated(function(tmp_state)
      local base = (vim.fn.stdpath("run") or vim.fn.stdpath("cache")):gsub("\\", "/")
      local root_a = base .. "/dap-persist-spec-root-a"
      local root_b = base .. "/dap-persist-spec-root-b"
      vim.fn.mkdir(root_a, "p")
      vim.fn.mkdir(root_b, "p")
      -- vim.fn.stdpath("state") is redirected to tmp_state for the duration
      -- of this test (see isolated()), so these paths -- and everything
      -- M.save()/M.load() touch below -- live entirely under tmp_state.
      local file_a = require("util.dap_persist").state_path(root_a, tmp_state)
      local file_b = require("util.dap_persist").state_path(root_b, tmp_state)

      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_name(buf, root_a .. "/Main.java")
      local by_buf = { [buf] = { { line = 42, condition = "x > 0" } } }
      local calls = { set = {} }
      install_dap_stub(by_buf, calls)

      local orig_cwd = vim.uv.cwd()
      vim.cmd("cd " .. vim.fn.fnameescape(root_a))

      local p = require("util.dap_persist")
      p.setup()
      -- Let the initial vim.schedule'd load() run (root_a has no file yet,
      -- so this is a no-op) before driving a DirChanged.
      vim.wait(200, function()
        return true
      end, 10)

      -- Simulate switching project mid-session, as the dashboard's Projects
      -- key does. This must (a) persist root_a's still-in-memory breakpoint
      -- into root_a's OWN file, not root_b's, and (b) clear the in-memory
      -- set so it cannot bleed into root_b.
      vim.cmd("cd " .. vim.fn.fnameescape(root_b))
      vim.wait(200, function()
        return vim.uv.fs_stat(file_a) ~= nil
      end, 10)

      vim.cmd("cd " .. vim.fn.fnameescape(orig_cwd))
      remove_dap_stub()

      assert_true(vim.uv.fs_stat(file_a) ~= nil, "root_a's breakpoint was never saved to root_a's file")
      local saved = vim.json.decode(table.concat(vim.fn.readfile(file_a), "\n"))
      assert_true(saved[root_a .. "/Main.java"] ~= nil, "root_a's file does not contain root_a's breakpoint")
      assert_eq(saved[root_a .. "/Main.java"][1].line, 42)
      assert_true(calls.cleared ~= nil and calls.cleared > 0, "DirChanged must clear in-memory breakpoints")

      os.remove(file_b)
      vim.fn.delete(root_a, "d")
      vim.fn.delete(root_b, "d")
    end)
  end)
end)

describe("dap_persist.state_path", function()
  it("puts one file per project under the state dir", function()
    local a = persist.state_path("/home/u/projects/alpha", "/state")
    local b = persist.state_path("/home/u/projects/beta", "/state")
    assert_true(a ~= b, "two projects must not share a file")
    assert_true(a:match("^/state/dap%-breakpoints/") ~= nil, "unexpected path: " .. a)
    assert_true(a:match("%.json$") ~= nil, "expected a .json file")
  end)

  it("is stable for the same project", function()
    assert_eq(persist.state_path("/home/u/alpha", "/state"), persist.state_path("/home/u/alpha", "/state"))
  end)

  it("does not leak path separators into the file name", function()
    local p = persist.state_path("C:/Users/u/projects/alpha", "/state")
    local file = p:match("([^/]+)$")
    assert_nil(file:match("[/\\:]"), "separator survived into " .. file)
  end)
end)
