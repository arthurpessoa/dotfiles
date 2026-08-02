-- Autocmds are automatically loaded on the VeryLazy event.
-- Defaults: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua

-- Publish editor state to WezTerm as OSC 1337 user vars so the tab can say
-- something more useful than "nvim". WezTerm keeps a var per pane and falls
-- back to the process name when one is empty, so clearing them on exit is what
-- restores the ordinary tab title.
local wezterm_group = vim.api.nvim_create_augroup("WeztermUserVar", { clear = true })

-- vim.base64.encode needs Neovim 0.10 or newer. Nothing else here depends on
-- it, and WezTerm shows the process name when a var never arrives.
local function publish(name, value)
  io.stdout:write(("\027]1337;SetUserVar=%s=%s\007"):format(name, vim.base64.encode(value)))
end

local function publish_file()
  local name = vim.fn.expand("%:t")
  if name ~= "" and vim.bo.modified then
    name = name .. " ●"
  end
  publish("nvim-file", name)
end

-- "E:2 W:5", or empty when the buffer is clean. Counts, not icons: the bar
-- picks its own glyphs, and a glyph crossing the OSC channel would have to
-- survive base64 and the terminal's own decoding.
local function publish_diagnostics()
  local errors = #vim.diagnostic.get(0, { severity = vim.diagnostic.severity.ERROR })
  local warnings = #vim.diagnostic.get(0, { severity = vim.diagnostic.severity.WARN })
  if errors == 0 and warnings == 0 then
    publish("nvim-diag", "")
    return
  end
  local parts = {}
  if errors > 0 then
    table.insert(parts, "E:" .. errors)
  end
  if warnings > 0 then
    table.insert(parts, "W:" .. warnings)
  end
  publish("nvim-diag", table.concat(parts, " "))
end

vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost", "BufModifiedSet" }, {
  group = wezterm_group,
  callback = publish_file,
})

vim.api.nvim_create_autocmd({ "DiagnosticChanged", "BufEnter" }, {
  group = wezterm_group,
  callback = publish_diagnostics,
})

-- LspProgress fires many times a second during indexing, so the var is only
-- written when the published state actually changes. Progress is tracked as
-- a set of open tokens rather than one flag: rust-analyzer alone runs
-- concurrent cachePriming and indexing tokens, and any buffer with two
-- attached servers means one server's "end" would otherwise clear busy while
-- the other is still working. Keys are client_id .. token because a token is
-- only unique within its own client.
local active_tokens = {}
local busy = false

local function set_busy(now)
  if now ~= busy then
    busy = now
    publish("nvim-busy", busy and "1" or "")
  end
end

vim.api.nvim_create_autocmd("LspProgress", {
  group = wezterm_group,
  callback = function(event)
    local data = event.data
    local params = data and data.params
    if not (params and params.token ~= nil and data.client_id) then
      return
    end
    local key = data.client_id .. ":" .. tostring(params.token)
    local kind = params.value and params.value.kind
    if kind == "end" then
      active_tokens[key] = nil
    else
      active_tokens[key] = true
    end
    set_busy(next(active_tokens) ~= nil)
  end,
})

-- A client that detaches or crashes mid-progress never sends "end" for its
-- open tokens, which would otherwise strand them and pin the tab busy
-- forever. LspProgress fires once per buffer a client was attached to
-- though, not only on a full stop, and the client can still be attached
-- elsewhere with a legitimate token in flight -- so the sweep is deferred
-- until the client is actually gone (vim.lsp.get_client_by_id returns nil),
-- rather than clearing its tokens on every single-buffer detach.
vim.api.nvim_create_autocmd("LspDetach", {
  group = wezterm_group,
  callback = function(event)
    local client_id = event.data and event.data.client_id
    if not client_id then
      return
    end
    vim.schedule(function()
      if vim.lsp.get_client_by_id(client_id) then
        return
      end
      local prefix = client_id .. ":"
      local changed = false
      for key in pairs(active_tokens) do
        if key:sub(1, #prefix) == prefix then
          active_tokens[key] = nil
          changed = true
        end
      end
      if changed then
        set_busy(next(active_tokens) ~= nil)
      end
    end)
  end,
})

vim.api.nvim_create_autocmd("VimLeavePre", {
  group = wezterm_group,
  callback = function()
    publish("nvim-file", "")
    publish("nvim-diag", "")
    publish("nvim-busy", "")
  end,
})
