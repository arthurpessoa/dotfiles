-- Breakpoints outlive the session that set them.
--
-- nvim-dap keeps breakpoints in memory only, so quitting loses every
-- condition and log message with them. They are stored per project root
-- rather than per session, so they follow the code and not the window layout.
local M = {}

-- Which fields survive a restart. `line` is separate because dap's set() takes
-- it positionally; these three go in the opts table. Names here match the
-- shape dap.breakpoints.get() returns (camelCase) so encode/decode round-trip
-- cleanly; M.load() translates to the snake_case keys dap.breakpoints.set()
-- actually reads (see the API note there).
local OPT_FIELDS = { "condition", "logMessage", "hitCondition" }

function M.encode(by_buf, name_of)
  local out = {}
  for bufnr, breakpoints in pairs(by_buf or {}) do
    local name = name_of(bufnr)
    if name and name ~= "" and #breakpoints > 0 then
      local list = {}
      for _, bp in ipairs(breakpoints) do
        local entry = { line = bp.line }
        for _, field in ipairs(OPT_FIELDS) do
          entry[field] = bp[field]
        end
        table.insert(list, entry)
      end
      out[name] = list
    end
  end
  return out
end

function M.decode(data)
  local out = {}
  for file, list in pairs(data or {}) do
    for _, bp in ipairs(list) do
      local opts = {}
      for _, field in ipairs(OPT_FIELDS) do
        opts[field] = bp[field]
      end
      table.insert(out, { file = file, line = bp.line, opts = opts })
    end
  end
  return out
end

-- One file per project. The root is flattened into the file name rather than
-- mirrored as directories: a Windows root starts with a drive letter, and a
-- colon is not legal in a path component.
function M.state_path(root, state_dir)
  local slug = root:gsub("[^%w]", "_")
  return state_dir .. "/dap-breakpoints/" .. slug .. ".json"
end

local function project_root()
  return vim.uv.cwd() or "."
end

local function path_for()
  return M.state_path(project_root(), vim.fn.stdpath("state"))
end

function M.save()
  local ok, breakpoints = pcall(require, "dap.breakpoints")
  if not ok then
    return
  end

  local data = M.encode(breakpoints.get(), function(bufnr)
    return vim.api.nvim_buf_get_name(bufnr)
  end)

  local path = path_for()
  vim.fn.mkdir(vim.fs.dirname(path), "p")

  if not next(data) then
    -- An empty file is how "I cleared them all" is remembered; deleting it
    -- would restore the previous session's breakpoints on the next start.
    vim.fn.writefile({ "{}" }, path)
    return
  end

  vim.fn.writefile({ vim.json.encode(data) }, path)
end

function M.load()
  local path = path_for()
  if not vim.uv.fs_stat(path) then
    return
  end

  local ok, decoded = pcall(vim.json.decode, table.concat(vim.fn.readfile(path), "\n"))
  if not ok or type(decoded) ~= "table" then
    return
  end

  local dap_ok = pcall(require, "dap")
  if not dap_ok then
    return
  end

  local breakpoints = require("dap.breakpoints")

  for _, entry in ipairs(M.decode(decoded)) do
    -- The buffer a breakpoint belongs to is usually not open yet, and
    -- breakpoints.set needs a loaded buffer to attach a sign to.
    local bufnr = vim.fn.bufadd(entry.file)
    vim.fn.bufload(bufnr)

    -- dap.breakpoints.set(opts, bufnr, lnum) forwards opts into toggle(),
    -- which reads opts.condition, opts.log_message and opts.hit_condition
    -- (snake_case) -- NOT the logMessage/hitCondition (camelCase) that
    -- breakpoints.get() and the bp sign table itself use. Confirmed against
    -- the installed plugin: dap/breakpoints.lua's toggle() builds
    -- `logMessage = opts.log_message, hitCondition = opts.hit_condition`,
    -- and dap.lua's own restore_breakpoints() (used by run_to_cursor)
    -- performs the same camelCase -> snake_case translation before calling
    -- breakpoints.set(). Passing entry.opts straight through would silently
    -- drop log points and hit conditions on restore.
    breakpoints.set({
      condition = entry.opts.condition,
      log_message = entry.opts.logMessage,
      hit_condition = entry.opts.hitCondition,
    }, bufnr, entry.line)
  end
end

function M.setup()
  local group = vim.api.nvim_create_augroup("DapPersist", { clear = true })

  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = M.save,
  })

  -- Loading on VeryLazy rather than on VimEnter: dap must be requirable, and
  -- the buffers the breakpoints belong to may not be open yet, which is why
  -- load() adds them itself.
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "VeryLazy",
    callback = function()
      pcall(M.load)
    end,
  })
end

return M
