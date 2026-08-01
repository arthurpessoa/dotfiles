# WezTerm + Neovim dotfiles — design

Date: 2026-08-01
Repo: https://github.com/arthurpessoa/dotfiles

## Goal

Rebuild the WezTerm configuration as a modular, cross-platform dotfiles repo with
a powerline status bar, per-process icons, live activity animation, git state, AI
agent state, desktop notifications, and Neovim integration. A single command sets
the whole thing up on a fresh Windows, macOS, or Linux machine.

## Non-goals

- No shell prompt changes. The PowerShell profile is not touched.
- No exit-code reporting or failure notifications (needs a prompt hook; declined).
- No clickable `file:line` hyperlink rules.
- No Neovim zen-mode syncing.
- No workspace switcher plugin (`smart_workspace_switcher` needs zoxide; declined).

## Starting point

`~/.wezterm.lua`, 302 lines, single file: `kanagawa.wz` plugin, JetBrainsMono Nerd
Font 12.5, acrylic backdrop, opacity 0.97, retro tab bar, `wezterm-agent-deck`, and
hand-written `update-right-status` / `format-tab-title` callbacks. Neovim is a
LazyVim install at `%LOCALAPPDATA%\nvim`, not under version control.

## Repository layout

```
~/.dotfiles/
  install.ps1              Windows bootstrap
  install.sh               macOS + Linux bootstrap
  README.md                one-liners + what gets installed
  .gitignore               local.lua, *.bak-*, git cache files
  wezterm/
    wezterm.lua            entry point
    modules/
      platform.lua         every OS branch lives here
      theme.lua            colours, font, padding, window chrome
      plugins.lua          plugin.require calls
      icons.lua            process basename -> glyph + busy/shell tag
      activity.lua         per-pane busy state, spinner, long-run notify
      git.lua              per-repo status cache
      agent.lua            AI state + notifications
      bar.lua              tabline sections and custom components
      keys.lua             leader, keybinds, smart-splits forwarding
  nvim/                    the LazyVim config, moved in whole
  docs/specs/  docs/plans/
```

The repo is the source of truth. Config directories are links back into it.

## Bootstrap

README carries two one-liners:

```powershell
irm https://raw.githubusercontent.com/arthurpessoa/dotfiles/main/install.ps1 | iex
```

```bash
curl -fsSL https://raw.githubusercontent.com/arthurpessoa/dotfiles/main/install.sh | bash
```

Alongside each, the README shows the download-inspect-run form, because piping a
URL into a shell executes whatever that URL serves at that moment with no chance to
read it first.

Both scripts perform the same five steps:

1. **Detect the package manager** — `winget`, falling back to `scoop`, on Windows;
   `brew` on macOS; `apt`, `dnf`, or `pacman` on Linux. Abort with a clear message
   if none is found.
2. **Install packages** — git, wezterm, neovim, and the JetBrainsMono Nerd Font.
   Already-installed packages are skipped, not reinstalled. Nothing else: the
   pickers used by `resurrect` and `quick_domains` are WezTerm's built-in
   `InputSelector`, so no fuzzy finder is needed.
3. **Clone** the repo to `~/.dotfiles`, or `git pull` if it is already there.
4. **Link** the config directories (below).
5. **Print** what changed, including the path of any backup it made.

Scripts are idempotent: a second run on a configured machine makes no changes
beyond a `git pull`.

### Linking

| Target | Points at |
| --- | --- |
| `~/.config/wezterm` | `~/.dotfiles/wezterm` |
| `~/.config/nvim` (Unix) | `~/.dotfiles/nvim` |
| `%LOCALAPPDATA%\nvim` (Windows) | `~/.dotfiles/nvim` |

Unix uses `ln -s`. Windows uses a **directory junction** (`New-Item -ItemType
Junction`), which needs neither administrator rights nor Developer Mode; a symlink
would need one of the two.

An existing directory at a target path is renamed to `<name>.bak-<timestamp>` and
left in place. Nothing is ever deleted. An existing link that already points at the
repo is left alone.

`~/.wezterm.lua` is copied into the repo as the basis for the rewrite and then
deleted, because WezTerm reads either `~/.wezterm.lua` or
`~/.config/wezterm/wezterm.lua` and keeping both is ambiguous.

## Configuration architecture

`wezterm.lua` builds the config object and hands it to each module in turn. It
contains no logic of its own.

`activity.lua`, `git.lua`, and `agent.lua` are pure state providers. Each polls on
its own cadence and exposes `get(pane)` returning a plain table. None of them knows
the bar exists, and each can be exercised in isolation. `bar.lua` only formats what
they return.

### Two clocks

- **120 ms** (`status_update_interval`) — bar redraw, spinner frames, and the
  foreground-process read. `pane:get_foreground_process_name()` comes from WezTerm's
  own process tracking, so this costs no syscall.
- **4 s** — git. A blocking `run_child_process` inside the status callback would
  stall the GUI thread, so `git.lua` uses `background_child_process` to write
  command output to a temp file, and the fast clock reads that file only when its
  mtime changes.

### platform.lua

The only module that inspects `wezterm.target_triple`. It exports:

- `default_prog` — `pwsh -NoLogo` on Windows, `$SHELL` elsewhere.
- `backdrop` — `win32_system_backdrop = "Acrylic"` on Windows,
  `macos_window_background_blur` on macOS, plain opacity on Linux.
- `temp_dir` — where the git cache file is written.
- `shell_cmd(str)` — `{"pwsh", "-NoProfile", "-c", str}` or `{"sh", "-c", str}`,
  used for `background_child_process`.
- `mod_primary` — `"CMD"` on macOS, `"CTRL|SHIFT"` elsewhere.
- `nvim_config_dir` — for the installer and for documentation.

No other module tests the platform.

### theme.lua

Kanagawa via the existing `kanagawa.wz` plugin. JetBrainsMono Nerd Font 12.5,
padding 8 on all sides, opacity 0.97, backdrop from `platform.lua`,
`window_decorations = "RESIZE"`, 100k scrollback, bell disabled — all carried over
unchanged.

Added: `inactive_pane_hsb` dimming so the focused pane reads instantly, a blinking
bar cursor with `EaseInOut` easing, and a pinned `window_frame` font and size so
tabline's separators sit flush against the bar instead of leaving hairlines.

### icons.lua

One table keyed by process basename. Each entry carries a Nerd Font glyph, an
optional colour, and a `kind` of `busy` or `shell`.

`busy`: cargo, rustc, node, npm, pnpm, yarn, tsc, java, gradle, gradlew, mvn,
kotlinc, python, uv, pip, pytest, go, docker, docker-compose, make, cmake, msbuild.

`shell`: pwsh, powershell, cmd, bash, zsh, fish, wsl, ssh, nvim, vim.

Unknown processes fall back to a terminal glyph and `shell`. The same table feeds
tabline's `process_to_icon`, so tab icons and busy detection can never disagree.
Adding a tool later is one line.

### activity.lua

Per pane, each tick:

1. Read the foreground process name, take the basename, look it up in `icons.lua`.
2. `shell` → idle. `busy` → busy.
3. idle→busy stamps a start time. busy→idle computes elapsed; if elapsed > 30 s
   **and** the pane's tab is not the active tab, raise a toast reading
   `cargo test — 4m12s`. No exit code is available from process-name polling, and
   none is shown.

The spinner frame is `floor(now * 8) % 8` — derived from the clock rather than a
per-pane counter, so every spinner in the window turns in lockstep. Frames are the
8 braille cells `⠋⠙⠹⠸⠼⠴⠦⠧`, which are single-width and never shift the layout.

### git.lua

One cache entry per repository root, keyed by the pane's current working directory.
Panes in the same repository share the entry and the process.

Every 4 s a background `git status --porcelain=v2 --branch` writes to
`<temp_dir>/wezterm-git-<hash>`. One command yields branch name, ahead/behind
counts, and dirty file count together, so there is no second invocation and no
`.git/HEAD` parsing.

Rendered states:

| State | Rendering |
| --- | --- |
| Clean | ` main ` in aqua |
| Uncommitted changes | ` feat/x  3` in amber, bold |
| Committed, unpushed | ` feat/x  2` in blue |
| Both | amber, both markers, dirty first |
| Detached HEAD | ` cc3e0db` in red |
| Not a repository | section hidden entirely |

No empty bracket or placeholder is ever shown.

### agent.lua

- **claude** — `agent_deck.get_status()`, which already reports working, waiting,
  and idle.
- **kiro-cli, copilot** — process-name detection only, giving busy or idle. Neither
  publishes a waiting state, so neither gets one.

Colours: working green with a spinner, waiting amber with a static `◔`, idle blue
`○`. With no agent process present the segment is hidden.

The robot glyph pulses between green and amber while an agent is working, on the
same 120 ms clock.

Notifications:

- **Waiting for input** — toast immediately.
- **Finished** — derived from the working→idle transition, the same mechanism
  `activity.lua` uses; toast carries elapsed time, and fires only when the tab is
  not focused.

No Claude Code hook edits are required. `agent.lua` exposes a documented
`on_user_var(name, value)` entry point so a CLI that later grows an OSC user-var
can report exact state without restructuring anything.

### bar.lua

Built on `tabline.wez`, which supplies powerline separators, `process_to_icon`,
mode detection, and the cpu/ram/battery/datetime components. Three components are
written by hand: git, agent, and the busy spinner.

| Section | Contents |
| --- | --- |
| A | `mode` (built-in) — normal / LEADER / copy / search |
| B | `workspace` (built-in) |
| C | `git` (custom) |
| TABS | `index` + `process` + `tab` + busy spinner (custom) + `zoomed` |
| X | `agent` (custom) |
| Y | `cpu` + `ram` (built-in); `battery` only when the machine has one |
| Z | `datetime` (built-in) |

**Known risk.** WezTerm repaints tab titles when the status bar ticks, which is what
makes an animated spinner inside a tab title possible. This is verified during
implementation on a real build. If tab titles turn out not to repaint on the timer,
the tab spinner degrades to a static busy dot and only the right-hand spinner
animates; nothing else in the design changes.

### keys.lua

Existing bindings are kept: LEADER `CTRL+q`, `LEADER h/j/k/l` pane navigation,
`<primary>+v` / `<primary>+h` splits inheriting the cwd, `LEADER z` zoom,
`LEADER w` close pane, `<primary>+t` new tab, `<primary>+[` / `]` tab cycling,
`LEADER p` launcher, `<primary>+W` workspace launcher, and the `CTRL+SHIFT` +
left-drag window drag.

`<primary>` is `CMD` on macOS and `CTRL|SHIFT` elsewhere, from `platform.lua`.
LEADER stays `CTRL+q` on every platform so leader chords are identical everywhere.

Added:

- `LEADER s` — resurrect: save current workspace state.
- `LEADER r` — resurrect: restore from a fuzzy picker.
- `LEADER d` — quick_domains: pick an SSH host, WSL distro, or docker container.
- `CTRL+h/j/k/l` — smart-splits. WezTerm checks whether the pane is running Neovim;
  if so it forwards the key, otherwise it switches pane.

### Plugins

| Plugin | Purpose |
| --- | --- |
| `sravioli/kanagawa.wz` | colour scheme (already in use) |
| `michaelbrusegard/tabline.wez` | status bar framework |
| `Eric162/wezterm-agent-deck` | AI agent state (already in use) |
| `MLFlexer/resurrect.wezterm` | save and restore workspace layouts |
| `DavidRR-F/quick_domains.wezterm` | SSH / WSL / docker domain picker |

Plugins fetch themselves on first launch, so the installers have no plugin step.

## Neovim integration

Two changes to the LazyVim config, which now lives at `~/.dotfiles/nvim`:

1. **`lua/plugins/smart-splits.lua`** — `mrjones2014/smart-splits.nvim`, with
   `CTRL+h/j/k/l` mapped to its directional move functions. Together with the
   WezTerm side, one set of keys moves across both Neovim splits and WezTerm panes.
2. **`lua/config/autocmds.lua`** — an autocmd group that pushes the current file
   name, modified flag, and mode as an OSC 1337 user-var on `BufEnter`,
   `BufModifiedSet`, and `ModeChanged`. The tab then shows ` main.rs ●` instead of
   a bare `nvim`. `bar.lua` reads the user-var through WezTerm's
   `user-var-changed` event and falls back to the plain process name when it is
   absent, so a Neovim without the autocmd still renders correctly.

## Secrets

Nothing machine-specific or private is committed. No SSH config, no environment
files, no tokens, no work hostnames. `quick_domains` reads `~/.ssh/config` at
runtime; that file stays outside the repository.

`.gitignore` covers `local.lua`, `*.bak-*`, and the git cache files.

`wezterm/local.lua` is gitignored and loaded last if present. It can override any
setting, which is where a machine-specific font size or an extra domain belongs.

## Verification

- `wezterm -n --config-file ~/.dotfiles/wezterm/wezterm.lua start -- pwsh` launches a
  throwaway instance, so broken Lua cannot take down the running terminal.
- The bar is checked in five states: idle, a build running, AI working, AI waiting,
  and a pane outside any git repository.
- A notification is confirmed by backgrounding a tab during a build longer than 30
  seconds.
- `nvim --headless "+checkhealth smart-splits" +qa` covers the Neovim side.
- `install.ps1` is re-run on the configured machine to prove idempotence: existing
  directories become `.bak-<timestamp>` and no data is lost.

macOS and Linux installers are written against their package managers but can only
be smoke-tested on Windows. Both are marked untested-on-target in the README until
run on a real machine of that kind.
