local M = {}

-- Encode a Unicode codepoint as literal UTF-8 bytes. Nerd Font glyphs live
-- in the Private Use Area (U+E000-U+F8FF) and in the supplementary planes
-- (U+F0000+); both get mangled by editors/clipboards that assume text is
-- "safe" to normalise, so codepoints are encoded at load time instead of
-- being pasted as literal characters. Lua 5.1 safe: no utf8.*, no \u{}.
function M.u(cp)
  if cp < 0x80 then
    return string.char(cp)
  elseif cp < 0x800 then
    return string.char(0xC0 + math.floor(cp / 64), 0x80 + cp % 64)
  elseif cp < 0x10000 then
    return string.char(0xE0 + math.floor(cp / 4096), 0x80 + math.floor(cp / 64) % 64, 0x80 + cp % 64)
  end
  return string.char(
    0xF0 + math.floor(cp / 262144),
    0x80 + math.floor(cp / 4096) % 64,
    0x80 + math.floor(cp / 64) % 64,
    0x80 + cp % 64
  )
end

return M
