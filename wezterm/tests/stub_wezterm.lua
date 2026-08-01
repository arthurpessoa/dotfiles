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

-- Plugins are handed back per url from a table the spec fills in, so a spec can
-- give one of them an init that misbehaves the way the real plugin does.
stub.__plugin_factories = {}
stub.__spawned = {}

stub.plugin = {
  require = function(url)
    local factory = stub.__plugin_factories[url]
    return factory and factory() or { __url = url }
  end,
}

stub.background_child_process = function(args)
  table.insert(stub.__spawned, args)
end

stub.__handlers = {}
stub.on = function(name, fn)
  stub.__handlers[name] = fn
end

stub.time = {
  now = function()
    return { format = function() return "1700000000.000" end }
  end,
}

-- nil means every directory reads; a table means only its keys do.
stub.__dirs = nil
stub.read_dir = function(path)
  if stub.__dirs and not stub.__dirs[path] then
    error("no such directory: " .. path)
  end
  return {}
end

function stub.__reset()
  stub.__plugin_factories = {}
  stub.__spawned = {}
  stub.__dirs = nil
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
