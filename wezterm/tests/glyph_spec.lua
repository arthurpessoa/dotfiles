local glyph = require("modules.glyph")

local function bytes(s)
  local out = {}
  for i = 1, #s do
    table.insert(out, string.format("%02x", s:byte(i)))
  end
  return table.concat(out, " ")
end

describe("glyph.u", function()
  it("encodes a 1-byte ASCII codepoint", function()
    local s = glyph.u(0x41) -- 'A'
    assert_eq(#s, 1)
    assert_eq(bytes(s), "41")
  end)

  it("encodes a 2-byte codepoint", function()
    local s = glyph.u(0xA9) -- copyright sign, U+00A9
    assert_eq(#s, 2)
    assert_eq(bytes(s), "c2 a9")
  end)

  it("encodes a 3-byte codepoint", function()
    local s = glyph.u(0xE702) -- nf-dev-git, Private Use Area
    assert_eq(#s, 3)
    assert_eq(bytes(s), "ee 9c 82")
  end)

  it("encodes a 4-byte codepoint", function()
    local s = glyph.u(0xF018D) -- supplementary plane glyph
    assert_eq(#s, 4)
    assert_eq(bytes(s), "f3 b0 86 8d")
  end)
end)
