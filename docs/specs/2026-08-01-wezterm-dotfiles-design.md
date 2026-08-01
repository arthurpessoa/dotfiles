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
  install/
    catalog.psd1           rows, sources, checks (PowerShell)
    catalog.sh             the same rows (POSIX)
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

Both scripts follow the same four phases: **probe**, **select**, **install**, **link**.

### Phase 1 — probe

Runs before anything is drawn and prints its findings.

- **OS and arch** — `$PSVersionTable` / `uname -sm`.
- **Privilege**, three outcomes rather than two:

  | Outcome | Detected by | Effect |
  | --- | --- | --- |
  | Already elevated | `IsInRole(Administrator)` / `euid 0` | every row enabled |
  | Can elevate | account in the Administrators group; `sudo -n true` or membership of sudo/wheel | admin-only rows enabled, one elevation prompt at install time |
  | Standard user | neither | admin-only rows disabled with the reason shown, and listed in a banner above the menu |

- **Package managers present** — winget, scoop, choco; brew; apt, dnf, pacman, zypper;
  sdkman; npm.

### Phase 2 — select

An ANSI checklist drawn by the script itself. No `fzf`, `gum`, or other dependency,
because the installer has to run before anything is installed.

```
 dotfiles installer                                  Windows 11 · x64
 privilege  standard user — no elevation path
 managers   scoop ✓   winget ✓   choco ✗   sdkman ✗

 1 row disabled: docker desktop (needs admin)

 PACKAGE MANAGERS
  [✓] scoop                already installed
  [✓] winget               already installed
  [x] sdkman               get.sdkman.io · user · needs Git Bash
 CORE
  [✓] git                  already installed
  [x] wezterm-nightly      scoop:versions · user      ← winget: no user scope
  [✓] neovim               already installed
  [x] JetBrainsMono NF     scoop:nerd-fonts · user
 TOOLBELT
  [x] ripgrep fd fzf bat eza zoxide lazygit gh jq     scoop:main · user
 TOOLCHAINS
  [x] rust                 rustup.rs · user
  [ ] node                 fnm · user
  [ ] python               uv · user
  [ ] jvm                  sdkman · user             → scoop:java (temurin-lts)
 CONTAINERS + AI
  [-] docker desktop       needs admin — disabled
  [x] docker cli           scoop:main · user
  [x] claude-code          npm · user
 DOTFILES
  [x] clone + link configs

 space toggle · a all · n none · g group · s cycle source · d dry-run · enter · q
```

Keys: `space` toggles a row, `a` selects all enabled rows, `n` clears, `g` toggles a
whole group, `s` cycles that row's source among the viable ones for this machine,
`d` prints the exact commands without running them, `enter` installs, `q` quits.

Rows whose `check` already passes render `[✓] already installed` and are skipped, so
a second run is a no-op. Disabled rows show why. The linking step is an ordinary row,
so tools can be installed without touching configs, or the reverse.

### Source resolution

Each catalog entry lists methods as `{platform, manager, scope, install, check}`. The
resolver picks the first viable one and offers the rest under `s`. It **prefers
user-scope even when admin is available**, so a machine gives the same result whether
or not the shell happens to be elevated.

Windows ladder:

1. `winget --scope user`, but only where the manifest actually declares user scope.
   This is probed at run time with `winget show --scope user <id>`, never hardcoded,
   because manifests change. Measured on 2026-08-01 with winget 1.29.280: Git.Git,
   GitHub.cli, BurntSushi.ripgrep.MSVC, ajeetdsouza.zoxide, Schniz.fnm and astral-sh.uv
   resolve under user scope; Neovim.Neovim, Docker.DockerDesktop and
   EclipseAdoptium.Temurin.21.JDK are machine-only; wez.wezterm, Rustlang.Rustup and
   DEVCOM.JetBrainsMonoNerdFont declare no scope at all and are therefore excluded by
   *both* scope filters.
2. `scoop`, which is user-scoped by definition. Missing buckets are added
   automatically: `versions` for wezterm-nightly, `nerd-fonts` for the font, `java`
   for temurin, `extras` for lazygit.
3. The tool's own user-scope installer — rustup.rs, fnm, uv, sdkman, npm.
4. `winget --scope machine`, only when elevation is available.
5. Otherwise disabled, with the reason displayed.

macOS and Linux use the same shape: brew → the tool's own `$HOME` installer → the
system package manager with sudo → disabled. On Linux without sudo, brew installs to
`~/.linuxbrew` and needs no elevation.

### Catalog

Package managers are rows themselves, so a bare machine can bootstrap one before
anything else installs.

| Row | Windows | macOS | Linux |
| --- | --- | --- | --- |
| scoop | `get.scoop.sh`, user | — | — |
| winget | preinstalled on Win11; App Installer otherwise | — | — |
| brew | — | `brew.sh`, `/opt/homebrew` (sudo once) or `~/homebrew` | `~/.linuxbrew`, no sudo |
| sdkman | `get.sdkman.io` via Git Bash | `get.sdkman.io` | `get.sdkman.io` |
| git | winget user / scoop | brew | apt·dnf·pacman / brew |
| **wezterm** | **`scoop:versions/wezterm-nightly`** | **`brew --cask wezterm@nightly`** | **`nightly` GitHub release: AppImage without sudo, .deb/.rpm with** |
| neovim | scoop:main | brew | brew / system |
| JetBrainsMono NF | scoop:nerd-fonts | brew --cask | manual to `~/.local/share/fonts` |
| toolbelt: ripgrep, fd, fzf, bat, eza, zoxide, lazygit, gh, jq | scoop | brew | brew / system |
| rust | rustup.rs | rustup.rs | rustup.rs |
| node | fnm | fnm | fnm |
| python | uv | uv | uv |
| jvm | sdkman via Git Bash, else `scoop:java/temurin-lts` | sdkman | sdkman |
| docker desktop | winget, **admin only** | brew --cask | system, sudo |
| docker cli | scoop:main | brew | brew / system |
| AI CLIs: claude-code, kiro-cli, copilot-cli | npm, user | npm | npm |
| clone + link configs | always available | | |

WezTerm is pinned to nightly on every platform. The stable channel lags — scoop's
`extras/wezterm` was still on the 2024-02-03 build as of 2026-08-01 — and the
configuration targets current nightly behaviour.

The catalog lives in one data file per shell (`install/catalog.psd1`,
`install/catalog.sh`) carrying identical rows, so adding a tool is a data change
rather than a code change.

### Non-interactive use

`curl | bash` feeds the script itself on stdin, so the selection loop reads keys from
`/dev/tty`; PowerShell's `irm | iex` keeps the console attached and uses `ReadKey`.
When no tty exists at all — CI, `ssh -T` — the script refuses to guess and exits
telling you to pass a flag.

Flags: `--all`, `--only git,wezterm,nvim`, `--yes`, `--dry-run`,
`--scope user|machine`, `--manager scoop`.

### Phase 3 — install

Selected rows run in catalog order, so a package manager row installs before anything
that depends on it. If any selected row needs elevation and elevation is available,
the prompt happens once, before the first admin-only command, rather than partway
through the run.

A row that fails does not abort the run. Its error is captured, the remaining rows
continue, and the closing summary lists successes, skips, and failures with the exact
command that failed so it can be re-run by hand.

### Phase 4 — link

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

**The bar sits at the bottom**: `tab_bar_at_bottom = true`, with
`use_fancy_tab_bar = false` and `hide_tab_bar_if_only_one_tab = false` carried over.
Placement is WezTerm's setting rather than tabline's, and tabline requires the retro
tab bar in any case, so it is applied in `theme.lua` after
`tabline.apply_to_config(config)` — the plugin sets `use_fancy_tab_bar` itself and
must not be able to overwrite the placement afterwards.

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

The bar renders at the bottom of the window, so section A sits in the bottom-left
where a vim statusline would — which is where the LEADER indicator is most useful.

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

## Implementation order

Two phases, each independently useful.

1. **Configuration** — repo skeleton, linking by hand, `wezterm/` modules, the Neovim
   two files. Ends with a working bar on this machine.
2. **Installer** — probe, catalog, selection UI, resolver, and the README one-liners.
   Ends with a fresh-machine bootstrap.

The current machine already satisfies much of phase 2's catalog: scoop with the main,
extras and versions buckets, `wezterm-nightly nightly-20260731`, neovim 0.12.4,
ripgrep, fd, fzf, lazygit and nodejs. Phase 2 is therefore validated mostly through
`--dry-run` here, and end to end on a clean machine or VM.

## Verification

- `wezterm -n --config-file ~/.dotfiles/wezterm/wezterm.lua start -- pwsh` launches a
  throwaway instance, so broken Lua cannot take down the running terminal.
- The bar is checked in five states: idle, a build running, AI working, AI waiting,
  and a pane outside any git repository.
- A notification is confirmed by backgrounding a tab during a build longer than 30
  seconds.
- `nvim --headless "+checkhealth smart-splits" +qa` covers the Neovim side.
- `install.ps1 --dry-run --all` prints every resolved command without running one,
  which is how the source ladder is inspected.
- `install.ps1` is re-run on the configured machine to prove idempotence: already
  satisfied rows render `already installed` and are skipped, existing directories
  become `.bak-<timestamp>`, and no data is lost.
- The standard-user path is exercised by running the probe from a non-elevated shell
  and confirming that docker desktop renders disabled with its reason, while
  wezterm-nightly still resolves through scoop.
- `--only` and the no-tty refusal are checked by piping the script with stdin closed.

macOS and Linux installers are written against their package managers but can only
be smoke-tested on Windows. Both are marked untested-on-target in the README until
run on a real machine of that kind.
