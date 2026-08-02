local icons = require("icons")
local palette = require("palette").wave

describe("shared registry from neovim", function()
  it("loads through the shared path", function()
    assert_true(icons.entries ~= nil, "entries missing")
    assert_true(icons.FALLBACK ~= nil, "fallback missing")
  end)

  it("carries the language entries neovim colours buffers with", function()
    for _, name in ipairs({ "java", "kotlin", "rust", "python", "typescript", "javascript", "lua" }) do
      assert_true(icons.entries[name] ~= nil, "missing language entry: " .. name)
    end
  end)

  it("keeps java on carpYellow so the wezterm tab and the statusline match", function()
    assert_eq(icons.entries.java.color, palette.yellow)
  end)

  it("encodes glyphs as multi-byte utf-8, never as a literal char", function()
    for name, entry in pairs(icons.entries) do
      assert_true(#entry.glyph >= 3, "suspiciously short glyph for " .. name)
    end
  end)
end)
