local M = { groups = {}, current = nil }

function M.describe(name, fn)
  M.current = { name = name, cases = {} }
  table.insert(M.groups, M.current)
  fn()
  M.current = nil
end

function M.it(name, fn)
  table.insert(M.current.cases, { name = name, fn = fn })
end

local function fail(msg, extra)
  error(msg .. (extra and ("\n      " .. extra) or ""), 2)
end

function M.assert_eq(actual, expected, msg)
  if actual ~= expected then
    fail(msg or "values differ",
      string.format("expected %s, got %s", tostring(expected), tostring(actual)))
  end
end

function M.assert_nil(value, msg)
  if value ~= nil then fail(msg or "expected nil", tostring(value)) end
end

function M.assert_true(value, msg)
  if not value then fail(msg or "expected truthy", tostring(value)) end
end

function M.run()
  local failures, total = 0, 0
  for _, group in ipairs(M.groups) do
    print(group.name)
    for _, case in ipairs(group.cases) do
      total = total + 1
      local ok, err = pcall(case.fn)
      if ok then
        print("  ok   " .. case.name)
      else
        failures = failures + 1
        print("  FAIL " .. case.name)
        print("       " .. tostring(err))
      end
    end
  end
  print(string.format("\n%d passed, %d failed, %d total", total - failures, failures, total))
  return failures
end

return M
