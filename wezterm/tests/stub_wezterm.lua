local stub = {
  target_triple = "x86_64-pc-windows-msvc",
  nerdfonts = setmetatable({}, { __index = function(_, k) return "<" .. k .. ">" end }),
  format = function(items) return items end,
  log_info = function() end,
  log_error = function() end,
}

package.preload["wezterm"] = function() return stub end

return stub
