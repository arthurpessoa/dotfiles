local stub = {
  target_triple = "x86_64-pc-windows-msvc",
  nerdfonts = setmetatable({}, { __index = function(_, k) return "<" .. k .. ">" end }),
  format = function(items) return items end,
  log_info = function() end,
  log_error = function() end,
}

function stub.__set_triple(triple)
  stub.target_triple = triple
end

-- wezterm.action.Foo is a value and wezterm.action.Foo({...}) is a call, and the
-- key table holds both forms. One metatable serves each: indexing mints a table
-- tagged with the action name, and calling that table tags it with the argument.
stub.action = setmetatable({}, {
  __index = function(_, name)
    return setmetatable({ __action = name }, {
      __call = function(_, arg) return { __action = name, arg = arg } end,
    })
  end,
})

stub.action_callback = function(fn) return { __action = "callback", fn = fn } end

package.preload["wezterm"] = function() return stub end

return stub
