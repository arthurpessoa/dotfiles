# dotfiles

WezTerm and Neovim configuration for Windows, macOS, and Linux.

- `wezterm/` — modular WezTerm config: bottom powerline bar via `tabline.wez`,
  per-process icons, an activity spinner, git state, AI agent state, and
  desktop notifications.
- `nvim/` — LazyVim, with `smart-splits.nvim` for split navigation.

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
already there — and links the config directories into place. Running it again
changes nothing: links already pointing at the repo are reported and left alone.

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
PowerShell script or pass `--dry-run` to the shell one.

**It links configuration only.** WezTerm, Neovim and the Nerd Font are not
installed for you — see Requirements below. An installer that resolves and
installs those per platform is a separate piece of work, not yet built.

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

WezTerm **nightly**, Neovim 0.10 or newer, and JetBrainsMono Nerd Font.

## Local overrides

`wezterm/local.lua` is gitignored and loaded last. Return a table from it to
override any setting on a single machine.

## Tests

```
nvim -l wezterm/tests/run.lua
```

No dependencies — the harness is 40 lines of Lua and the runner is Neovim.
