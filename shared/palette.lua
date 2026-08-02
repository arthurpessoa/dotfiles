local M = {}

-- Kanagawa "wave", the same theme wezterm/modules/theme.lua applies to the
-- terminal. Roles rather than colour names, so a consumer never has to know
-- which Kanagawa key it wants. The comment on each line is the upstream key,
-- which is what tests/palette_spec compares against.
M.wave = {
  bg         = "#1F1F28", -- sumiInk3
  bg_dim     = "#16161D", -- sumiInk0
  fg         = "#DCD7BA", -- fujiWhite

  yellow     = "#E6C384", -- carpYellow
  red        = "#E46876", -- waveRed
  blue       = "#7E9CD8", -- crystalBlue
  green      = "#98BB6C", -- springGreen
  aqua       = "#7AA89F", -- waveAqua2
  white      = "#C8C093", -- oldWhite
  gray       = "#727169", -- fujiGray
  violet     = "#957FB8", -- oniViolet
  pink       = "#D27E99", -- sakuraPink
  orange     = "#FFA066", -- surimiOrange

  error      = "#E82424", -- samuraiRed
  warn       = "#FF9E3B", -- roninYellow
  info       = "#658594", -- dragonBlue
  hint       = "#6A9589", -- waveAqua1

  git_add    = "#76946A", -- autumnGreen
  git_change = "#DCA561", -- autumnYellow
  git_del    = "#C34043", -- autumnRed
}

return M
