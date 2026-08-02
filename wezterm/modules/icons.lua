-- The registry itself lives in shared/, because Neovim needs the same glyphs
-- and the same colours and two copies is how they drift. This module stays so
-- that bar.lua and the existing specs keep requiring "modules.icons".
return require("icons")
