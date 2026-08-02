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
