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
the F-keys are the debugger. See [Keybindings](#keybindings).

## Keybindings

Leader is `<Space>`. `★` marks a binding this config adds; everything else comes
from Vim itself or from LazyVim.

Two things worth knowing before you go looking for a key that seems missing:

- **LSP and git-hunk bindings are buffer-local.** `gd`, `gr`, `K`, `<leader>ca`,
  `<leader>gh*` and friends only exist once a language server or gitsigns has
  attached to that buffer. They will not show up in a keymap list taken from an
  empty buffer.
- **`<Space>` on its own opens which-key**, which lists whatever is valid from
  where you are. That is faster than this document for recall — the tables below
  are for learning what exists in the first place.

### Vim essentials

Not exhaustive; `:help index` is. These are the ones worth having in your hands
before the rest of this document is useful.

| Key | Does |
|---|---|
| `h` `j` `k` `l` | left, down, up, right |
| `w` `b` `e` | word forward, word back, end of word |
| `0` `^` `$` | line start, first non-blank, line end |
| `gg` `G` `{n}G` | top, bottom, line n |
| `{` `}` | paragraph back, forward |
| `%` | matching bracket |
| `f{c}` `t{c}` `;` `,` | to char, before char, repeat, repeat back |
| `<C-o>` `<C-i>` | jump back, jump forward |
| `i` `a` `I` `A` `o` `O` | insert, append, line start, line end, open below, open above |
| `d` `c` `y` `p` `P` | delete, change, yank, paste after, paste before |
| `dd` `yy` `cc` | operate on the whole line |
| `x` `r{c}` `~` | delete char, replace char, toggle case |
| `u` `<C-r>` `.` | undo, redo, repeat last change |
| `v` `V` `<C-v>` | visual, visual line, visual block |
| `>` `<` `=` | indent, outdent, auto-indent |
| `/` `?` `n` `N` `*` | search forward, back, next, previous, word under cursor |
| `:%s/old/new/g` | substitute in file |
| `m{a}` `` `{a} `` | set mark, jump to mark |
| `q{a}` `@{a}` `@@` | record macro, play, replay |
| `zz` `zt` `zb` | centre, top, bottom the cursor line |
| `za` `zR` `zM` | toggle fold, open all, close all |

Text objects combine with any operator — `ciw`, `da(`, `yi"`, `vip`:

| Object | Is |
|---|---|
| `iw` / `aw` | word, inner / around |
| `is` / `as` | sentence |
| `ip` / `ap` | paragraph |
| `i(` `i[` `i{` `i<` | inside brackets (`a` variants include them) |
| `i"` `i'` `` i` `` | inside quotes |
| `it` / `at` | inside / around an HTML tag |
| `if` / `af` | inside / around a function (treesitter) |
| `ic` / `ac` | inside / around a class (treesitter) |
| `iu` / `au` | inside / around a function call ("usage") |
| `ih` | a git hunk |

`a` and `i` also take `l` and `n` to reach the *last* or *next* object rather
than the one under the cursor — `cinq` changes the next quoted string, `danf`
deletes the next function.

### Navigation and search

| Key | Does |
|---|---|
| `<leader><space>` | find files (root dir) |
| `<leader>ff` / `<leader>fF` | find files, root dir / cwd |
| `<leader>fg` | find files tracked by git |
| `<leader>fr` / `<leader>fR` | recent files, root dir / cwd |
| `<leader>fb` / `<leader>fB` | buffers / all buffers |
| `<leader>fp` | projects |
| `<leader>fc` | find a config file |
| `<leader>fn` | new file |
| `<leader>fe` / `<leader>e` | explorer (root dir) |
| `<leader>ft` / `<leader>fT` | terminal, root dir / cwd |
| `<C-/>` | terminal (root dir) |
| `<leader>/` `<leader>sg` | grep (root dir) |
| `<leader>sG` `<leader>sW` | grep cwd / selection or word under cursor |
| `<leader>sB` `<leader>sb` | grep open buffers / lines in this buffer |
| `<leader>sR` | resume last picker |
| `<leader>sk` `<leader>sh` `<leader>sC` | keymaps, help, commands |
| `<leader>sm` `<leader>sj` `<leader>s"` | marks, jumps, registers |
| `<leader>sd` `<leader>sD` | diagnostics, workspace / buffer |
| `<leader>sT` `<leader>xt` | todo / fixme comments |
| `<leader>,` `<leader>:` `<leader>s/` | buffers, command history, search history |

### LSP and code

Buffer-local — needs an attached server.

| Key | Does |
|---|---|
| `gd` `gD` | go to definition / declaration |
| `gr` | references |
| `gI` | implementation |
| `gy` | type definition |
| `K` `gK` | hover docs / signature help |
| `gai` `gao` | incoming / outgoing calls |
| `]]` `[[` | next / previous reference |
| `<leader>ca` `<leader>cA` | code action / source action |
| `<leader>cr` | rename symbol |
| `<leader>cf` `<leader>cF` | format / format injected languages |
| `<leader>cd` | line diagnostics |
| `<leader>cl` `<leader>cm` | LSP info, Mason |
| `<leader>cc` `<leader>cC` | run / refresh codelens |
| `<leader>co` | organize imports (Java) |
| `<leader>cxv` `<leader>cxc` `<leader>cxm` | extract variable / constant / method (Java) |
| `<leader>cgs` `<leader>cgS` | go to super / subjects (Java) |
| `<leader>ss` `<leader>sS` | document / workspace symbols |
| `<C-Space>` | expand treesitter selection |

### IDEA layer ★

An IntelliJ vocabulary over the top; LazyVim's own keys still work underneath.
Every key is exactly two characters after the leader, so none is a prefix of
another.

| Key | IntelliJ | Does |
|---|---|---|
| `<leader>ib` | `Ctrl+B` | go to definition |
| `<leader>ig` | `Ctrl+Alt+B` | go to implementation |
| `<leader>it` | `Ctrl+Shift+B` | type definition |
| `<leader>iu` | `Alt+F7` | find usages |
| `<leader>ir` | `Shift+F6` | rename symbol |
| `<leader>ia` | `Alt+Enter` | code action |
| `<leader>ii` | `Alt+Insert` | generate code |
| `<leader>iv` | `Ctrl+Alt+V` | extract variable |
| `<leader>im` | `Ctrl+Alt+M` | extract method |
| `<leader>ic` | `Ctrl+Alt+C` | extract constant |
| `<leader>il` | `Ctrl+Alt+L` | reformat code |
| `<leader>iO` | `Ctrl+Alt+O` | optimize imports |
| `<leader>ih` | `Ctrl+Q` | quick documentation |
| `<leader>ip` | `Ctrl+P` | signature help |
| `<leader>ie` | `Ctrl+F1` | show error |
| `<leader>is` | `Shift Shift` | search everywhere |
| `<leader>if` | `Ctrl+Shift+N` | find file |
| `<leader>iF` | `Ctrl+Shift+F` | find in files |
| `<leader>iA` | `Ctrl+Shift+A` | find action |
| `<leader>iR` | `Ctrl+E` | recent files |
| `<leader>io` | `Ctrl+F12` | file structure |
| `<leader>iT` | `Ctrl+Shift+T` | go to test |
| `<leader>iH` | | git history |
| `<leader>iw` | `Ctrl+W` | expand selection |
| `<leader>iz` | `Ctrl+Shift+F12` | maximize editor |

### Debugging

F-keys mirror IntelliJ. Breakpoints survive a restart, per project.

| Key | IntelliJ | Does |
|---|---|---|
| `<F5>` `<F9>` | `F9` | start / continue |
| `<F8>` | `F8` | step over |
| `<F7>` | `F7` | step into |
| `<S-F8>` | `Shift+F8` | step out |
| `<C-F8>` | `Ctrl+F8` | toggle breakpoint |
| `<C-S-F8>` | `Ctrl+Shift+F8` | conditional breakpoint |
| `<C-F2>` | `Ctrl+F2` | terminate |
| `<leader>db` `<leader>dB` | | toggle / conditional breakpoint |
| `<leader>dL` ★ | | log-message breakpoint (prints, never stops) |
| `<leader>dh` ★ | | hit-count breakpoint |
| `<leader>dx` ★ | | clear all breakpoints |
| `<leader>d?` ★ | | list breakpoints |
| `<leader>dc` `<leader>da` | | run/continue, run with args |
| `<leader>di` `<leader>dO` `<leader>do` | | step into, over, out |
| `<leader>dC` `<leader>dg` | | run to cursor, go to line without executing |
| `<leader>dj` `<leader>dk` | | move down / up the stack |
| `<leader>de` `<leader>dw` | | eval, widgets |
| `<leader>du` `<leader>dr` | | toggle dap UI, toggle REPL |
| `<leader>ds` `<leader>dt` `<leader>dl` | | session, terminate, run last |
| `<leader>td` | | debug nearest test |

### Git and review

| Key | Does |
|---|---|
| `<leader>gg` / `<leader>gG` | lazygit, root dir / cwd |
| `<leader>gs` `<leader>gl` `<leader>gL` | status, log, log (cwd) |
| `<leader>gb` | blame line |
| `<leader>gf` | current file history |
| `<leader>gd` `<leader>gD` | diff hunks / against origin |
| `<leader>gB` `<leader>gY` | open in browser / copy the URL |
| `<leader>gW` ★ | diffview: working tree |
| `<leader>gH` ★ | diffview: file history |
| `<leader>gR` ★ | diffview: branch history |
| `<leader>gQ` ★ | diffview: close |
| `<leader>rr` ★ | **review**: working-tree diff plus diagnostics for exactly the changed files |
| `]h` `[h` | next / previous hunk |
| `]H` `[H` | last / first hunk |
| `<leader>ghs` `<leader>ghr` | stage / reset hunk (works in visual mode too) |
| `<leader>ghS` `<leader>ghR` | stage / reset the whole buffer |
| `<leader>ghu` | undo stage hunk |
| `<leader>ghp` | preview hunk inline |
| `<leader>ghb` `<leader>ghB` | blame line / buffer |
| `<leader>gi` `<leader>gp` `<leader>gr` | GitHub issues, PRs, repos (Octo) |
| `<leader>gI` `<leader>gP` `<leader>gS` | search issues, PRs, anything (Octo) |

### AI

| Key | Does |
|---|---|
| `<M-]>` `<M-[>` | next / previous Copilot suggestion |
| `<leader>ac` | toggle Claude Code |
| `<leader>aC` `<leader>ar` | continue / resume Claude |
| `<leader>af` | focus Claude |
| `<leader>ab` | add the current buffer to Claude's context |
| `<leader>aa` `<leader>ad` | accept / deny a Claude diff |
| `<leader>ao` ★ | CodeCompanion chat |
| `<leader>ai` ★ | CodeCompanion inline |
| `<leader>ak` ★ | CodeCompanion actions |

Copilot suggestions arrive in the same completion menu as LSP results, so
`<CR>` and `<Tab>` accept them like anything else.

### Diagnostics and lists

| Key | Does |
|---|---|
| `<leader>xx` `<leader>xX` | diagnostics, workspace / buffer (Trouble) |
| `<leader>cs` `<leader>cS` | symbols / LSP references (Trouble) |
| `<leader>xL` `<leader>xQ` | location list, quickfix (Trouble) |
| `<leader>xl` `<leader>xq` | location list, quickfix (plain) |
| `<leader>xt` `<leader>xT` | todo comments (Trouble) |
| `]d` `[d` | next / previous diagnostic |
| `]e` `[e` | next / previous error |
| `]w` `[w` | next / previous warning |
| `]D` `[D` | last / first diagnostic in the buffer |
| `]q` `[q` | next / previous quickfix or Trouble item |
| `<C-w>d` | show the diagnostic under the cursor |

### Testing

| Key | Does |
|---|---|
| `<leader>tr` `<leader>tt` `<leader>tT` | run nearest, file, all files |
| `<leader>tl` | run last |
| `<leader>ts` `<leader>to` `<leader>tO` | summary, output, output panel |
| `<leader>tw` | toggle watch |
| `<leader>tS` | stop |
| `<leader>td` | debug nearest |

### Buffers, windows and sessions

| Key | Does |
|---|---|
| `<C-h>` `<C-j>` `<C-k>` `<C-l>` | move between windows |
| `<C-Up>` `<C-Down>` `<C-Left>` `<C-Right>` | resize the window |
| `<C-w>` then a key | window hydra mode (which-key shows the rest) |
| `<leader>bb` | switch to the previously used buffer |
| `]b` `[b` | next / previous buffer |
| `]B` `[B` | move the buffer right / left |
| `<leader>bd` `<leader>bD` | delete buffer / buffer and window |
| `<leader>bo` `<leader>bl` `<leader>br` | delete other / left / right buffers |
| `<leader>bp` `<leader>bP` | pin, delete everything unpinned |
| `<leader>bj` `<leader>bi` | pick a buffer, delete invisible ones |
| `<C-s>` | save |
| `<leader>qq` | quit all |
| `<leader>qs` `<leader>ql` `<leader>qS` | restore session, restore last, pick |
| `<leader>qd` | do not save this session |

### Editing helpers

| Key | Does |
|---|---|
| `gcc` `gc{motion}` | toggle comment (line / over a motion) |
| `gco` `gcO` | add a comment below / above |
| `gsa` `gsd` `gsr` | add / delete / replace a surrounding |
| `gsf` `gsF` `gsh` | find right, find left, highlight a surrounding |
| `<M-j>` `<M-k>` | move the line or selection down / up |
| `]<Space>` `[<Space>` | add a blank line below / above |
| `<leader>p` | yank history |
| `[y` `]y` | cycle forward / backward through yank history after a paste |
| `<Esc>` | clear search highlight |
| `<leader>ur` | redraw, clear highlight, refresh diff |

### UI toggles

All under `<leader>u`; which-key lists them with their current state.

| Key | Toggles |
|---|---|
| `<leader>uz` `<leader>uZ` | zen mode / zoom |
| `<leader>ud` `<leader>uh` | diagnostics / inlay hints |
| `<leader>uf` `<leader>uF` | auto-format, global / this buffer |
| `<leader>ul` `<leader>uL` | line numbers / relative numbers |
| `<leader>uw` `<leader>uc` | wrap / conceal |
| `<leader>us` `<leader>ug` | spelling / indent guides |
| `<leader>ub` `<leader>uC` | dark background / pick a colorscheme |
| `<leader>uT` `<leader>uD` | treesitter highlight / dimming |
| `<leader>uS` `<leader>ua` | smooth scroll / animations |
| `<leader>ue` `<leader>uE` | edgy panels / select an edgy window |
| `<leader>un` | dismiss notifications |
| `<leader>ui` `<leader>uI` | inspect position / inspect tree |

### Commands worth knowing

| Command | Does |
|---|---|
| `:JdkList` ★ | every JDK found, and which one runs jdtls |
| `:IconAudit` ★ | draw every registered glyph, to spot blanks the font lacks |
| `:LazyExtras` | enable or disable LazyVim extras |
| `:Lazy` `:Mason` | plugin and tool managers |
| `:checkhealth vim.lsp` | attached servers and their configuration (`:LspInfo` is gone) |
| `:lua vim.cmd('e ' .. vim.lsp.get_log_path())` | open the LSP log |
| `:ConformInfo` | which formatter runs here and why |
| `:DiffviewOpen` `:Trouble` `:Octo` | diff view, diagnostics list, GitHub |

## Tests

    nvim -l wezterm/tests/run.lua
    nvim -l nvim/tests/run.lua

No dependencies — the harness is 40 lines of Lua and the runner is Neovim.

Changing an icon also means checking it exists in the font:

    pip install fonttools
    python nvim/scripts/verify-glyphs.py

That checks the font's cmap. A codepoint can be present and still render
blank, so `:IconAudit` inside Neovim draws every glyph for a visual pass.
