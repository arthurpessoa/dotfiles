-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
--
-- Add any additional autocmds here
-- with `vim.api.nvim_create_autocmd`
--
-- Or remove existing autocmds by their group name (which is prefixed with `lazyvim_` for the defaults)
-- e.g. vim.api.nvim_del_augroup_by_name("lazyvim_wrap_spell")

-- Publish the current file to WezTerm as an OSC 1337 user var so the tab can
-- show the file name instead of a bare "nvim". WezTerm keeps the var per pane
-- and falls back to the process name when it is empty, so clearing it on exit
-- is what restores the ordinary tab title.
local wezterm_group = vim.api.nvim_create_augroup("WeztermUserVar", { clear = true })

local function publish_file()
  local name = vim.fn.expand("%:t")
  if name ~= "" and vim.bo.modified then
    name = name .. " ●"
  end
  -- vim.base64.encode needs Neovim 0.10 or newer. Nothing else here depends on
  -- it, and WezTerm shows the process name when the var never arrives.
  io.stdout:write(("\027]1337;SetUserVar=%s=%s\007"):format("nvim-file", vim.base64.encode(name)))
end

vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost", "BufModifiedSet" }, {
  group = wezterm_group,
  callback = publish_file,
})

vim.api.nvim_create_autocmd("VimLeavePre", {
  group = wezterm_group,
  callback = function()
    io.stdout:write(("\027]1337;SetUserVar=%s=%s\007"):format("nvim-file", ""))
  end,
})
