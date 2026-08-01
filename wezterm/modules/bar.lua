local wezterm = require("wezterm")
local icons = require("modules.icons")
local activity = require("modules.activity")
local git = require("modules.git")
local agent = require("modules.agent")

local M = {}

-- How often the CPU/memory sample is taken. Sampling costs a process launch,
-- so it is deliberately much slower than the status tick.
local SYSINFO_POLL_SECONDS = 10

-- agent-deck reads each pane's scrollback to tell working from waiting, so it
-- runs far slower than the status tick as well.
local AGENT_POLL_SECONDS = 0.5
local agent_polled_at = -math.huge

-- The sysinfo poll is a single global reading, not per-pane state, so it lives
-- here rather than in the `state` table bar.apply is handed. Both are rebuilt
-- from scratch on every config reload.
local sysinfo = { polled_at = -math.huge, path = nil, cpu = nil, ram = nil }

-- Tab titles are not redrawn on the status tick. WezTerm calls
-- format-tab-title often enough, but it repaints the tab bar only every few
-- seconds, so a rotating frame there reads as a glyph stuck at a random angle.
-- Measured on wezterm 20260731-083202-9554bdd0 by putting the frame index in
-- the tab as a digit: it changed twice in six seconds. The busy marker in a tab
-- is therefore static, and the animated spinner survives only in the right-hand
-- agent segment, which does ride the status tick.
local BUSY_GLYPH = require("modules.glyph").u(0x25cf) -- black circle

-- Fractional seconds. activity.frame advances eight times a second, so whole
-- seconds would pin the spinner to a single frame forever; chrono's %.3f adds
-- the milliseconds. Everything else here only ever takes differences, so the
-- extra precision is free.
local function now_seconds()
  return tonumber(wezterm.time.now():format("%s%.3f"))
end

local function read_file(path)
  if not path then return nil end
  local handle = io.open(path, "r")
  if not handle then return nil end
  local text = handle:read("*a")
  handle:close()
  return text
end

-- Every sample in this module goes through here: a background process writes
-- to a file and the status callback only ever opens that file. Nothing on the
-- callback waits for a child process.
local function poll(entry, platform, interval, command)
  local now = now_seconds()
  if now - entry.polled_at >= interval then
    entry.polled_at = now
    wezterm.background_child_process(
      platform.shell_cmd(string.format('%s > "%s" 2>&1', command, entry.path)))
  end
  return read_file(entry.path)
end

-- A pane's working directory arrives as a URL, and on Windows its file_path
-- keeps the URL's leading slash: "/C:/Projects/x". git rejects that outright,
-- so drop the slash when a drive letter follows it. The pattern cannot match a
-- POSIX path, so this is not an OS branch.
local function pane_cwd(pane)
  local url = pane and pane:get_current_working_dir()
  local path = url and url.file_path or nil
  if not path then return nil end
  return (path:gsub("^/(%a:)", "%1"))
end

local function refresh_git(state, platform, cwd)
  if not cwd then return nil end
  local key = git.repo_key(cwd)
  local entry = state.git[key]

  if not entry then
    entry = { info = nil, polled_at = -math.huge, path = git.cache_path(platform.temp_dir, key) }
    state.git[key] = entry
  end

  -- `git -C` rather than `cd <dir> && git`: one command, no shell chaining, and
  -- no chance of a bracket in the path being read as a glob by Set-Location.
  local text = poll(entry, platform, git.POLL_SECONDS,
    string.format('git -C "%s" status --porcelain=v2 --branch', cwd))

  -- Only a reading that carries a branch header counts. The file is truncated
  -- the instant the poll starts, so a read can land on an empty or half-written
  -- one, and git's own failures land in it too; parsing either would render a
  -- confident, wrong segment. Anything unrecognised leaves the last reading in
  -- place, and only a definite "no repository here" clears it.
  if text and text:find("# branch.head", 1, true) then
    entry.info = git.parse(text)
  elseif text and text:find("not a git repository", 1, true) then
    entry.info = nil
  end

  return entry.info
end

local function refresh_sysinfo(platform)
  -- Only the platforms platform.lua has a verified sample command for show a
  -- reading; elsewhere the section is simply absent.
  if not platform.sysinfo_command then return nil end
  sysinfo.path = sysinfo.path or (platform.temp_dir .. "/wezterm-sysinfo")

  local text = poll(sysinfo, platform, SYSINFO_POLL_SECONDS, platform.sysinfo_command)
  -- The file is empty for as long as the sample takes to run, which is most of
  -- a second; keep the last reading rather than blinking the section out.
  local cpu, ram = (text or ""):match("([%d%.]+)%s*\r?\n%s*([%d%.]+)")
  if cpu then
    sysinfo.cpu, sysinfo.ram = cpu, ram
  end
  return sysinfo.cpu, sysinfo.ram
end

-- agent-deck holds no timer of its own unless apply_to_config installs one, and
-- that also brings its tab titles, its right status and its own notifications.
-- Only the detection is wanted here, so the panes are walked from this module's
-- update-status handler instead and the plugin is left to do nothing else.
local function refresh_agents(plugins, window, now)
  if now - agent_polled_at < AGENT_POLL_SECONDS then return end
  agent_polled_at = now
  for _, tab in ipairs(window:mux_window():tabs()) do
    for _, pane in ipairs(tab:panes()) do
      pcall(function() plugins.agent_deck.update_pane(pane) end)
    end
  end
end

local function agent_states(plugins)
  local entries
  pcall(function() entries = plugins.agent_deck.get_all_agent_states() end)
  return entries
end

-- tabline expects `{ "<glyph>", color = { fg = "#rrggbb" } }`; icons.lua speaks
-- `{ glyph = ..., color = ... }`. The translation belongs here, where the rest
-- of the presentation lives.
local function process_to_icon()
  local map = {}
  for name, entry in pairs(icons.process_to_icon()) do
    map[name] = { entry.glyph, color = { fg = entry.color } }
  end
  return map
end

-- tabline derives its own theme from a colour scheme table. Handed the Kanagawa
-- scheme as-is it would take the tab-bar grey for the section background, so
-- point that key at the real background first. get() returns a fresh clone, so
-- this cannot disturb the scheme theme.lua applies to the terminal.
local function tabline_theme(plugins)
  local scheme = plugins.kanagawa.get("wave")
  scheme.tab_bar.inactive_tab.bg_color = scheme.background
  return scheme
end

-- Neovim publishes the file it has open as an OSC 1337 user var (see
-- nvim/lua/config/autocmds.lua) and WezTerm keeps user vars per pane, so the
-- tab can name the file rather than repeat the process. Neovim writes an empty
-- value on exit, which is what puts the tab title back. tabline's own "tab"
-- component renders the literal string "default" for an untitled tab, so the
-- fallback is handled here too.
local function tab_title(tab)
  local pane = tab.active_pane
  local file = pane and pane.user_vars and pane.user_vars["nvim-file"]
  if file and file ~= "" then return file end
  return tab.tab_title or ""
end

-- Read-only on purpose. activity.update advances the store and consumes the
-- busy -> idle transition that raises the notification, and format-tab-title
-- runs on its own schedule as well as on the status tick, so calling update
-- from here would sometimes swallow a notification. The store is advanced in
-- exactly one place: the update-status handler at the bottom of this file.
local function tab_busy_marker(tab)
  local pane = tab.active_pane
  if not pane then return "" end
  if icons.lookup(pane.foreground_process_name).kind ~= "busy" then return "" end
  return " " .. BUSY_GLYPH
end

function M.apply(config, plugins, platform, state)
  -- Material Design pair, the same block icons.lua draws from. tabline's own
  -- cpu component uses oct_cpu, which resolves in the font but came out blank
  -- in the bar.
  local CPU_GLYPH = wezterm.nerdfonts.md_chip
  local RAM_GLYPH = wezterm.nerdfonts.md_memory

  -- agent-deck raises its own toast the moment a pane starts waiting, and
  -- agent.update raises one for the same transition. Its own rendering is off
  -- for the same reason: this config draws the segment and the tab titles.
  pcall(function()
    plugins.agent_deck.set_config({
      notifications = { enabled = false },
      tab_title = { enabled = false },
      right_status = { enabled = false },
    })
  end)

  plugins.tabline.setup({
    options = {
      icons_enabled = true,
      theme = tabline_theme(plugins),
      section_separators = {
        left = wezterm.nerdfonts.pl_left_hard_divider,
        right = wezterm.nerdfonts.pl_right_hard_divider,
      },
      component_separators = {
        left = wezterm.nerdfonts.pl_left_soft_divider,
        right = wezterm.nerdfonts.pl_right_soft_divider,
      },
      tab_separators = {
        left = wezterm.nerdfonts.pl_left_hard_divider,
        right = wezterm.nerdfonts.pl_right_hard_divider,
      },
    },
    sections = {
      tabline_a = { "mode" },
      tabline_b = { "workspace" },
      tabline_c = {
        function(_window, pane)
          local cwd = pane_cwd(pane)
          local segment = git.render(refresh_git(state, platform, cwd))
          if not segment then return "" end
          return wezterm.format({
            { Foreground = { Color = segment.color } },
            { Text = segment.text },
          })
        end,
      },
      tab_active = {
        "index",
        { "process", padding = { left = 0, right = 1 }, process_to_icon = process_to_icon() },
        tab_title,
        tab_busy_marker,
        "zoomed",
      },
      tab_inactive = {
        "index",
        { "process", padding = { left = 0, right = 1 }, process_to_icon = process_to_icon() },
        tab_title,
        tab_busy_marker,
        "zoomed",
      },
      tabline_x = {
        function(window, pane)
          local deck = agent.pick(agent_states(plugins), pane and pane:pane_id() or nil)
          local process = pane and pane:get_foreground_process_name() or nil
          local result = agent.update(
            state.agent, agent.classify(deck, process), now_seconds(), window:is_focused())
          if result.notify then
            window:toast_notification(result.notify.title, result.notify.body, nil, 6000)
          end
          if not result.segment then return "" end
          return wezterm.format({
            { Foreground = { Color = result.segment.color } },
            { Text = result.segment.text },
          })
        end,
      },
      -- Empty on the platforms platform.lua has no verified sample command
      -- for. It has to be named either way: tabline falls back to its own
      -- datetime and battery components for a section left out entirely, and
      -- its cpu and ram components shell out on every status tick.
      tabline_y = platform.sysinfo_command and {
        function()
          local cpu, ram = refresh_sysinfo(platform)
          if not cpu then return "" end
          -- Leading space on purpose: a glyph placed in the cell immediately
          -- after the section's powerline divider does not get drawn.
          return string.format(" %s %s%%  %s %s GB", CPU_GLYPH, cpu, RAM_GLYPH, ram)
        end,
      } or {},
      tabline_z = { "datetime" },
    },
    extensions = { "resurrect", "quick_domains" },
  })

  plugins.tabline.apply_to_config(config)

  wezterm.on("user-var-changed", function(_window, _pane, name, value)
    agent.on_user_var(state.agent, name, value)
  end)

  wezterm.on("update-status", function(window)
    local focused = window:is_focused()
    refresh_agents(plugins, window, now_seconds())
    for _, tab in ipairs(window:mux_window():tabs_with_info()) do
      local pane = tab.tab:active_pane()
      local result = activity.update(
        state.activity, pane:pane_id(), pane:get_foreground_process_name(),
        now_seconds(), tab.is_active and focused)
      if result.notify then
        window:toast_notification(result.notify.title, result.notify.body, nil, 6000)
      end
    end
  end)
end

return M
