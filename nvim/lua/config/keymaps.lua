-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set:
-- https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

-- lua/config/keymaps.lua

-- lua/config/keymaps.lua

local map = vim.keymap.set

local IDEA = "󰄛 IDEA"

----------------------------------------------------------
-- Helpers
----------------------------------------------------------

local function snacks_available()
  return Snacks ~= nil
end

----------------------------------------------------------
-- IDEA group
----------------------------------------------------------

map("n", "<leader>i", "<nop>", {
  desc = IDEA .. " Actions",
})

----------------------------------------------------------
-- Navigation
----------------------------------------------------------

-- Ctrl+B
map("n", "<leader>ib", function()
  vim.lsp.buf.definition()
end, {
  desc = IDEA .. ": Go to Definition",
})

-- Ctrl+Alt+B
map("n", "<leader>ig", function()
  vim.lsp.buf.implementation()
end, {
  desc = IDEA .. ": Go to Implementation",
})

map("n", "<leader>it", function()
  vim.lsp.buf.type_definition()
end, {
  desc = IDEA .. ": Type Definition",
})

----------------------------------------------------------
-- Find usages
----------------------------------------------------------

-- Alt+F7

map("n", "<leader>iu", function()
  Snacks.picker.lsp_references()
end, {
  desc = IDEA .. ": Find Usages",
})

----------------------------------------------------------
-- Refactor
----------------------------------------------------------

-- Shift+F6

map("n", "<leader>ir", function()
  vim.lsp.buf.rename()
end, {
  desc = IDEA .. ": Rename Symbol",
})

-- Alt+Enter

map("n", "<leader>ia", function()
  vim.lsp.buf.code_action()
end, {
  desc = IDEA .. ": Code Action",
})

----------------------------------------------------------
-- Formatting
----------------------------------------------------------

-- Ctrl+Alt+L

map("n", "<leader>il", function()
  vim.lsp.buf.format({
    async = true,
  })
end, {
  desc = IDEA .. ": Reformat Code",
})

----------------------------------------------------------
-- Search Everywhere
----------------------------------------------------------

-- Shift+Shift

map("n", "<leader>is", function()
  Snacks.picker.smart()
end, {
  desc = IDEA .. ": Search Everywhere",
})

----------------------------------------------------------
-- Find Files
----------------------------------------------------------

map("n", "<leader>if", function()
  Snacks.picker.files()
end, {
  desc = IDEA .. ": Find Files",
})

----------------------------------------------------------
-- Find in Files
----------------------------------------------------------

-- Ctrl+Shift+F

map("n", "<leader>igrep", function()
  Snacks.picker.grep()
end, {
  desc = IDEA .. ": Find in Files",
})

----------------------------------------------------------
-- Symbols
----------------------------------------------------------

map("n", "<leader>io", function()
  Snacks.picker.lsp_symbols()
end, {
  desc = IDEA .. ": Search Symbols",
})

----------------------------------------------------------
-- Documentation
----------------------------------------------------------

-- Ctrl+Q

map("n", "<leader>ih", function()
  vim.lsp.buf.hover()
end, {
  desc = IDEA .. ": Quick Documentation",
})

----------------------------------------------------------
-- Diagnostics
----------------------------------------------------------

-- Ctrl+F1

map("n", "<leader>ie", function()
  vim.diagnostic.open_float()
end, {
  desc = IDEA .. ": Show Error",
})

----------------------------------------------------------
-- Generate
----------------------------------------------------------

-- Alt+Insert

map("n", "<leader>ii", function()
  vim.lsp.buf.code_action()
end, {
  desc = IDEA .. ": Generate Code",
})

----------------------------------------------------------
-- Snacks Explorer
----------------------------------------------------------

-- Alt+1
-- IDEA Project View

map("n", "<leader>e", function()
  Snacks.explorer()
end, {
  desc = IDEA .. ": Project View",
})

----------------------------------------------------------
-- Explorer actions
----------------------------------------------------------

-- Alt+Insert
-- Create File

map("n", "<leader>en", function()
  Snacks.explorer.create()
end, {
  desc = IDEA .. ": New File",
})

-- Ctrl+Alt+L inside explorer

map("n", "<leader>ef", function()
  vim.lsp.buf.format({
    async = true,
  })
end, {
  desc = IDEA .. ": Format File",
})

----------------------------------------------------------
-- Debug
----------------------------------------------------------

-- F8

map("n", "<leader>ic", function()
  require("dap").continue()
end, {
  desc = IDEA .. ": Continue Debug",
})

-- Ctrl+F8

map("n", "<leader>ix", function()
  require("dap").toggle_breakpoint()
end, {
  desc = IDEA .. ": Toggle Breakpoint",
})

----------------------------------------------------------
-- Extra IDEA shortcuts
----------------------------------------------------------

-- Ctrl+Shift+A
-- Action Search

map("n", "<leader>iaa", function()
  Snacks.picker.keymaps()
end, {
  desc = IDEA .. ": Find Action",
})

-- Alt+Left

map("n", "<leader>ihistory", function()
  Snacks.picker.git_log()
end, {
  desc = IDEA .. ": Git History",
})
