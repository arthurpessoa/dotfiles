local M = {}

function M.apply(config, plugins, platform)
  plugins.kanagawa.apply_to_config(config)

  config.font = require("wezterm").font("JetBrainsMono Nerd Font")
  config.font_size = 12.5

  config.window_background_opacity = 0.97
  config.window_padding = { left = 8, right = 8, top = 8, bottom = 8 }
  config.window_decorations = "RESIZE"

  if platform.backdrop then
    config[platform.backdrop.key] = platform.backdrop.value
  end

  config.inactive_pane_hsb = { saturation = 0.85, brightness = 0.75 }
  config.default_cursor_style = "BlinkingBar"
  config.cursor_blink_ease_in = "EaseInOut"
  config.cursor_blink_ease_out = "EaseInOut"
  config.cursor_blink_rate = 600

  config.scrollback_lines = 100000
  config.audible_bell = "Disabled"
  config.default_prog = platform.default_prog

  config.window_frame = {
    font = require("wezterm").font("JetBrainsMono Nerd Font", { weight = "Bold" }),
    font_size = 11.5,
  }

  -- Placement is WezTerm's, not tabline's, and tabline sets use_fancy_tab_bar
  -- itself, so this must run after tabline.apply_to_config.
  config.enable_tab_bar = true
  config.use_fancy_tab_bar = false
  config.hide_tab_bar_if_only_one_tab = false
  config.tab_bar_at_bottom = true

  -- Everything the bar does runs on this clock, on the GUI thread, so the tick
  -- rate is an input-latency setting as much as a refresh rate. 120ms was
  -- chosen to match the spinner's eight frames a second; at 250 the spinner
  -- takes every other frame, which still reads as motion, and the window keeps
  -- twice as much of the thread for drawing and keystrokes.
  config.status_update_interval = 250
end

return M
