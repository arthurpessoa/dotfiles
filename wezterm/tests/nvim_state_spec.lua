local bar = require("modules.bar")

describe("bar.parse_diag", function()
  it("reads an error and warning count", function()
    local d = bar.parse_diag("E:2 W:5")
    assert_eq(d.errors, 2)
    assert_eq(d.warnings, 5)
  end)

  it("reads errors alone", function()
    local d = bar.parse_diag("E:3")
    assert_eq(d.errors, 3)
    assert_eq(d.warnings, 0)
  end)

  it("returns nil for an empty value, which is how neovim says 'clean'", function()
    assert_nil(bar.parse_diag(""))
    assert_nil(bar.parse_diag(nil))
  end)

  it("returns nil for anything it does not recognise, rather than guessing", function()
    assert_nil(bar.parse_diag("garbage"))
  end)
end)
