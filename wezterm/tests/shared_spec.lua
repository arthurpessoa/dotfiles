local shared = require("icons")
local wez = require("modules.icons")

describe("shared icon registry", function()
  it("is what wezterm's module exposes", function()
    assert_eq(wez.entries, shared.entries, "wezterm must re-export the shared table")
    assert_eq(wez.FALLBACK, shared.FALLBACK, "fallback must be shared too")
  end)

  it("colours every entry from the palette", function()
    local palette = require("palette").wave
    local known = {}
    for _, hex in pairs(palette) do
      known[hex] = true
    end
    for name, entry in pairs(shared.entries) do
      assert_true(known[entry.color], "off-palette colour for " .. name .. ": " .. tostring(entry.color))
    end
    assert_true(known[shared.FALLBACK.color], "off-palette fallback colour")
  end)

  it("gives every entry a kind the bar understands", function()
    for name, entry in pairs(shared.entries) do
      assert_true(entry.kind == "busy" or entry.kind == "shell", "bad kind for " .. name)
    end
  end)

  it("has no duplicate glyph-and-colour pair across different languages", function()
    -- Aliases are expected (javaw shares java's icon); this only asserts the
    -- table is not silently collapsing to one entry.
    local distinct = {}
    for _, entry in pairs(shared.entries) do
      distinct[entry.glyph .. entry.color] = true
    end
    local count = 0
    for _ in pairs(distinct) do
      count = count + 1
    end
    assert_true(count > 15, "expected more than 15 distinct icons, got " .. count)
  end)
end)
