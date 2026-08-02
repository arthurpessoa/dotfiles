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
-- written when the state actually changes.
local busy = false
vim.api.nvim_create_autocmd("LspProgress", {
  group = wezterm_group,
  callback = function(event)
    local now = event.data and event.data.params and event.data.params.value and event.data.params.value.kind ~= "end"
    if now ~= busy then
      busy = now
      publish("nvim-busy", busy and "1" or "")
    end
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
