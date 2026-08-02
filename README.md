# dotfiles

WezTerm and Neovim configuration for Windows, macOS, and Linux.

- `wezterm/` — modular WezTerm config: bottom powerline bar via `tabline.wez`,
  per-process icons, an activity spinner, git state, AI agent state, and
  desktop notifications.
- `nvim/` — LazyVim, with a Java/Kotlin toolchain, a persistent debugger, and
  a statusline matched to the WezTerm bar.
- `shared/` — the glyph encoder, the Kanagawa palette and the icon registry
  both `nvim/` and `wezterm/` read from, so an icon changed once changes in
  both places.

## Install

Windows:

```powershell
irm https://raw.githubusercontent.com/arthurpessoa/dotfiles/main/install.ps1 | iex
```

macOS and Linux:

```bash
curl -fsSL https://raw.githubusercontent.com/arthurpessoa/dotfiles/main/install.sh | sh
```

Either one clones this repository to `~/.dotfiles` — or pulls it if it is
already there — links the config directories into place, and installs the
command-line tools Neovim reaches for: `fd`, `ripgrep`, `fzf` and `gh` (octo
needs `gh` to reach GitHub). Running it again changes nothing: links already
pointing at the repo and tools already on PATH are reported and left alone.

Tools come from scoop first and winget second on Windows, and from Homebrew or
the system package manager elsewhere. A tool counts as installed when its
command answers afterwards, not when the package manager exits zero — managers
exit non-zero refusing to reinstall something already present. Where root is
needed and no passwordless `sudo` is available, the exact command is printed
rather than prompting for a password that a piped shell cannot read.

On Debian and Ubuntu the `fd` binary is installed as `fdfind`, so a
`~/.local/bin/fd` link is created pointing at it; the script says so, and warns
if `~/.local/bin` is not on your PATH.

Piping a URL into a shell runs whatever that URL serves at that moment, with no
chance to read it first. To look before running:

```powershell
irm https://raw.githubusercontent.com/arthurpessoa/dotfiles/main/install.ps1 -OutFile install.ps1
# read it, then:
./install.ps1
```

```bash
curl -fsSL https://raw.githubusercontent.com/arthurpessoa/dotfiles/main/install.sh -o install.sh
# read it, then:
sh install.sh
```

To see what it would do without doing it, set `DOTFILES_DRY_RUN=1` for the
PowerShell script or pass `--dry-run` to the shell one. `DOTFILES_SKIP_TOOLS=1`
links the configs and installs nothing.

**WezTerm, Neovim and the Nerd Font are not installed for you** — see
Requirements below. An installer that resolves and installs those per platform
is a separate piece of work, not yet built.

## Layout

Config directories are links back into this repo:

| Target | Points at |
| --- | --- |
| `~/.config/wezterm` | `wezterm/` |
| `~/.config/nvim` (macOS, Linux) | `nvim/` |
| `%LOCALAPPDATA%\nvim` (Windows) | `nvim/` |

Windows uses directory junctions, which need neither administrator rights nor
Developer Mode.

## Requirements

WezTerm **nightly**, Neovim 0.12 or newer, and JetBrainsMono Nerd Font. The
`editor.refactoring` extra hard-errors below 0.12
(`extras/editor/refactoring.lua`), which sets the floor for the whole config.

## Local overrides

`wezterm/local.lua` is gitignored and loaded last. Return a table from it to
override any setting on a single machine.

## Neovim

LazyVim, with the language, debug, test and UI support coming from its extras
rather than from hand-written specs. `nvim/lua/plugins` holds only deltas, and
every one of them is an `opts` table: a `config` function replaces LazyVim's
spec instead of merging with it, which is how the same language server ends up
attached twice.

`shared/` holds the glyph encoder, the Kanagawa palette and the icon registry,
and both this config and the WezTerm one read from it, so an icon changed in
one place changes in both.

Java picks its own JDK. `nvim/lua/util/jdk.lua` finds every installation on the
machine, hands jdtls one new enough to run it, and gives the language server the
full list so a project can target whichever it needs. `:JdkList` shows what it
found.

`<leader>i` is an IntelliJ vocabulary laid over LazyVim's own; `<leader>d` and
the F-keys are the debugger.

## Tests

    nvim -l wezterm/tests/run.lua
    nvim -l nvim/tests/run.lua

No dependencies — the harness is 40 lines of Lua and the runner is Neovim.

Changing an icon also means checking it exists in the font:

    pip install fonttools
    python nvim/scripts/verify-glyphs.py

That checks the font's cmap. A codepoint can be present and still render
blank, so `:IconAudit` inside Neovim draws every glyph for a visual pass.
