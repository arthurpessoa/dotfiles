# Dotfiles Installer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the interactive, scope-aware bootstrap that probes a machine, lets you pick what to install from a checklist, resolves each row to a source that works without administrator rights where possible, installs, and links the configs — on Windows, macOS, and Linux.

**Architecture:** `install.ps1` and `install.sh` are thin entry points that parse arguments, dot-source a library, and run four phases: probe, select, install, link. Every phase is a pure function over injected inputs — command existence, the catalog, and the command runner all arrive as parameters — so the whole thing is testable without installing anything. The catalog is data, not code, and exists once per shell with identical rows.

**Tech Stack:** PowerShell 7 with Pester 5, POSIX `sh` with a hand-written assert harness, winget, scoop, brew, apt/dnf/pacman, sdkman, npm.

**Spec:** `docs/specs/2026-08-01-wezterm-dotfiles-design.md`, amended by `docs/specs/2026-08-01-installer-amendments-design.md`

**Depends on:** `docs/plans/2026-08-01-wezterm-config.md`, which creates the repo, the configs, and `README.md`.

## Global Constraints

- Repo root is `~/.dotfiles`. Paths below are relative to it unless absolute.
- Nothing in `install/lib/` may perform an install, write outside a temp directory, or read the real environment at import time. Side effects happen only inside `Invoke-Rows` / `run_rows`, which take the runner as a parameter.
- Resolution **prefers user scope even when administrator rights are available**, so a machine resolves the same whether or not the shell is elevated.
- A row with no viable method is **disabled with its reason shown**, never hidden and never silently skipped.
- A row knows itself by a **list** of commands plus an optional per-method path, and reports `installed`, `partial` or `missing`. A single sentinel command would let a half-installed row claim to be whole.
- A row **succeeds when its checks pass afterwards**, not when its command exits zero. Managers exit non-zero refusing to reinstall what is already present, and a command can exit zero while installing nothing.
- WezTerm is pinned to nightly on every platform: `scoop:versions/wezterm-nightly`, `brew --cask wezterm@nightly`, and the GitHub `nightly` release on Linux.
- `bash` on Windows PATH is **WSL**, not Git Bash. Anything that must run under Git Bash uses the full path `C:\Program Files\Git\bin\bash.exe`.
- sdkman is POSIX-only. On Windows the jvm row falls back to `scoop:java/temurin-lts` when Git Bash is absent.
- The selection loop reads keys from `/dev/tty` in `sh` because `curl | bash` occupies stdin. With no tty, the script exits with a message naming `--all` or `--only`, and never guesses.
- Never delete an existing config directory. Rename to `<name>.bak-<timestamp>`.
- Every task ends with a commit, Conventional Commits, normal prose.

---

## File Structure

| File | Responsibility |
| --- | --- |
| `install.ps1` | Windows entry point. Parses args, dot-sources `install/lib/*.ps1`, runs the four phases. |
| `install.sh` | macOS and Linux entry point. Same shape in POSIX `sh`. |
| `install/lib/args.ps1` / `args.sh` | Command-line parsing. Pure. |
| `install/lib/probe.ps1` / `probe.sh` | OS, arch, privilege, managers. Takes a command-existence probe as a parameter. |
| `install/catalog.psd1` / `catalog.sh` | The rows: id, group, label, checks, and methods per platform, each method carrying an optional check path. Data only. |
| `install/lib/resolver.ps1` / `resolver.sh` | The source ladder, and the row status. Pure over `(row, environment, wingetProbe, commandProbe, pathProbe)`. |
| `install/lib/ui.ps1` / `ui.sh` | Renders the menu to an array of lines, and maps keypresses to state changes. Pure. |
| `install/lib/exec.ps1` / `exec.sh` | Ordered execution, one elevation, failure capture, summary. Runner injected. |
| `install/lib/link.ps1` / `link.sh` | Junctions and symlinks with timestamped backups. |
| `install/tests/*.Tests.ps1` | Pester 5 specs, one per lib file. |
| `install/tests/run.sh` | POSIX harness plus specs, mirroring the Pester cases. |

---

### Task 1: Test scaffolding for both shells

**Files:**
- Create: `install/tests/smoke.Tests.ps1`
- Create: `install/tests/run.sh`
- Create: `install/tests/harness.sh`
- Modify: `README.md` (test section)

**Interfaces:**
- Consumes: nothing.
- Produces: `harness.sh` exporting `it <name> <fn>`, `assert_eq <actual> <expected> [msg]`, `assert_contains <haystack> <needle> [msg]`, `harness_summary` (returns non-zero on failure). Pester specs run with `Invoke-Pester install/tests`.

- [ ] **Step 1: Install Pester 5 without administrator rights**

The bundled Pester on Windows is 3.4.0, whose syntax differs enough to be unusable here.

```powershell
Install-Module Pester -Scope CurrentUser -MinimumVersion 5.5.0 -Force -SkipPublisherCheck
Import-Module Pester -MinimumVersion 5.5.0
(Get-Module Pester).Version
```

Expected: 5.5.0 or newer. `-Scope CurrentUser` keeps it under `~/Documents/PowerShell/Modules`, no elevation.

- [ ] **Step 2: Write the PowerShell smoke spec**

Create `install/tests/smoke.Tests.ps1`:

```powershell
Describe 'harness' {
    It 'runs' {
        1 + 1 | Should -Be 2
    }
}
```

- [ ] **Step 3: Run it**

Run: `Invoke-Pester install/tests -Output Detailed`
Expected: 1 passed, 0 failed.

- [ ] **Step 4: Write the POSIX harness**

Create `install/tests/harness.sh`:

```sh
#!/bin/sh
# Dependency-free assert harness. Source it, call it/assert_*, end with harness_summary.

HARNESS_PASS=0
HARNESS_FAIL=0

it() {
  name="$1"
  shift
  if "$@"; then
    HARNESS_PASS=$((HARNESS_PASS + 1))
    printf '  ok   %s\n' "$name"
  else
    HARNESS_FAIL=$((HARNESS_FAIL + 1))
    printf '  FAIL %s\n' "$name"
  fi
}

assert_eq() {
  if [ "$1" = "$2" ]; then
    return 0
  fi
  printf '       expected [%s], got [%s] %s\n' "$2" "$1" "${3:-}"
  return 1
}

assert_contains() {
  case "$1" in
    *"$2"*) return 0 ;;
  esac
  printf '       [%s] does not contain [%s] %s\n' "$1" "$2" "${3:-}"
  return 1
}

harness_summary() {
  printf '\n%d passed, %d failed\n' "$HARNESS_PASS" "$HARNESS_FAIL"
  [ "$HARNESS_FAIL" -eq 0 ]
}
```

- [ ] **Step 5: Write the POSIX runner with a smoke case**

Create `install/tests/run.sh`:

```sh
#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
. install/tests/harness.sh

echo "harness"
smoke() { assert_eq "$((1 + 1))" "2"; }
it "adds" smoke

harness_summary
```

- [ ] **Step 6: Run it under Git Bash**

Plain `bash` on this machine is WSL, so call Git Bash explicitly:

Run: `& 'C:\Program Files\Git\bin\bash.exe' install/tests/run.sh`
Expected: `ok adds` and `1 passed, 0 failed`, exit 0.

- [ ] **Step 7: Document both runners in the README**

Replace the `## Tests` section of `README.md`:

````markdown
## Tests

WezTerm config, no dependencies:

```
nvim -l wezterm/tests/run.lua
```

Installer, PowerShell (needs Pester 5, installed user-scoped):

```
Invoke-Pester install/tests -Output Detailed
```

Installer, POSIX (no dependencies). On Windows use Git Bash explicitly, since
`bash` on PATH is WSL:

```
sh install/tests/run.sh
```
````

- [ ] **Step 8: Commit**

```bash
git add install/tests README.md
git commit -m "test: add installer test scaffolding for both shells

Pester 5 covers the PowerShell library; the POSIX side uses a 40-line
assert harness so the shell installer needs nothing installed to be
tested. Note that bash on Windows PATH is WSL, so the POSIX suite is
run through Git Bash by full path."
```

---

### Task 2: Argument parsing

**Files:**
- Create: `install/lib/args.ps1`
- Create: `install/lib/args.sh`
- Create: `install/tests/args.Tests.ps1`
- Modify: `install/tests/run.sh`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `Get-InstallerArgs([string[]] $Argv) -> hashtable` with keys `All` (bool), `Only` (string[]), `Yes` (bool), `DryRun` (bool), `Scope` (`'user'|'machine'|$null`), `Manager` (string or `$null`), `Help` (bool). Throws on an unknown flag or a missing value.
  - `parse_args "$@"` setting `ARG_ALL`, `ARG_ONLY` (comma-joined), `ARG_YES`, `ARG_DRY_RUN`, `ARG_SCOPE`, `ARG_MANAGER`, `ARG_HELP`; returns 1 and prints to stderr on an unknown flag.

- [ ] **Step 1: Write the failing PowerShell test**

Create `install/tests/args.Tests.ps1`:

```powershell
BeforeAll {
    . "$PSScriptRoot/../lib/args.ps1"
}

Describe 'Get-InstallerArgs' {
    It 'defaults everything off' {
        $a = Get-InstallerArgs @()
        $a.All      | Should -BeFalse
        $a.DryRun   | Should -BeFalse
        $a.Only     | Should -BeNullOrEmpty
        $a.Scope    | Should -BeNullOrEmpty
    }

    It 'parses the simple switches' {
        $a = Get-InstallerArgs @('--all', '--yes', '--dry-run')
        $a.All    | Should -BeTrue
        $a.Yes    | Should -BeTrue
        $a.DryRun | Should -BeTrue
    }

    It 'splits --only on commas and trims' {
        $a = Get-InstallerArgs @('--only', 'git, wezterm ,nvim')
        $a.Only | Should -Be @('git', 'wezterm', 'nvim')
    }

    It 'reads --scope and --manager' {
        $a = Get-InstallerArgs @('--scope', 'machine', '--manager', 'scoop')
        $a.Scope   | Should -Be 'machine'
        $a.Manager | Should -Be 'scoop'
    }

    It 'rejects an unknown flag' {
        { Get-InstallerArgs @('--wat') } | Should -Throw '*unknown option*'
    }

    It 'rejects a flag missing its value' {
        { Get-InstallerArgs @('--only') } | Should -Throw '*requires a value*'
    }

    It 'rejects an invalid scope' {
        { Get-InstallerArgs @('--scope', 'sideways') } | Should -Throw '*user*machine*'
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Invoke-Pester install/tests/args.Tests.ps1 -Output Detailed`
Expected: FAIL — the file `install/lib/args.ps1` does not exist.

- [ ] **Step 3: Write args.ps1**

Create `install/lib/args.ps1`:

```powershell
function Get-InstallerArgs {
    param([string[]] $Argv = @())

    $result = @{
        All = $false; Only = @(); Yes = $false
        DryRun = $false; Scope = $null; Manager = $null; Help = $false
    }

    $index = 0
    while ($index -lt $Argv.Count) {
        $flag = $Argv[$index]

        $needsValue = $flag -in @('--only', '--scope', '--manager')
        if ($needsValue -and $index + 1 -ge $Argv.Count) {
            throw "$flag requires a value"
        }

        switch ($flag) {
            '--all'     { $result.All = $true }
            '--yes'     { $result.Yes = $true }
            '--dry-run' { $result.DryRun = $true }
            '--help'    { $result.Help = $true }
            '-h'        { $result.Help = $true }
            '--only' {
                $index++
                $result.Only = $Argv[$index].Split(',') |
                    ForEach-Object { $_.Trim() } |
                    Where-Object { $_ -ne '' }
            }
            '--scope' {
                $index++
                $value = $Argv[$index]
                if ($value -notin @('user', 'machine')) {
                    throw "--scope must be user or machine, got '$value'"
                }
                $result.Scope = $value
            }
            '--manager' {
                $index++
                $result.Manager = $Argv[$index]
            }
            default { throw "unknown option '$flag'" }
        }
        $index++
    }

    return $result
}
```

- [ ] **Step 4: Run it to verify it passes**

Run: `Invoke-Pester install/tests/args.Tests.ps1 -Output Detailed`
Expected: 7 passed.

- [ ] **Step 5: Write args.sh**

Create `install/lib/args.sh`:

```sh
#!/bin/sh
# Sets ARG_* variables from the command line. Returns 1 on a bad option.

parse_args() {
  ARG_ALL=0; ARG_ONLY=""; ARG_YES=0
  ARG_DRY_RUN=0; ARG_SCOPE=""; ARG_MANAGER=""; ARG_HELP=0

  while [ $# -gt 0 ]; do
    case "$1" in
      --all)     ARG_ALL=1 ;;
      --yes)     ARG_YES=1 ;;
      --dry-run) ARG_DRY_RUN=1 ;;
      --help|-h) ARG_HELP=1 ;;
      --only)
        [ $# -ge 2 ] || { echo "--only requires a value" >&2; return 1; }
        shift
        ARG_ONLY=$(printf '%s' "$1" | tr -d ' ')
        ;;
      --scope)
        [ $# -ge 2 ] || { echo "--scope requires a value" >&2; return 1; }
        shift
        case "$1" in
          user|machine) ARG_SCOPE="$1" ;;
          *) echo "--scope must be user or machine, got '$1'" >&2; return 1 ;;
        esac
        ;;
      --manager)
        [ $# -ge 2 ] || { echo "--manager requires a value" >&2; return 1; }
        shift
        ARG_MANAGER="$1"
        ;;
      *) echo "unknown option '$1'" >&2; return 1 ;;
    esac
    shift
  done
  return 0
}
```

- [ ] **Step 6: Add the mirrored POSIX cases**

Insert into `install/tests/run.sh` before `harness_summary`:

```sh
. install/lib/args.sh

echo "parse_args"

t_defaults() { parse_args && assert_eq "$ARG_ALL" "0"; }
it "defaults everything off" t_defaults

t_switches() { parse_args --all --yes --dry-run && assert_eq "$ARG_ALL$ARG_YES$ARG_DRY_RUN" "111"; }
it "parses the simple switches" t_switches

t_only() { parse_args --only "git, wezterm ,nvim" && assert_eq "$ARG_ONLY" "git,wezterm,nvim"; }
it "splits --only on commas and trims" t_only

t_scope() { parse_args --scope machine && assert_eq "$ARG_SCOPE" "machine"; }
it "reads --scope" t_scope

t_unknown() { ! parse_args --wat 2>/dev/null; }
it "rejects an unknown flag" t_unknown

t_missing() { ! parse_args --only 2>/dev/null; }
it "rejects a flag missing its value" t_missing

t_badscope() { ! parse_args --scope sideways 2>/dev/null; }
it "rejects an invalid scope" t_badscope
```

- [ ] **Step 7: Run the POSIX suite**

Run: `& 'C:\Program Files\Git\bin\bash.exe' install/tests/run.sh`
Expected: 8 passed, 0 failed.

- [ ] **Step 8: Commit**

```bash
git add install/lib/args.ps1 install/lib/args.sh install/tests
git commit -m "feat(install): parse command line arguments in both shells

Supports --all, --only, --yes, --dry-run, --scope, --manager, and
--help. Unknown flags, missing values, and an invalid scope all fail
loudly rather than being ignored, since a silently dropped --only would
install the wrong set."
```

---

### Task 3: The catalog

**Files:**
- Create: `install/catalog.psd1`
- Create: `install/catalog.sh`
- Create: `install/lib/catalog.ps1`
- Create: `install/tests/catalog.Tests.ps1`
- Modify: `install/tests/run.sh`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `Import-Catalog([string] $Path) -> object[]`. Each row: `Id` (string, unique), `Group` (string), `Label` (string), `Checks` (string[] — every command the row provides; empty for a row that installs no command), `Methods` (array). Each method: `Platform` (`windows|macos|linux`), `Manager` (string), `Scope` (`user|machine`), `Install` (string), `CheckPath` (string or `$null` — a path whose existence means this method's work is done), `Note` (string or `$null`).
  - `Test-Catalog($rows) -> string[]` — a list of problems, empty when valid. A row with an empty `Checks` and a method without a `CheckPath` is a problem: nothing could ever tell whether it is installed.
  - `catalog_rows` in `catalog.sh` emitting one `id|group|label|checks` line per row, where `checks` is a space-separated command list and may be empty; and `catalog_methods <id>` emitting `platform|manager|scope|checkpath|install` lines, where `checkpath` may be empty.

A row carries a *list* of checks rather than one command because a row can
install more than one thing. `toolbelt` installs nine tools; behind a single
sentinel command, a machine with ripgrep but without bat reports the row
installed and never gets bat. The list makes a partial install visible.

`CheckPath` sits on the method rather than the row because only the method knows
where its manager puts things: the Nerd Font lands in `~/Library/Fonts` under
brew and `~/.local/share/fonts` under the GitHub download.

- [ ] **Step 1: Write the failing test**

Create `install/tests/catalog.Tests.ps1`:

```powershell
BeforeAll {
    . "$PSScriptRoot/../lib/catalog.ps1"
    $script:Rows = Import-Catalog "$PSScriptRoot/../catalog.psd1"
}

Describe 'catalog' {
    It 'validates clean' {
        Test-Catalog $script:Rows | Should -BeNullOrEmpty
    }

    It 'has unique ids' {
        ($script:Rows.Id | Sort-Object -Unique).Count | Should -Be $script:Rows.Count
    }

    It 'lists the package managers first so they install before their dependents' {
        $script:Rows[0].Group | Should -Be 'PACKAGE MANAGERS'
        $linkIndex = [array]::IndexOf($script:Rows.Id, 'dotfiles')
        $linkIndex | Should -Be ($script:Rows.Count - 1)
    }

    It 'pins wezterm to nightly on every platform' {
        $wez = $script:Rows | Where-Object Id -eq 'wezterm'
        foreach ($m in $wez.Methods) {
            $m.Install | Should -Match 'nightly'
        }
    }

    It 'gives every row at least one method per platform it supports' {
        foreach ($row in $script:Rows) {
            $row.Methods.Count | Should -BeGreaterThan 0 -Because $row.Id
        }
    }

    It 'marks docker desktop on windows as machine scope' {
        $docker = $script:Rows | Where-Object Id -eq 'docker-desktop'
        $win = $docker.Methods | Where-Object Platform -eq 'windows'
        $win.Scope | Should -Be 'machine'
    }

    It 'gives the jvm row a windows fallback that is not sdkman' {
        $jvm = $script:Rows | Where-Object Id -eq 'jvm'
        $win = @($jvm.Methods | Where-Object Platform -eq 'windows')
        $win.Count | Should -BeGreaterThan 1
        ($win | Where-Object Manager -eq 'scoop').Install | Should -Match 'temurin'
    }

    It 'can tell whether every row is installed' {
        foreach ($row in $script:Rows) {
            $byPath = @($row.Methods | Where-Object { $_.CheckPath }).Count -eq @($row.Methods).Count
            ($row.Checks.Count -gt 0 -or $byPath) | Should -BeTrue -Because $row.Id
        }
    }

    It 'lists every command the toolbelt installs, not just the first' {
        $belt = $script:Rows | Where-Object Id -eq 'toolbelt'
        $belt.Checks | Should -Contain 'rg'
        $belt.Checks | Should -Contain 'bat'
        $belt.Checks.Count | Should -Be 9
    }

    It 'does not let the two docker rows answer for each other' {
        $desktop = $script:Rows | Where-Object Id -eq 'docker-desktop'
        $cli = $script:Rows | Where-Object Id -eq 'docker-cli'
        $shared = @($desktop.Checks | Where-Object { $_ -in $cli.Checks })
        $shared.Count | Should -Be 0
    }

    It 'checks sdkman by its init script rather than a command' {
        # sdk is a shell function sourced into bash, never a binary on PATH.
        $sdkman = $script:Rows | Where-Object Id -eq 'sdkman'
        $sdkman.Checks.Count | Should -Be 0
        foreach ($m in $sdkman.Methods) { $m.CheckPath | Should -Match 'sdkman-init' }
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Invoke-Pester install/tests/catalog.Tests.ps1 -Output Detailed`
Expected: FAIL — `install/lib/catalog.ps1` does not exist.

- [ ] **Step 3: Write the catalog data**

Create `install/catalog.psd1`. Rows are ordered: managers, core, toolbelt, toolchains, containers and AI, dotfiles.

```powershell
@{
    Rows = @(
        @{ Id='scoop'; Group='PACKAGE MANAGERS'; Label='scoop'; Checks=@('scoop')
           Methods=@(
             @{ Platform='windows'; Manager='self'; Scope='user'
                Install='Invoke-RestMethod get.scoop.sh | Invoke-Expression' }
           ) }

        @{ Id='winget'; Group='PACKAGE MANAGERS'; Label='winget'; Checks=@('winget')
           Methods=@(
             @{ Platform='windows'; Manager='self'; Scope='machine'
                Install='Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe'
                Note='ships with Windows 11; reinstall needs the Store' }
           ) }

        @{ Id='brew'; Group='PACKAGE MANAGERS'; Label='homebrew'; Checks=@('brew')
           Methods=@(
             @{ Platform='macos'; Manager='self'; Scope='user'
                Install='/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"' }
             @{ Platform='linux'; Manager='self'; Scope='user'
                Install='/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"' }
           ) }

        # sdk is a shell function, not a binary, so this row is known by its
        # init script alone.
        @{ Id='sdkman'; Group='PACKAGE MANAGERS'; Label='sdkman'; Checks=@()
           Methods=@(
             @{ Platform='macos'; Manager='self'; Scope='user'
                CheckPath='$HOME/.sdkman/bin/sdkman-init.sh'
                Install='curl -s "https://get.sdkman.io" | bash' }
             @{ Platform='linux'; Manager='self'; Scope='user'
                CheckPath='$HOME/.sdkman/bin/sdkman-init.sh'
                Install='curl -s "https://get.sdkman.io" | bash' }
             @{ Platform='windows'; Manager='gitbash'; Scope='user'
                CheckPath='$HOME/.sdkman/bin/sdkman-init.sh'
                Install='& "C:\Program Files\Git\bin\bash.exe" -lc ''curl -s "https://get.sdkman.io" | bash'''
                Note='requires Git Bash' }
           ) }

        @{ Id='git'; Group='CORE'; Label='git'; Checks=@('git')
           Methods=@(
             @{ Platform='windows'; Manager='winget'; Scope='user'; Install='winget install --scope user -e --id Git.Git' }
             @{ Platform='windows'; Manager='scoop';  Scope='user'; Install='scoop install main/git' }
             @{ Platform='macos';   Manager='brew';   Scope='user'; Install='brew install git' }
             @{ Platform='linux';   Manager='brew';   Scope='user'; Install='brew install git' }
             @{ Platform='linux';   Manager='system'; Scope='machine'; Install='git' }
           ) }

        @{ Id='wezterm'; Group='CORE'; Label='wezterm (nightly)'; Checks=@('wezterm')
           Methods=@(
             @{ Platform='windows'; Manager='scoop'; Scope='user'
                Install='scoop bucket add versions; scoop install versions/wezterm-nightly' }
             @{ Platform='macos'; Manager='brew'; Scope='user'
                Install='brew install --cask wezterm@nightly --no-quarantine' }
             @{ Platform='linux'; Manager='github'; Scope='user'
                Install='curl -fsSL -o "$HOME/.local/bin/wezterm" https://github.com/wez/wezterm/releases/download/nightly/WezTerm-nightly-Ubuntu20.04.AppImage && chmod +x "$HOME/.local/bin/wezterm"' }
             @{ Platform='linux'; Manager='system'; Scope='machine'
                Install='wezterm-nightly' }
           ) }

        @{ Id='neovim'; Group='CORE'; Label='neovim'; Checks=@('nvim')
           Methods=@(
             @{ Platform='windows'; Manager='scoop';  Scope='user'; Install='scoop install main/neovim' }
             @{ Platform='windows'; Manager='winget'; Scope='machine'; Install='winget install --scope machine -e --id Neovim.Neovim' }
             @{ Platform='macos';   Manager='brew';   Scope='user'; Install='brew install neovim' }
             @{ Platform='linux';   Manager='brew';   Scope='user'; Install='brew install neovim' }
           ) }

        # A font installs no command, and each manager drops it somewhere else.
        @{ Id='nerdfont'; Group='CORE'; Label='JetBrainsMono Nerd Font'; Checks=@()
           Methods=@(
             @{ Platform='windows'; Manager='scoop'; Scope='user'
                CheckPath='$HOME\scoop\apps\JetBrainsMono-NF\current'
                Install='scoop bucket add nerd-fonts; scoop install nerd-fonts/JetBrainsMono-NF' }
             @{ Platform='macos'; Manager='brew'; Scope='user'
                CheckPath='$HOME/Library/Fonts/JetBrainsMonoNerdFont-Regular.ttf'
                Install='brew install --cask font-jetbrains-mono-nerd-font' }
             @{ Platform='linux'; Manager='github'; Scope='user'
                CheckPath='$HOME/.local/share/fonts/JetBrainsMonoNerdFont-Regular.ttf'
                Install='mkdir -p "$HOME/.local/share/fonts" && curl -fsSL -o /tmp/jbm.zip https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip && unzip -o /tmp/jbm.zip -d "$HOME/.local/share/fonts" && fc-cache -f' }
           ) }

        @{ Id='toolbelt'; Group='TOOLBELT'; Label='ripgrep fd fzf bat eza zoxide lazygit gh jq'
           Checks=@('rg', 'fd', 'fzf', 'bat', 'eza', 'zoxide', 'lazygit', 'gh', 'jq')
           Methods=@(
             @{ Platform='windows'; Manager='scoop'; Scope='user'
                Install='scoop bucket add extras; scoop install main/ripgrep main/fd main/fzf main/bat main/eza main/zoxide extras/lazygit main/gh main/jq' }
             @{ Platform='macos'; Manager='brew'; Scope='user'
                Install='brew install ripgrep fd fzf bat eza zoxide lazygit gh jq' }
             @{ Platform='linux'; Manager='brew'; Scope='user'
                Install='brew install ripgrep fd fzf bat eza zoxide lazygit gh jq' }
           ) }

        @{ Id='rust'; Group='TOOLCHAINS'; Label='rust'; Checks=@('cargo', 'rustc')
           Methods=@(
             @{ Platform='windows'; Manager='scoop'; Scope='user'; Install='scoop install main/rustup' }
             @{ Platform='macos';   Manager='self';  Scope='user'; Install='curl --proto ''=https'' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y' }
             @{ Platform='linux';   Manager='self';  Scope='user'; Install='curl --proto ''=https'' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y' }
           ) }

        # The row installs fnm; node itself arrives through `fnm install`, so
        # fnm is what tells you the row is done.
        @{ Id='node'; Group='TOOLCHAINS'; Label='node (fnm)'; Checks=@('fnm')
           Methods=@(
             @{ Platform='windows'; Manager='winget'; Scope='user'; Install='winget install --scope user -e --id Schniz.fnm' }
             @{ Platform='windows'; Manager='scoop';  Scope='user'; Install='scoop install main/fnm' }
             @{ Platform='macos';   Manager='brew';   Scope='user'; Install='brew install fnm' }
             @{ Platform='linux';   Manager='brew';   Scope='user'; Install='brew install fnm' }
           ) }

        @{ Id='python'; Group='TOOLCHAINS'; Label='python (uv)'; Checks=@('uv')
           Methods=@(
             @{ Platform='windows'; Manager='winget'; Scope='user'; Install='winget install --scope user -e --id astral-sh.uv' }
             @{ Platform='windows'; Manager='scoop';  Scope='user'; Install='scoop install main/uv' }
             @{ Platform='macos';   Manager='brew';   Scope='user'; Install='brew install uv' }
             @{ Platform='linux';   Manager='brew';   Scope='user'; Install='brew install uv' }
           ) }

        @{ Id='jvm'; Group='TOOLCHAINS'; Label='jvm'; Checks=@('java')
           Methods=@(
             @{ Platform='windows'; Manager='gitbash'; Scope='user'
                Install='& "C:\Program Files\Git\bin\bash.exe" -lc ''source "$HOME/.sdkman/bin/sdkman-init.sh" && sdk install java'''
                Note='requires sdkman under Git Bash' }
             @{ Platform='windows'; Manager='scoop'; Scope='user'
                Install='scoop bucket add java; scoop install java/temurin-lts-jdk' }
             @{ Platform='macos'; Manager='sdkman'; Scope='user'
                Install='source "$HOME/.sdkman/bin/sdkman-init.sh" && sdk install java' }
             @{ Platform='linux'; Manager='sdkman'; Scope='user'
                Install='source "$HOME/.sdkman/bin/sdkman-init.sh" && sdk install java' }
           ) }

        # Both docker rows would answer to the `docker` command, so the desktop
        # row is known by the application it installs instead.
        @{ Id='docker-desktop'; Group='CONTAINERS + AI'; Label='docker desktop'; Checks=@()
           Methods=@(
             @{ Platform='windows'; Manager='winget'; Scope='machine'
                CheckPath='C:\Program Files\Docker\Docker\Docker Desktop.exe'
                Install='winget install --scope machine -e --id Docker.DockerDesktop' }
             @{ Platform='macos'; Manager='brew'; Scope='user'
                CheckPath='/Applications/Docker.app'
                Install='brew install --cask docker' }
             @{ Platform='linux'; Manager='system'; Scope='machine'
                CheckPath='/opt/docker-desktop'
                Install='docker.io' }
           ) }

        @{ Id='docker-cli'; Group='CONTAINERS + AI'; Label='docker cli'; Checks=@('docker')
           Methods=@(
             @{ Platform='windows'; Manager='scoop'; Scope='user'; Install='scoop install main/docker' }
             @{ Platform='macos';   Manager='brew';  Scope='user'; Install='brew install docker' }
             @{ Platform='linux';   Manager='brew';  Scope='user'; Install='brew install docker' }
           ) }

        @{ Id='ai-clis'; Group='CONTAINERS + AI'; Label='claude-code'; Checks=@('claude')
           Methods=@(
             @{ Platform='windows'; Manager='npm'; Scope='user'; Install='npm install -g @anthropic-ai/claude-code' }
             @{ Platform='macos';   Manager='npm'; Scope='user'; Install='npm install -g @anthropic-ai/claude-code' }
             @{ Platform='linux';   Manager='npm'; Scope='user'; Install='npm install -g @anthropic-ai/claude-code' }
           ) }

        @{ Id='dotfiles'; Group='DOTFILES'; Label='clone + link configs'; Checks=@()
           Methods=@(
             @{ Platform='windows'; Manager='builtin'; Scope='user'
                CheckPath='$HOME\.config\wezterm'; Install='<link>' }
             @{ Platform='macos';   Manager='builtin'; Scope='user'
                CheckPath='$HOME/.config/wezterm'; Install='<link>' }
             @{ Platform='linux';   Manager='builtin'; Scope='user'
                CheckPath='$HOME/.config/wezterm'; Install='<link>' }
           ) }
    )
}
```

- [ ] **Step 4: Write the catalog loader**

Create `install/lib/catalog.ps1`:

```powershell
function Import-Catalog {
    param([Parameter(Mandatory)] [string] $Path)
    $data = Import-PowerShellDataFile -Path $Path
    return @($data.Rows | ForEach-Object {
        $row = [pscustomobject] $_
        if (-not $row.PSObject.Properties['Checks']) {
            $row | Add-Member -NotePropertyName Checks -NotePropertyValue @()
        }
        $row.Checks = @($row.Checks)
        $row
    })
}

function Test-Catalog {
    param([Parameter(Mandatory)] $Rows)

    $problems = @()
    $seen = @{}

    foreach ($row in $Rows) {
        foreach ($field in 'Id', 'Group', 'Label', 'Checks', 'Methods') {
            if (-not $row.PSObject.Properties[$field]) {
                $problems += "row is missing $field"
            }
        }
        if ($seen.ContainsKey($row.Id)) { $problems += "duplicate id '$($row.Id)'" }
        $seen[$row.Id] = $true

        if (@($row.Methods).Count -eq 0) { $problems += "'$($row.Id)' has no methods" }

        foreach ($method in $row.Methods) {
            if ($method.Platform -notin 'windows', 'macos', 'linux') {
                $problems += "'$($row.Id)' has method with bad platform '$($method.Platform)'"
            }
            if ($method.Scope -notin 'user', 'machine') {
                $problems += "'$($row.Id)' has method with bad scope '$($method.Scope)'"
            }
            if ([string]::IsNullOrWhiteSpace($method.Install)) {
                $problems += "'$($row.Id)' has method with no install command"
            }
            # A row with no commands has to be knowable some other way, or the
            # menu can never report it as anything but missing.
            if (@($row.Checks).Count -eq 0 -and [string]::IsNullOrWhiteSpace($method.CheckPath)) {
                $problems += "'$($row.Id)' has no checks and its $($method.Platform) method has no CheckPath"
            }
        }
    }

    return $problems
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `Invoke-Pester install/tests/catalog.Tests.ps1 -Output Detailed`
Expected: 11 passed.

- [ ] **Step 6: Write catalog.sh with the same rows**

Create `install/catalog.sh`. It carries the macOS and Linux methods only — the
Windows rows are unreachable from `sh`. The fourth field of a row is its command
list, space separated and possibly empty; the fourth field of a method is its
`CheckPath`, also possibly empty.

```sh
#!/bin/sh
# id|group|label|checks
catalog_rows() {
  cat <<'ROWS'
brew|PACKAGE MANAGERS|homebrew|brew
sdkman|PACKAGE MANAGERS|sdkman|
git|CORE|git|git
wezterm|CORE|wezterm (nightly)|wezterm
neovim|CORE|neovim|nvim
nerdfont|CORE|JetBrainsMono Nerd Font|
toolbelt|TOOLBELT|ripgrep fd fzf bat eza zoxide lazygit gh jq|rg fd fzf bat eza zoxide lazygit gh jq
rust|TOOLCHAINS|rust|cargo rustc
node|TOOLCHAINS|node (fnm)|fnm
python|TOOLCHAINS|python (uv)|uv
jvm|TOOLCHAINS|jvm|java
docker-desktop|CONTAINERS + AI|docker desktop|
docker-cli|CONTAINERS + AI|docker cli|docker
ai-clis|CONTAINERS + AI|claude-code|claude
dotfiles|DOTFILES|clone + link configs|
ROWS
}

# platform|manager|scope|checkpath|install
catalog_methods() {
  case "$1" in
    brew) cat <<'M'
macos|self|user||/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
linux|self|user||/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
M
      ;;
    sdkman) cat <<'M'
macos|self|user|$HOME/.sdkman/bin/sdkman-init.sh|curl -s "https://get.sdkman.io" | bash
linux|self|user|$HOME/.sdkman/bin/sdkman-init.sh|curl -s "https://get.sdkman.io" | bash
M
      ;;
    git) cat <<'M'
macos|brew|user||brew install git
linux|brew|user||brew install git
linux|system|machine||git
M
      ;;
    wezterm) cat <<'M'
macos|brew|user||brew install --cask wezterm@nightly --no-quarantine
linux|github|user||curl -fsSL -o "$HOME/.local/bin/wezterm" https://github.com/wez/wezterm/releases/download/nightly/WezTerm-nightly-Ubuntu20.04.AppImage && chmod +x "$HOME/.local/bin/wezterm"
linux|system|machine||wezterm-nightly
M
      ;;
    neovim) cat <<'M'
macos|brew|user||brew install neovim
linux|brew|user||brew install neovim
M
      ;;
    nerdfont) cat <<'M'
macos|brew|user|$HOME/Library/Fonts/JetBrainsMonoNerdFont-Regular.ttf|brew install --cask font-jetbrains-mono-nerd-font
linux|github|user|$HOME/.local/share/fonts/JetBrainsMonoNerdFont-Regular.ttf|mkdir -p "$HOME/.local/share/fonts" && curl -fsSL -o /tmp/jbm.zip https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip && unzip -o /tmp/jbm.zip -d "$HOME/.local/share/fonts" && fc-cache -f
M
      ;;
    toolbelt) cat <<'M'
macos|brew|user||brew install ripgrep fd fzf bat eza zoxide lazygit gh jq
linux|brew|user||brew install ripgrep fd fzf bat eza zoxide lazygit gh jq
M
      ;;
    rust) cat <<'M'
macos|self|user||curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
linux|self|user||curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
M
      ;;
    node) cat <<'M'
macos|brew|user||brew install fnm
linux|brew|user||brew install fnm
M
      ;;
    python) cat <<'M'
macos|brew|user||brew install uv
linux|brew|user||brew install uv
M
      ;;
    jvm) cat <<'M'
macos|sdkman|user||source "$HOME/.sdkman/bin/sdkman-init.sh" && sdk install java
linux|sdkman|user||source "$HOME/.sdkman/bin/sdkman-init.sh" && sdk install java
M
      ;;
    docker-desktop) cat <<'M'
macos|brew|user|/Applications/Docker.app|brew install --cask docker
linux|system|machine|/opt/docker-desktop|docker.io
M
      ;;
    docker-cli) cat <<'M'
macos|brew|user||brew install docker
linux|brew|user||brew install docker
M
      ;;
    ai-clis) cat <<'M'
macos|npm|user||npm install -g @anthropic-ai/claude-code
linux|npm|user||npm install -g @anthropic-ai/claude-code
M
      ;;
    dotfiles) cat <<'M'
macos|builtin|user|$HOME/.config/wezterm|<link>
linux|builtin|user|$HOME/.config/wezterm|<link>
M
      ;;
    *) return 1 ;;
  esac
}
```

- [ ] **Step 7: Add POSIX catalog cases**

Insert into `install/tests/run.sh` before `harness_summary`:

```sh
. install/catalog.sh

echo "catalog"

t_rows() { assert_eq "$(catalog_rows | wc -l | tr -d ' ')" "15"; }
it "lists every row" t_rows

t_order() { assert_contains "$(catalog_rows | head -1)" "PACKAGE MANAGERS"; }
it "puts package managers first" t_order

t_last() { assert_contains "$(catalog_rows | tail -1)" "dotfiles"; }
it "puts linking last" t_last

t_nightly() { assert_contains "$(catalog_methods wezterm)" "nightly"; }
it "pins wezterm to nightly" t_nightly

t_every_row_has_methods() {
  catalog_rows | while IFS='|' read -r id _ _ _; do
    catalog_methods "$id" >/dev/null || return 1
  done
}
it "gives every row methods" t_every_row_has_methods

t_toolbelt_lists_all() {
  checks=$(catalog_rows | awk -F'|' '$1 == "toolbelt" { print $4 }')
  assert_contains "$checks" "bat" &&
    assert_eq "$(printf '%s\n' "$checks" | wc -w | tr -d ' ')" "9"
}
it "lists every command the toolbelt installs" t_toolbelt_lists_all

t_checkable() {
  catalog_rows | while IFS='|' read -r id _ _ checks; do
    [ -n "$checks" ] && continue
    catalog_methods "$id" | while IFS='|' read -r _ _ _ checkpath _; do
      [ -n "$checkpath" ] || { echo "$id has neither checks nor a checkpath" >&2; return 1; }
    done || return 1
  done
}
it "can tell whether every row is installed" t_checkable

t_docker_rows_differ() {
  desktop=$(catalog_rows | awk -F'|' '$1 == "docker-desktop" { print $4 }')
  cli=$(catalog_rows | awk -F'|' '$1 == "docker-cli" { print $4 }')
  assert_eq "$desktop" "" && assert_eq "$cli" "docker"
}
it "does not let the two docker rows answer for each other" t_docker_rows_differ
```

- [ ] **Step 8: Run both suites**

Run: `Invoke-Pester install/tests -Output Detailed`
Run: `& 'C:\Program Files\Git\bin\bash.exe' install/tests/run.sh`
Expected: both green.

- [ ] **Step 9: Commit**

```bash
git add install/catalog.psd1 install/catalog.sh install/lib/catalog.ps1 install/tests
git commit -m "feat(install): add the package catalog

Rows are data, one per tool, each listing per-platform methods with
their manager and scope. Package managers come first so a bare machine
can bootstrap one, and linking comes last. WezTerm is pinned to nightly
on all three platforms; the jvm row prefers sdkman and falls back to
scoop's temurin on Windows.

A row carries every command it provides rather than one sentinel, so a
half-installed toolbelt cannot report itself complete, and the rows that
install no command at all -- the font, sdkman's shell function, Docker
Desktop, the links themselves -- are known by a path on each method."
```

---

### Task 4: Environment probe

**Files:**
- Create: `install/lib/probe.ps1`
- Create: `install/lib/probe.sh`
- Create: `install/tests/probe.Tests.ps1`
- Modify: `install/tests/run.sh`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `Get-Environment([scriptblock] $CommandProbe, [scriptblock] $PrivilegeProbe) -> hashtable` with `Os`, `Arch`, `Privilege` (`elevated|can-elevate|standard`), `Managers` (string[]).
  - `Test-CommandExists([string] $Name)` — the real probe, used as the default.
  - `Get-PrivilegeState()` — the real probe: elevated when the process is in the Administrators role; `can-elevate` when the current user is a member of the local Administrators group; `standard` otherwise.
  - `detect_environment` in `probe.sh` setting `ENV_OS`, `ENV_ARCH`, `ENV_PRIVILEGE`, `ENV_MANAGERS`, using `command -v` and `id -u` / `sudo -n true`.

- [ ] **Step 1: Write the failing test**

Create `install/tests/probe.Tests.ps1`:

```powershell
BeforeAll {
    . "$PSScriptRoot/../lib/probe.ps1"
}

Describe 'Get-Environment' {
    It 'lists only the managers that exist' {
        $probe = { param($name) $name -in @('scoop', 'winget') }
        $env = Get-Environment -CommandProbe $probe -PrivilegeProbe { 'standard' }
        $env.Managers | Should -Contain 'scoop'
        $env.Managers | Should -Contain 'winget'
        $env.Managers | Should -Not -Contain 'choco'
    }

    It 'reports the privilege the probe returns' {
        $env = Get-Environment -CommandProbe { $false } -PrivilegeProbe { 'can-elevate' }
        $env.Privilege | Should -Be 'can-elevate'
    }

    It 'reports windows when run from powershell on windows' {
        $env = Get-Environment -CommandProbe { $false } -PrivilegeProbe { 'standard' }
        $env.Os | Should -Be 'windows'
    }

    It 'never returns a null manager list' {
        $env = Get-Environment -CommandProbe { $false } -PrivilegeProbe { 'standard' }
        $env.Managers | Should -Not -BeNullOrEmpty -Because 'npm and self are always present as pseudo-managers'
    }
}

Describe 'Get-PrivilegeState' {
    It 'returns one of the three known states' {
        Get-PrivilegeState | Should -BeIn @('elevated', 'can-elevate', 'standard')
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Invoke-Pester install/tests/probe.Tests.ps1 -Output Detailed`
Expected: FAIL — `install/lib/probe.ps1` does not exist.

- [ ] **Step 3: Write probe.ps1**

Create `install/lib/probe.ps1`:

```powershell
$script:KnownManagers = @('winget', 'scoop', 'choco', 'brew', 'npm', 'sdk', 'apt', 'dnf', 'pacman')

function Test-CommandExists {
    param([Parameter(Mandatory)] [string] $Name)
    return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Get-PrivilegeState {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal] $identity
    $adminRole = [Security.Principal.WindowsBuiltInRole]::Administrator

    if ($principal.IsInRole($adminRole)) { return 'elevated' }

    $adminSid = [Security.Principal.SecurityIdentifier]'S-1-5-32-544'
    foreach ($group in $identity.Groups) {
        if ($group -eq $adminSid) { return 'can-elevate' }
    }

    return 'standard'
}

function Get-Environment {
    param(
        [scriptblock] $CommandProbe = { param($name) Test-CommandExists $name },
        [scriptblock] $PrivilegeProbe = { Get-PrivilegeState }
    )

    $managers = @('self', 'builtin')
    foreach ($manager in $script:KnownManagers) {
        if (& $CommandProbe $manager) { $managers += $manager }
    }

    if (Test-Path 'C:\Program Files\Git\bin\bash.exe') { $managers += 'gitbash' }

    return @{
        Os        = 'windows'
        Arch      = $env:PROCESSOR_ARCHITECTURE
        Privilege = (& $PrivilegeProbe)
        Managers  = $managers
    }
}
```

- [ ] **Step 4: Run it to verify it passes**

Run: `Invoke-Pester install/tests/probe.Tests.ps1 -Output Detailed`
Expected: 5 passed.

- [ ] **Step 5: Write probe.sh**

Create `install/lib/probe.sh`:

```sh
#!/bin/sh
# Sets ENV_OS, ENV_ARCH, ENV_PRIVILEGE, ENV_MANAGERS.
# PROBE_CMD may be overridden by tests; it must echo 0 when a command exists.

probe_command() {
  if [ -n "${PROBE_CMD:-}" ]; then
    "$PROBE_CMD" "$1"
    return $?
  fi
  command -v "$1" >/dev/null 2>&1
}

probe_privilege() {
  if [ -n "${PROBE_PRIV:-}" ]; then
    printf '%s' "$PROBE_PRIV"
    return 0
  fi
  if [ "$(id -u)" -eq 0 ]; then
    printf 'elevated'
  elif sudo -n true 2>/dev/null; then
    printf 'can-elevate'
  elif probe_command sudo; then
    printf 'can-elevate'
  else
    printf 'standard'
  fi
}

detect_environment() {
  case "$(uname -s)" in
    Darwin) ENV_OS=macos ;;
    Linux)  ENV_OS=linux ;;
    *)      ENV_OS=linux ;;
  esac

  ENV_ARCH=$(uname -m)
  ENV_PRIVILEGE=$(probe_privilege)

  ENV_MANAGERS="self builtin"
  for m in brew npm sdk apt dnf pacman github system; do
    if probe_command "$m"; then
      ENV_MANAGERS="$ENV_MANAGERS $m"
    fi
  done
  # github and system are pseudo-managers: always available.
  case "$ENV_MANAGERS" in
    *github*) ;;
    *) ENV_MANAGERS="$ENV_MANAGERS github" ;;
  esac
}
```

- [ ] **Step 6: Add POSIX probe cases**

Insert into `install/tests/run.sh` before `harness_summary`:

```sh
. install/lib/probe.sh

echo "detect_environment"

fake_has_brew() { [ "$1" = "brew" ]; }

t_managers() {
  PROBE_CMD=fake_has_brew PROBE_PRIV=standard detect_environment
  assert_contains "$ENV_MANAGERS" "brew"
}
it "lists a manager that exists" t_managers

t_no_ghost_managers() {
  PROBE_CMD=fake_has_brew PROBE_PRIV=standard detect_environment
  case "$ENV_MANAGERS" in *pacman*) return 1 ;; esac
  return 0
}
it "omits managers that do not exist" t_no_ghost_managers

t_priv() {
  PROBE_CMD=fake_has_brew PROBE_PRIV=can-elevate detect_environment
  assert_eq "$ENV_PRIVILEGE" "can-elevate"
}
it "reports the probed privilege" t_priv

t_os() {
  PROBE_CMD=fake_has_brew PROBE_PRIV=standard detect_environment
  case "$ENV_OS" in macos|linux) return 0 ;; *) return 1 ;; esac
}
it "detects a known os" t_os
```

- [ ] **Step 7: Run both suites**

Run: `Invoke-Pester install/tests -Output Detailed` and `& 'C:\Program Files\Git\bin\bash.exe' install/tests/run.sh`
Expected: both green.

- [ ] **Step 8: Commit**

```bash
git add install/lib/probe.ps1 install/lib/probe.sh install/tests
git commit -m "feat(install): probe the machine before drawing anything

Privilege has three outcomes rather than two: already elevated, able to
elevate, and a standard user with no path to administrator. The last
one is what disables rows, so it is detected explicitly through group
membership rather than inferred from a failed command."
```

---

### Task 5: Source resolver

**Files:**
- Create: `install/lib/resolver.ps1`
- Create: `install/lib/resolver.sh`
- Create: `install/tests/resolver.Tests.ps1`
- Modify: `install/tests/run.sh`

**Interfaces:**
- Consumes: catalog rows from Task 3, environment from Task 4.
- Produces:
  - `Resolve-Source($Row, $Environment, [scriptblock] $WingetScopeProbe) -> hashtable` with `Method` (the chosen method or `$null`), `Alternatives` (array), `Reason` (string, set only when `Method` is `$null`).
  - `Test-WingetUserScope([string] $Id) -> bool` — the real probe, running `winget show --scope user --id <id>` and returning false when the output reports no applicable installer.
  - `Expand-InstallPath([string] $Path) -> string` — replaces `$HOME` in a catalog path with the real profile directory. Catalog paths are single-quoted data, so nothing expands until asked.
  - `Test-RowStatus($Row, $Method, [scriptblock] $InstalledProbe, [scriptblock] $PathProbe) -> hashtable` with `Status` (`installed|partial|missing`) and `Missing` (string[] — the checks that did not pass). Task 7 calls this again after an install to decide whether the row succeeded.
  - `Get-CatalogView($Rows, $Environment, $WingetScopeProbe, [scriptblock] $InstalledProbe, [scriptblock] $PathProbe) -> object[]` — each row gains `Resolved`, `Alternatives`, `Reason`, `Status`, `Missing`, `Selected`.
  - `resolve_source <id>` in `resolver.sh` printing `platform|manager|scope|checkpath|install` for the winner, or nothing plus a reason in `RESOLVE_REASON`.
  - `row_status <checks> <checkpath>` in `resolver.sh` printing `installed`, `partial` or `missing`, and setting `ROW_MISSING` to the space-separated checks that failed.

`Status` replaces the earlier `Installed` boolean. A row that provides nine
commands can be neither plainly installed nor plainly missing, and the case
matters: partial is the state a machine sits in after the catalog grows a tool.

- [ ] **Step 1: Write the failing test**

Create `install/tests/resolver.Tests.ps1`:

```powershell
BeforeAll {
    . "$PSScriptRoot/../lib/catalog.ps1"
    . "$PSScriptRoot/../lib/resolver.ps1"
    $script:Rows = Import-Catalog "$PSScriptRoot/../catalog.psd1"

    function Get-Row([string] $id) { $script:Rows | Where-Object Id -eq $id }

    $script:StandardUser = @{
        Os = 'windows'; Arch = 'AMD64'; Privilege = 'standard'
        Managers = @('self', 'builtin', 'scoop', 'winget', 'npm', 'gitbash')
    }
    $script:AdminUser = @{
        Os = 'windows'; Arch = 'AMD64'; Privilege = 'elevated'
        Managers = @('self', 'builtin', 'scoop', 'winget', 'npm', 'gitbash')
    }
    $script:ScoopOnly = @{
        Os = 'windows'; Arch = 'AMD64'; Privilege = 'standard'
        Managers = @('self', 'builtin', 'scoop')
    }

    $script:NothingInstalled = { $false }
    $script:NoPaths = { $false }
}

Describe 'Resolve-Source' {
    It 'takes winget user scope when the manifest declares it' {
        $result = Resolve-Source (Get-Row 'git') $script:StandardUser { $true }
        $result.Method.Manager | Should -Be 'winget'
        $result.Method.Scope   | Should -Be 'user'
    }

    It 'falls through to scoop when winget has no user scope' {
        $result = Resolve-Source (Get-Row 'git') $script:StandardUser { $false }
        $result.Method.Manager | Should -Be 'scoop'
    }

    It 'still prefers user scope when running elevated' {
        $result = Resolve-Source (Get-Row 'neovim') $script:AdminUser { $false }
        $result.Method.Manager | Should -Be 'scoop'
        $result.Method.Scope   | Should -Be 'user'
    }

    It 'uses machine scope only when no user scope method is viable' {
        $result = Resolve-Source (Get-Row 'docker-desktop') $script:AdminUser { $false }
        $result.Method.Scope | Should -Be 'machine'
    }

    It 'disables an admin-only row for a standard user and says why' {
        $result = Resolve-Source (Get-Row 'docker-desktop') $script:StandardUser { $false }
        $result.Method | Should -BeNullOrEmpty
        $result.Reason | Should -Match 'admin'
    }

    It 'disables a row whose managers are all missing' {
        $env = @{ Os = 'windows'; Arch = 'AMD64'; Privilege = 'standard'; Managers = @('self') }
        $result = Resolve-Source (Get-Row 'toolbelt') $env { $false }
        $result.Method | Should -BeNullOrEmpty
        $result.Reason | Should -Match 'no package manager'
    }

    It 'picks scoop temurin for the jvm when git bash is absent' {
        $result = Resolve-Source (Get-Row 'jvm') $script:ScoopOnly { $false }
        $result.Method.Manager | Should -Be 'scoop'
        $result.Method.Install | Should -Match 'temurin'
    }

    It 'prefers sdkman for the jvm when git bash is present' {
        $result = Resolve-Source (Get-Row 'jvm') $script:StandardUser { $false }
        $result.Method.Manager | Should -Be 'gitbash'
    }

    It 'always resolves wezterm to a nightly source' {
        $result = Resolve-Source (Get-Row 'wezterm') $script:StandardUser { $false }
        $result.Method.Install | Should -Match 'nightly'
    }

    It 'offers the losers as alternatives' {
        $result = Resolve-Source (Get-Row 'git') $script:StandardUser { $true }
        $result.Alternatives.Count | Should -BeGreaterThan 0
        $result.Alternatives | Should -Not -Contain $result.Method
    }
}

Describe 'Test-RowStatus' {
    It 'calls a row installed when every check passes' {
        $status = Test-RowStatus (Get-Row 'git') $null { $true } $script:NoPaths
        $status.Status | Should -Be 'installed'
        $status.Missing | Should -BeNullOrEmpty
    }

    It 'calls a row partial when only some checks pass' {
        $probe = { param($check) $check -eq 'rg' }
        $status = Test-RowStatus (Get-Row 'toolbelt') $null $probe $script:NoPaths
        $status.Status | Should -Be 'partial'
        $status.Missing | Should -Contain 'bat'
        $status.Missing | Should -Not -Contain 'rg'
    }

    It 'calls a row missing when nothing passes' {
        $status = Test-RowStatus (Get-Row 'toolbelt') $null $script:NothingInstalled $script:NoPaths
        $status.Status | Should -Be 'missing'
        $status.Missing.Count | Should -Be 9
    }

    It 'reads a path for a row that installs no command' {
        $row = Get-Row 'dotfiles'
        $method = $row.Methods | Where-Object Platform -eq 'windows'
        $status = Test-RowStatus $row $method $script:NothingInstalled { $true }
        $status.Status | Should -Be 'installed'
    }

    It 'reports a path row as missing when the path is absent' {
        $row = Get-Row 'nerdfont'
        $method = $row.Methods | Where-Object Platform -eq 'windows'
        $status = Test-RowStatus $row $method $script:NothingInstalled { $false }
        $status.Status | Should -Be 'missing'
    }

    It 'expands $HOME in a catalog path before probing it' {
        $seen = $null
        $row = Get-Row 'sdkman'
        $method = $row.Methods | Where-Object Platform -eq 'windows'
        Test-RowStatus $row $method $script:NothingInstalled { param($p) $script:seen = $p; $true } | Out-Null
        $script:seen | Should -Not -Match '\$HOME'
        $script:seen | Should -Match 'sdkman-init'
    }
}

Describe 'Get-CatalogView' {
    It 'marks an installed row and leaves it deselected' {
        $view = Get-CatalogView $script:Rows $script:StandardUser { $false } { param($check) $check -eq 'git' } $script:NoPaths
        $git = $view | Where-Object Id -eq 'git'
        $git.Status   | Should -Be 'installed'
        $git.Selected | Should -BeFalse
    }

    It 'preselects a viable, uninstalled row' {
        $view = Get-CatalogView $script:Rows $script:StandardUser { $false } $script:NothingInstalled $script:NoPaths
        $wez = $view | Where-Object Id -eq 'wezterm'
        $wez.Selected | Should -BeTrue
    }

    It 'preselects a partial row, because that is where the work is' {
        $view = Get-CatalogView $script:Rows $script:StandardUser { $false } { param($check) $check -eq 'rg' } $script:NoPaths
        $belt = $view | Where-Object Id -eq 'toolbelt'
        $belt.Status   | Should -Be 'partial'
        $belt.Selected | Should -BeTrue
    }

    It 'never selects a disabled row' {
        $view = Get-CatalogView $script:Rows $script:StandardUser { $false } $script:NothingInstalled $script:NoPaths
        $docker = $view | Where-Object Id -eq 'docker-desktop'
        $docker.Selected | Should -BeFalse
        $docker.Reason   | Should -Not -BeNullOrEmpty
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Invoke-Pester install/tests/resolver.Tests.ps1 -Output Detailed`
Expected: FAIL — `install/lib/resolver.ps1` does not exist.

- [ ] **Step 3: Write resolver.ps1**

Create `install/lib/resolver.ps1`:

```powershell
function Test-WingetUserScope {
    param([Parameter(Mandatory)] [string] $Id)
    $output = (winget show --scope user --id $Id --disable-interactivity 2>&1 | Out-String)
    return $output -notmatch 'No applicable|not find|No package'
}

function Get-WingetId {
    param([Parameter(Mandatory)] [string] $Install)
    if ($Install -match '--id\s+(\S+)') { return $Matches[1] }
    return $null
}

function Expand-InstallPath {
    param([string] $Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $Path }
    return $Path.Replace('$HOME', [Environment]::GetFolderPath('UserProfile'))
}

function Resolve-Source {
    param(
        [Parameter(Mandatory)] $Row,
        [Parameter(Mandatory)] $Environment,
        [scriptblock] $WingetScopeProbe = { param($id) Test-WingetUserScope $id }
    )

    $forPlatform = @($Row.Methods | Where-Object { $_.Platform -eq $Environment.Os })
    if ($forPlatform.Count -eq 0) {
        return @{ Method = $null; Alternatives = @(); Reason = "not available on $($Environment.Os)" }
    }

    $viable = @()
    foreach ($method in $forPlatform) {
        if ($method.Manager -notin $Environment.Managers) { continue }

        if ($method.Manager -eq 'winget' -and $method.Scope -eq 'user') {
            $id = Get-WingetId $method.Install
            if ($id -and -not (& $WingetScopeProbe $id)) { continue }
        }

        if ($method.Scope -eq 'machine' -and $Environment.Privilege -eq 'standard') { continue }

        $viable += $method
    }

    if ($viable.Count -eq 0) {
        $anyMachine = @($forPlatform | Where-Object Scope -eq 'machine').Count -gt 0
        $reason = if ($anyMachine -and $Environment.Privilege -eq 'standard') {
            'needs admin'
        } else {
            'no package manager available for this row'
        }
        return @{ Method = $null; Alternatives = @(); Reason = $reason }
    }

    # User scope always wins, regardless of the current privilege level, so a
    # machine resolves identically whether or not the shell happens to be elevated.
    $ordered = @($viable | Where-Object Scope -eq 'user') + @($viable | Where-Object Scope -eq 'machine')

    return @{
        Method = $ordered[0]
        Alternatives = @($ordered | Select-Object -Skip 1)
        Reason = $null
    }
}

function Test-RowStatus {
    param(
        [Parameter(Mandatory)] $Row,
        $Method,
        [scriptblock] $InstalledProbe = { param($check) $check -and (Test-CommandExists $check) },
        [scriptblock] $PathProbe = { param($path) Test-Path -LiteralPath $path }
    )

    $missing = @()
    $total = 0

    foreach ($check in @($Row.Checks)) {
        $total++
        if (-not (& $InstalledProbe $check)) { $missing += $check }
    }

    if ($Method -and -not [string]::IsNullOrWhiteSpace($Method.CheckPath)) {
        $total++
        $path = Expand-InstallPath $Method.CheckPath
        if (-not (& $PathProbe $path)) { $missing += $path }
    }

    # Nothing to go on. Treated as missing so the row is still offered, never
    # as installed, which would silently drop it.
    if ($total -eq 0) { return @{ Status = 'missing'; Missing = @() } }

    if ($missing.Count -eq 0)      { return @{ Status = 'installed'; Missing = @() } }
    if ($missing.Count -lt $total) { return @{ Status = 'partial'; Missing = $missing } }
    return @{ Status = 'missing'; Missing = $missing }
}

function Get-CatalogView {
    param(
        [Parameter(Mandatory)] $Rows,
        [Parameter(Mandatory)] $Environment,
        [scriptblock] $WingetScopeProbe = { param($id) Test-WingetUserScope $id },
        [scriptblock] $InstalledProbe = { param($check) $check -and (Test-CommandExists $check) },
        [scriptblock] $PathProbe = { param($path) Test-Path -LiteralPath $path }
    )

    return @($Rows | ForEach-Object {
        $resolution = Resolve-Source $_ $Environment $WingetScopeProbe
        $status = Test-RowStatus $_ $resolution.Method $InstalledProbe $PathProbe

        [pscustomobject] @{
            Id           = $_.Id
            Group        = $_.Group
            Label        = $_.Label
            Checks       = $_.Checks
            Resolved     = $resolution.Method
            Alternatives = $resolution.Alternatives
            Reason       = $resolution.Reason
            Status       = $status.Status
            Missing      = $status.Missing
            Selected     = ($status.Status -ne 'installed') -and ($null -ne $resolution.Method)
        }
    })
}
```

- [ ] **Step 4: Run it to verify it passes**

Run: `Invoke-Pester install/tests/resolver.Tests.ps1 -Output Detailed`
Expected: 20 passed.

- [ ] **Step 5: Write resolver.sh**

Create `install/lib/resolver.sh`:

```sh
#!/bin/sh
# resolve_source <id> -> prints platform|manager|scope|checkpath|install of the
# winner. On failure prints nothing and sets RESOLVE_REASON.

resolve_source() {
  id="$1"
  RESOLVE_REASON=""
  user_pick=""
  machine_pick=""
  saw_machine=0
  saw_platform=0

  while IFS='|' read -r platform manager scope checkpath install; do
    [ "$platform" = "$ENV_OS" ] || continue
    saw_platform=1
    [ "$scope" = "machine" ] && saw_machine=1

    case " $ENV_MANAGERS " in
      *" $manager "*) ;;
      *) continue ;;
    esac

    if [ "$scope" = "machine" ] && [ "$ENV_PRIVILEGE" = "standard" ]; then
      continue
    fi

    if [ "$scope" = "user" ] && [ -z "$user_pick" ]; then
      user_pick="$platform|$manager|$scope|$checkpath|$install"
    elif [ "$scope" = "machine" ] && [ -z "$machine_pick" ]; then
      machine_pick="$platform|$manager|$scope|$checkpath|$install"
    fi
  done <<EOF
$(catalog_methods "$id")
EOF

  if [ "$saw_platform" -eq 0 ]; then
    RESOLVE_REASON="not available on $ENV_OS"
    return 1
  fi

  if [ -n "$user_pick" ]; then
    printf '%s\n' "$user_pick"
    return 0
  fi

  if [ -n "$machine_pick" ]; then
    printf '%s\n' "$machine_pick"
    return 0
  fi

  if [ "$saw_machine" -eq 1 ] && [ "$ENV_PRIVILEGE" = "standard" ]; then
    RESOLVE_REASON="needs sudo"
  else
    RESOLVE_REASON="no package manager available for this row"
  fi
  return 1
}

# Catalog paths carry a literal $HOME so the data file stays inert. This is the
# one place it expands.
expand_path() {
  eval "printf '%s' \"$1\""
}

# row_status <checks> <checkpath> -> prints installed|partial|missing and sets
# ROW_MISSING to the checks that did not pass. The command prober is
# ROW_CHECK_CMD so tests can replace it; it defaults to command -v.
ROW_CHECK_CMD="command -v"
ROW_CHECK_PATH="test -e"

row_status() {
  checks="$1"
  checkpath="$2"
  ROW_MISSING=""
  total=0
  missing=0

  for check in $checks; do
    total=$((total + 1))
    if ! $ROW_CHECK_CMD "$check" >/dev/null 2>&1; then
      missing=$((missing + 1))
      ROW_MISSING="${ROW_MISSING}${ROW_MISSING:+ }$check"
    fi
  done

  if [ -n "$checkpath" ]; then
    total=$((total + 1))
    expanded=$(expand_path "$checkpath")
    if ! $ROW_CHECK_PATH "$expanded" 2>/dev/null; then
      missing=$((missing + 1))
      ROW_MISSING="${ROW_MISSING}${ROW_MISSING:+ }$expanded"
    fi
  fi

  if [ "$total" -eq 0 ]; then printf 'missing\n'; return 0; fi
  if [ "$missing" -eq 0 ]; then printf 'installed\n'; return 0; fi
  if [ "$missing" -lt "$total" ]; then printf 'partial\n'; return 0; fi
  printf 'missing\n'
}
```

- [ ] **Step 6: Add POSIX resolver cases**

Insert into `install/tests/run.sh` before `harness_summary`:

```sh
. install/lib/resolver.sh

echo "resolve_source"

setup_linux_brew() {
  ENV_OS=linux
  ENV_PRIVILEGE=standard
  ENV_MANAGERS="self builtin brew npm github"
}

t_prefers_brew() {
  setup_linux_brew
  assert_contains "$(resolve_source git)" "brew"
}
it "prefers brew for git on linux" t_prefers_brew

t_nightly_linux() {
  setup_linux_brew
  assert_contains "$(resolve_source wezterm)" "nightly"
}
it "resolves wezterm to a nightly source" t_nightly_linux

t_needs_sudo() {
  ENV_OS=linux
  ENV_PRIVILEGE=standard
  ENV_MANAGERS="self builtin"
  ! resolve_source docker-desktop >/dev/null 2>&1 && assert_contains "$RESOLVE_REASON" "sudo"
}
it "disables an admin-only row for a standard user" t_needs_sudo

t_user_scope_wins_when_root() {
  ENV_OS=linux
  ENV_PRIVILEGE=elevated
  ENV_MANAGERS="self builtin brew system"
  assert_contains "$(resolve_source git)" "brew"
}
it "still prefers user scope when running as root" t_user_scope_wins_when_root

echo "row_status"

# Stand-ins for the real probes: rg is the only command present and no path is.
fake_check() { [ "$1" = "rg" ]; }
fake_path_yes() { true; }
fake_path_no() { false; }

t_status_installed() {
  ROW_CHECK_CMD=fake_check
  assert_eq "$(row_status 'rg' '')" "installed"
}
it "calls a row installed when every check passes" t_status_installed

t_status_partial() {
  ROW_CHECK_CMD=fake_check
  result=$(row_status 'rg fd bat' '')
  assert_eq "$result" "partial" && assert_contains "$ROW_MISSING" "bat"
}
it "calls a half-installed row partial" t_status_partial

t_status_missing() {
  ROW_CHECK_CMD=fake_check
  assert_eq "$(row_status 'fd bat' '')" "missing"
}
it "calls a row missing when nothing passes" t_status_missing

t_status_path() {
  ROW_CHECK_CMD=fake_check
  ROW_CHECK_PATH=fake_path_yes
  assert_eq "$(row_status '' '$HOME/.config/wezterm')" "installed"
  ROW_CHECK_PATH="test -e"
}
it "reads a path for a row that installs no command" t_status_path

t_status_expands_home() {
  ROW_CHECK_CMD=fake_check
  ROW_CHECK_PATH=fake_path_no
  row_status '' '$HOME/.sdkman/bin/sdkman-init.sh' >/dev/null
  ROW_CHECK_PATH="test -e"
  case "$ROW_MISSING" in
    *'$HOME'*) return 1 ;;
    *sdkman-init*) return 0 ;;
    *) return 1 ;;
  esac
}
it "expands HOME before probing a path" t_status_expands_home
```

- [ ] **Step 7: Run both suites**

Run: `Invoke-Pester install/tests -Output Detailed` and `& 'C:\Program Files\Git\bin\bash.exe' install/tests/run.sh`
Expected: both green.

- [ ] **Step 8: Commit**

```bash
git add install/lib/resolver.ps1 install/lib/resolver.sh install/tests
git commit -m "feat(install): resolve each row to a source that fits the machine

The ladder tries winget user scope, then scoop, then the tool's own
installer, then winget machine scope, and disables the row with a
reason when nothing fits. winget's user scope is probed at run time
because it is per-manifest, not per-package-manager. User scope wins
even when elevated so a machine resolves identically either way.

A row reports installed, partial or missing rather than a boolean. A row
that provides nine commands is regularly neither wholly present nor
wholly absent, and partial is the state a machine sits in whenever the
catalog grows a tool. Partial rows arrive selected: they are the rows
with work left."
```

---

### Task 6: Menu rendering and key handling

**Files:**
- Create: `install/lib/ui.ps1`
- Create: `install/lib/ui.sh`
- Create: `install/tests/ui.Tests.ps1`
- Modify: `install/tests/run.sh`

**Interfaces:**
- Consumes: the catalog view from Task 5 — `Id`, `Group`, `Label`, `Resolved`, `Alternatives`, `Reason`, `Status`, `Missing`, `Selected`.
- Produces:
  - `Format-Menu($View, $Environment, [int] $Cursor) -> string[]` — the whole screen as lines. Renders nothing itself.
  - `Invoke-MenuKey($View, [int] $Cursor, [string] $Key) -> hashtable` with `View`, `Cursor`, `Done`, `Cancelled`.
  - `render_menu <state> <os> <arch> <privilege> <managers> <cursor>` and `menu_key <state> <cursor> <key>` in `ui.sh`.

**The POSIX state record.** One line per row, twelve fields, `install` last
because it is the only field that may itself contain a `|`:

```
selected|id|group|label|manager|scope|reason|status|missing|checks|checkpath|install
```

`status` is `installed`, `partial` or `missing`. `missing` is the space-separated
list of checks that did not pass, so the menu can say how much of a row is left
without probing anything. `checks` and `checkpath` are carried so that Task 7 can
re-probe a row after installing it without going back to the catalog. Every
function that reads a record reads all twelve fields: reading fewer silently
lands the remainder in the last variable, which is how a record read one field
short turns `status` into `missing|brew install …`.

- [ ] **Step 1: Write the failing test**

Create `install/tests/ui.Tests.ps1`:

```powershell
BeforeAll {
    . "$PSScriptRoot/../lib/ui.ps1"

    function New-View {
        @(
            [pscustomobject] @{ Id='scoop'; Group='PACKAGE MANAGERS'; Label='scoop'
                Checks=@('scoop')
                Resolved=@{Manager='self';Scope='user'}; Alternatives=@(); Reason=$null
                Status='installed'; Missing=@(); Selected=$false }
            [pscustomobject] @{ Id='wezterm'; Group='CORE'; Label='wezterm (nightly)'
                Checks=@('wezterm')
                Resolved=@{Manager='scoop';Scope='user'}; Alternatives=@(@{Manager='winget';Scope='machine'})
                Reason=$null; Status='missing'; Missing=@('wezterm'); Selected=$true }
            [pscustomobject] @{ Id='toolbelt'; Group='TOOLBELT'; Label='ripgrep fd fzf bat eza zoxide lazygit gh jq'
                Checks=@('rg','fd','fzf','bat','eza','zoxide','lazygit','gh','jq')
                Resolved=@{Manager='scoop';Scope='user'}; Alternatives=@(); Reason=$null
                Status='partial'; Missing=@('bat','eza'); Selected=$true }
            [pscustomobject] @{ Id='docker-desktop'; Group='CONTAINERS + AI'; Label='docker desktop'
                Checks=@()
                Resolved=$null; Alternatives=@(); Reason='needs admin'
                Status='missing'; Missing=@('docker'); Selected=$false }
        )
    }

    $script:Env = @{ Os='windows'; Arch='AMD64'; Privilege='standard'; Managers=@('scoop','winget') }
}

Describe 'Format-Menu' {
    It 'shows the privilege and manager summary' {
        $lines = Format-Menu (New-View) $script:Env 0
        ($lines -join "`n") | Should -Match 'standard'
        ($lines -join "`n") | Should -Match 'scoop'
    }

    It 'banners the disabled rows with the count' {
        $lines = Format-Menu (New-View) $script:Env 0
        ($lines -join "`n") | Should -Match '1 row disabled'
        ($lines -join "`n") | Should -Match 'needs admin'
    }

    It 'renders an installed row as already installed and not as a checkbox' {
        $line = (Format-Menu (New-View) $script:Env 0) | Where-Object { $_ -match 'scoop\s' } | Select-Object -First 1
        $line | Should -Match 'already installed'
    }

    It 'says how much of a partial row is missing' {
        $line = (Format-Menu (New-View) $script:Env 0) | Where-Object { $_ -match 'ripgrep' } | Select-Object -First 1
        $line | Should -Match '2 of 9 missing'
    }

    It 'marks the selected row with an x and the disabled row with a dash' {
        $text = (Format-Menu (New-View) $script:Env 0) -join "`n"
        $text | Should -Match '\[x\].*wezterm'
        $text | Should -Match '\[-\].*docker desktop'
    }

    It 'shows the resolved source on the row' {
        $text = (Format-Menu (New-View) $script:Env 0) -join "`n"
        $text | Should -Match 'wezterm.*scoop'
    }

    It 'prints group headings once each' {
        $lines = Format-Menu (New-View) $script:Env 0
        @($lines | Where-Object { $_ -eq 'CORE' }).Count | Should -Be 1
    }

    It 'includes the key legend' {
        $text = (Format-Menu (New-View) $script:Env 0) -join "`n"
        foreach ($k in 'space', 'all', 'source', 'dry-run') { $text | Should -Match $k }
    }
}

Describe 'Invoke-MenuKey' {
    It 'toggles the row under the cursor with space' {
        $view = New-View
        $result = Invoke-MenuKey $view 1 'space'
        $result.View[1].Selected | Should -BeFalse
    }

    It 'refuses to toggle a disabled row' {
        $view = New-View
        $result = Invoke-MenuKey $view 3 'space'
        $result.View[3].Selected | Should -BeFalse
    }

    It 'refuses to toggle an installed row' {
        $view = New-View
        $result = Invoke-MenuKey $view 0 'space'
        $result.View[0].Selected | Should -BeFalse
    }

    It 'lets a partial row be toggled, because it still has work' {
        $view = New-View
        $result = Invoke-MenuKey $view 2 'space'
        $result.View[2].Selected | Should -BeFalse
        $again = Invoke-MenuKey $result.View 2 'space'
        $again.View[2].Selected | Should -BeTrue
    }

    It 'selects every enabled row that is not already installed with a' {
        $view = New-View
        $result = Invoke-MenuKey $view 0 'a'
        $result.View[1].Selected | Should -BeTrue
        $result.View[2].Selected | Should -BeTrue
        $result.View[3].Selected | Should -BeFalse
    }

    It 'clears everything with n' {
        $view = New-View
        $result = Invoke-MenuKey $view 0 'n'
        @($result.View | Where-Object Selected).Count | Should -Be 0
    }

    It 'cycles the source with s' {
        $view = New-View
        $result = Invoke-MenuKey $view 1 's'
        $result.View[1].Resolved.Manager | Should -Be 'winget'
    }

    It 'wraps the cursor at both ends' {
        (Invoke-MenuKey (New-View) 0 'up').Cursor   | Should -Be 3
        (Invoke-MenuKey (New-View) 3 'down').Cursor | Should -Be 0
    }

    It 'finishes on enter and cancels on q' {
        (Invoke-MenuKey (New-View) 0 'enter').Done      | Should -BeTrue
        (Invoke-MenuKey (New-View) 0 'q').Cancelled     | Should -BeTrue
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Invoke-Pester install/tests/ui.Tests.ps1 -Output Detailed`
Expected: FAIL — `install/lib/ui.ps1` does not exist.

- [ ] **Step 3: Write ui.ps1**

Create `install/lib/ui.ps1`:

```powershell
function Format-Menu {
    param(
        [Parameter(Mandatory)] $View,
        [Parameter(Mandatory)] $Environment,
        [int] $Cursor = 0
    )

    $lines = @()
    $lines += " dotfiles installer                        $($Environment.Os) · $($Environment.Arch)"
    $lines += " privilege  $($Environment.Privilege)"
    $lines += " managers   $($Environment.Managers -join '  ')"
    $lines += ''

    $disabled = @($View | Where-Object { $null -eq $_.Resolved })
    if ($disabled.Count -gt 0) {
        $detail = ($disabled | ForEach-Object { "$($_.Label) ($($_.Reason))" }) -join ', '
        $noun = if ($disabled.Count -eq 1) { 'row' } else { 'rows' }
        $lines += " $($disabled.Count) $noun disabled: $detail"
        $lines += ''
    }

    $group = $null
    for ($i = 0; $i -lt $View.Count; $i++) {
        $row = $View[$i]
        if ($row.Group -ne $group) {
            $group = $row.Group
            $lines += $group
        }

        $marker = if ($row.Status -eq 'installed') { '✓' }
                  elseif ($null -eq $row.Resolved) { '-' }
                  elseif ($row.Selected) { 'x' }
                  else { ' ' }

        $pointer = if ($i -eq $Cursor) { '>' } else { ' ' }

        # A partial row says how much of it is missing. "2 of 9 missing" is the
        # difference between a row worth re-running and one already done.
        $detail = if ($row.Status -eq 'installed') { 'already installed' }
                  elseif ($null -eq $row.Resolved) { "$($row.Reason) — disabled" }
                  elseif ($row.Status -eq 'partial') {
                      $total = @($row.Checks).Count
                      if ($row.Resolved.CheckPath) { $total++ }
                      "$($row.Resolved.Manager) · $($row.Resolved.Scope) · $(@($row.Missing).Count) of $total missing"
                  }
                  else { "$($row.Resolved.Manager) · $($row.Resolved.Scope)" }

        $lines += ('{0} [{1}] {2,-34} {3}' -f $pointer, $marker, $row.Label, $detail)
    }

    $lines += ''
    $lines += ' space toggle · a all · n none · g group · s cycle source · d dry-run · enter install · q quit'
    return $lines
}

function Invoke-MenuKey {
    param(
        [Parameter(Mandatory)] $View,
        [int] $Cursor,
        [Parameter(Mandatory)] [string] $Key
    )

    $result = @{ View = $View; Cursor = $Cursor; Done = $false; Cancelled = $false }
    # Partial rows are selectable: they are the rows with work left.
    $canSelect = { param($row) ($row.Status -ne 'installed') -and ($null -ne $row.Resolved) }

    switch ($Key) {
        'up'    { $result.Cursor = if ($Cursor -le 0) { $View.Count - 1 } else { $Cursor - 1 } }
        'down'  { $result.Cursor = if ($Cursor -ge $View.Count - 1) { 0 } else { $Cursor + 1 } }
        'enter' { $result.Done = $true }
        'q'     { $result.Cancelled = $true }
        'space' {
            $row = $View[$Cursor]
            if (& $canSelect $row) { $row.Selected = -not $row.Selected }
        }
        'a' {
            foreach ($row in $View) { if (& $canSelect $row) { $row.Selected = $true } }
        }
        'n' {
            foreach ($row in $View) { $row.Selected = $false }
        }
        'g' {
            $group = $View[$Cursor].Group
            $rows = @($View | Where-Object { $_.Group -eq $group -and (& $canSelect $_) })
            $target = -not ($rows | Where-Object Selected | Select-Object -First 1)
            foreach ($row in $rows) { $row.Selected = [bool] $target }
        }
        's' {
            $row = $View[$Cursor]
            if ($row.Alternatives.Count -gt 0) {
                $next = $row.Alternatives[0]
                $rest = @($row.Alternatives | Select-Object -Skip 1) + @($row.Resolved)
                $row.Resolved = $next
                $row.Alternatives = $rest
            }
        }
    }

    return $result
}
```

`Format-Menu` counts a row's checks from what the view already carries, so the
renderer never reaches back into the catalog for them.

- [ ] **Step 4: Run it to verify it passes**

Run: `Invoke-Pester install/tests/ui.Tests.ps1 -Output Detailed`
Expected: 17 passed.

- [ ] **Step 5: Write ui.sh**

Create `install/lib/ui.sh`. The state is a newline-separated string of the
twelve-field records described above, which keeps it assignable from a subshell.

```sh
#!/bin/sh
# render_menu <state> <os> <arch> <privilege> <managers> <cursor>

render_menu() {
  state="$1"; os="$2"; arch="$3"; priv="$4"; managers="$5"; cursor="$6"

  printf ' dotfiles installer                        %s · %s\n' "$os" "$arch"
  printf ' privilege  %s\n' "$priv"
  printf ' managers   %s\n\n' "$managers"

  disabled=$(printf '%s\n' "$state" | awk -F'|' '$7 != "" { print }')
  if [ -n "$disabled" ]; then
    count=$(printf '%s\n' "$disabled" | wc -l | tr -d ' ')
    detail=$(printf '%s\n' "$disabled" | awk -F'|' '{ printf "%s (%s), ", $4, $7 }' | sed 's/, $//')
    printf ' %s rows disabled: %s\n\n' "$count" "$detail"
  fi

  group=""
  index=0
  printf '%s\n' "$state" |
    while IFS='|' read -r sel id grp label manager scope reason status missing checks checkpath install; do
      [ -n "$id" ] || continue
      if [ "$grp" != "$group" ]; then
        printf '%s\n' "$grp"
        group="$grp"
      fi

      if [ "$status" = "installed" ]; then marker="✓"
      elif [ -n "$reason" ];          then marker="-"
      elif [ "$sel" = "1" ];          then marker="x"
      else marker=" "
      fi

      if [ "$index" = "$cursor" ]; then pointer=">"; else pointer=" "; fi

      if [ "$status" = "installed" ]; then detail="already installed"
      elif [ -n "$reason" ];          then detail="$reason — disabled"
      elif [ "$status" = "partial" ]; then
        total=$(printf '%s' "$checks" | wc -w | tr -d ' ')
        [ -n "$checkpath" ] && total=$((total + 1))
        gone=$(printf '%s' "$missing" | wc -w | tr -d ' ')
        detail="$manager · $scope · $gone of $total missing"
      else detail="$manager · $scope"
      fi

      printf '%s [%s] %-34s %s\n' "$pointer" "$marker" "$label" "$detail"
      index=$((index + 1))
    done

  printf '\n space toggle · a all · n none · g group · s cycle source · d dry-run · enter install · q quit\n'
}

# menu_key <state> <cursor> <key> -> prints the new state; sets MENU_CURSOR,
# MENU_DONE, MENU_CANCELLED.
menu_key() {
  state="$1"; cursor="$2"; key="$3"
  MENU_DONE=0; MENU_CANCELLED=0; MENU_CURSOR="$cursor"
  total=$(printf '%s\n' "$state" | grep -c '|')

  case "$key" in
    up)    MENU_CURSOR=$([ "$cursor" -le 0 ] && echo $((total - 1)) || echo $((cursor - 1))) ;;
    down)  MENU_CURSOR=$([ "$cursor" -ge $((total - 1)) ] && echo 0 || echo $((cursor + 1))) ;;
    enter) MENU_DONE=1 ;;
    q)     MENU_CANCELLED=1 ;;
    space)
      state=$(printf '%s\n' "$state" | awk -F'|' -v OFS='|' -v c="$cursor" '
        NR-1 == c && $7 == "" && $8 != "installed" { $1 = ($1 == "1" ? "0" : "1") } { print }')
      ;;
    a)
      state=$(printf '%s\n' "$state" | awk -F'|' -v OFS='|' '
        $7 == "" && $8 != "installed" { $1 = "1" } { print }')
      ;;
    n)
      state=$(printf '%s\n' "$state" | awk -F'|' -v OFS='|' '{ $1 = "0"; print }')
      ;;
  esac

  printf '%s\n' "$state"
}
```

Rebuilding a record with `awk -v OFS='|'` is safe even when the install command
contains a `|`: awk splits it into extra fields and rejoins them with the same
separator, so the line comes back byte for byte.

- [ ] **Step 6: Add POSIX UI cases**

Insert into `install/tests/run.sh` before `harness_summary`:

```sh
. install/lib/ui.sh

echo "menu"

STATE='0|scoop|PACKAGE MANAGERS|scoop|self|user||installed||scoop||curl get.scoop.sh | sh
1|wezterm|CORE|wezterm (nightly)|scoop|user||missing|wezterm|wezterm||brew install --cask wezterm@nightly
1|toolbelt|TOOLBELT|ripgrep fd bat|brew|user||partial|bat|rg fd bat||brew install ripgrep fd bat
0|docker-desktop|CONTAINERS + AI|docker desktop|||needs sudo|missing|/opt/docker-desktop||/opt/docker-desktop|docker.io'

t_render_priv() {
  assert_contains "$(render_menu "$STATE" linux x86_64 standard "brew npm" 0)" "standard"
}
it "shows the privilege" t_render_priv

t_render_disabled() {
  assert_contains "$(render_menu "$STATE" linux x86_64 standard "brew npm" 0)" "needs sudo"
}
it "banners the disabled rows" t_render_disabled

t_render_installed() {
  assert_contains "$(render_menu "$STATE" linux x86_64 standard "brew npm" 0)" "already installed"
}
it "marks an installed row" t_render_installed

t_render_partial() {
  assert_contains "$(render_menu "$STATE" linux x86_64 standard "brew npm" 0)" "1 of 3 missing"
}
it "says how much of a partial row is left" t_render_partial

t_render_survives_pipes_in_install() {
  # The scoop row's install command contains a pipe; the record must still
  # parse, so the row is not rendered as though it were missing.
  line=$(render_menu "$STATE" linux x86_64 standard "brew npm" 0 | grep 'scoop ')
  assert_contains "$line" "already installed"
}
it "parses a record whose install command contains a pipe" t_render_survives_pipes_in_install

t_toggle() {
  new=$(menu_key "$STATE" 1 space)
  assert_contains "$(printf '%s\n' "$new" | sed -n 2p)" "0|wezterm"
}
it "toggles the row under the cursor" t_toggle

t_no_toggle_disabled() {
  new=$(menu_key "$STATE" 3 space)
  assert_contains "$(printf '%s\n' "$new" | sed -n 4p)" "0|docker-desktop"
}
it "refuses to toggle a disabled row" t_no_toggle_disabled

t_toggle_partial() {
  new=$(menu_key "$STATE" 2 space)
  assert_contains "$(printf '%s\n' "$new" | sed -n 3p)" "0|toolbelt"
}
it "lets a partial row be toggled" t_toggle_partial

t_select_all() {
  new=$(menu_key "$STATE" 0 a)
  assert_contains "$(printf '%s\n' "$new" | sed -n 4p)" "0|docker-desktop" &&
    assert_contains "$(printf '%s\n' "$new" | sed -n 1p)" "0|scoop"
}
it "select-all skips disabled and installed rows" t_select_all

t_wrap() {
  menu_key "$STATE" 0 up >/dev/null
  assert_eq "$MENU_CURSOR" "3"
}
it "wraps the cursor" t_wrap
```

- [ ] **Step 7: Run both suites**

Run: `Invoke-Pester install/tests -Output Detailed` and `& 'C:\Program Files\Git\bin\bash.exe' install/tests/run.sh`
Expected: both green.

- [ ] **Step 8: Commit**

```bash
git add install/lib/ui.ps1 install/lib/ui.sh install/tests
git commit -m "feat(install): render the selection menu as a pure function

Format-Menu returns lines and Invoke-MenuKey returns new state, so the
whole interface is asserted in tests without a terminal. Installed and
disabled rows cannot be selected by space, select-all, or group toggle,
which is the property that keeps a disabled row from being installed by
a stray keystroke.

A row renders in three states rather than two. A partial row shows how
much of it is missing and can be selected, since it is exactly the row
with work left. The POSIX record carries its checks and its path so the
execution phase can re-probe a row without consulting the catalog, and
every reader reads all twelve fields: reading fewer lands the remainder
in the last variable and quietly corrupts the status."
```

---

### Task 7: Execution and summary

**Files:**
- Create: `install/lib/exec.ps1`
- Create: `install/lib/exec.sh`
- Create: `install/tests/exec.Tests.ps1`
- Modify: `install/tests/run.sh`

**Interfaces:**
- Consumes: the view from Task 5 (`Selected`, `Status`, `Checks`, `Missing`, `Resolved`), and `Test-RowStatus` / `row_status` from the same task.
- Produces:
  - `Invoke-Rows($View, [scriptblock] $Runner, [switch] $DryRun, [scriptblock] $StatusProbe) -> hashtable` with `Succeeded`, `Skipped`, `Failed` (each an array of `@{ Id; Command; Error; Missing }`), and `NeedsElevation` (bool). `$Runner` is called as `& $Runner $command`. `$StatusProbe` is called as `& $StatusProbe $row` after the command and returns the same `@{ Status; Missing }` shape `Test-RowStatus` does; it defaults to `Test-RowStatus $row $row.Resolved`.
  - `Format-Summary($Result) -> string[]`.
  - `run_rows` and `format_summary` in `exec.sh` with the same semantics. `run_rows` expects `row_status` from `resolver.sh` to be sourced; the entry points source both.

**A row succeeds when its checks pass afterwards, not when its command exits
zero.** Re-running `scoop install main/ripgrep main/bat` where ripgrep is already
present exits non-zero, and judging by exit code would report a failure for a run
that did exactly what was asked — on every partial row, on every run. The exit
code and the captured output become the *reason* attached to a failure instead.
The reverse case matters too: a command that exits zero while leaving its tools
absent is a failure, and only re-probing catches it.

- [ ] **Step 1: Write the failing test**

Create `install/tests/exec.Tests.ps1`:

```powershell
BeforeAll {
    . "$PSScriptRoot/../lib/exec.ps1"

    function New-View {
        @(
            [pscustomobject] @{ Id='scoop'; Label='scoop'; Selected=$true; Status='missing'
                Checks=@('scoop'); Missing=@('scoop')
                Resolved=@{ Manager='self'; Scope='user'; Install='install-scoop' } }
            [pscustomobject] @{ Id='wezterm'; Label='wezterm'; Selected=$true; Status='missing'
                Checks=@('wezterm'); Missing=@('wezterm')
                Resolved=@{ Manager='scoop'; Scope='user'; Install='install-wezterm' } }
            [pscustomobject] @{ Id='neovim'; Label='neovim'; Selected=$false; Status='missing'
                Checks=@('nvim'); Missing=@('nvim')
                Resolved=@{ Manager='scoop'; Scope='user'; Install='install-neovim' } }
            [pscustomobject] @{ Id='docker'; Label='docker'; Selected=$true; Status='missing'
                Checks=@('docker'); Missing=@('docker')
                Resolved=@{ Manager='winget'; Scope='machine'; Install='install-docker' } }
        )
    }

    # Everything the run touches ends up installed unless a test says otherwise.
    $script:AllGood = { param($row) @{ Status = 'installed'; Missing = @() } }
}

Describe 'Invoke-Rows' {
    It 'runs only the selected rows, in catalog order' {
        $ran = [System.Collections.ArrayList]::new()
        Invoke-Rows (New-View) { param($cmd) [void] $ran.Add($cmd) } -StatusProbe $script:AllGood | Out-Null
        $ran | Should -Be @('install-scoop', 'install-wezterm', 'install-docker')
    }

    It 'reports a failure without aborting the rest' {
        $ran = [System.Collections.ArrayList]::new()
        $runner = {
            param($cmd)
            [void] $ran.Add($cmd)
            if ($cmd -eq 'install-wezterm') { throw 'boom' }
        }
        $probe = {
            param($row)
            if ($row.Id -eq 'wezterm') { @{ Status = 'missing'; Missing = @('wezterm') } }
            else { @{ Status = 'installed'; Missing = @() } }
        }
        $result = Invoke-Rows (New-View) $runner -StatusProbe $probe
        $ran.Count           | Should -Be 3
        $result.Failed.Count | Should -Be 1
        $result.Failed[0].Id | Should -Be 'wezterm'
        $result.Failed[0].Error | Should -Match 'boom'
        $result.Succeeded.Count | Should -Be 2
    }

    It 'counts a row that ends up installed even when the command exits non-zero' {
        # scoop refuses to reinstall what is already there; the tools are
        # present afterwards, which is what was asked for.
        $runner = { param($cmd) throw "'ripgrep' is already installed" }
        $result = Invoke-Rows (New-View) $runner -StatusProbe $script:AllGood
        $result.Succeeded.Count | Should -Be 3
        $result.Failed.Count    | Should -Be 0
    }

    It 'fails a row whose command succeeded but whose checks still do not pass' {
        $probe = { param($row) @{ Status = 'partial'; Missing = @('bat') } }
        $result = Invoke-Rows (New-View) { } -StatusProbe $probe
        $result.Failed.Count      | Should -Be 3
        $result.Failed[0].Missing | Should -Contain 'bat'
        $result.Failed[0].Error   | Should -Match 'still missing'
    }

    It 'runs nothing under dry run but reports what it would run' {
        $ran = [System.Collections.ArrayList]::new()
        $result = Invoke-Rows (New-View) { param($cmd) [void] $ran.Add($cmd) } -DryRun -StatusProbe $script:AllGood
        $ran.Count | Should -Be 0
        $result.Succeeded.Count | Should -Be 3
    }

    It 'never probes under dry run, because nothing has changed' {
        $probed = 0
        $probe = { param($row) $script:probed++; @{ Status = 'installed'; Missing = @() } }
        Invoke-Rows (New-View) { } -DryRun -StatusProbe $probe | Out-Null
        $script:probed | Should -Be 0
    }

    It 'flags that elevation will be needed before running anything' {
        $result = Invoke-Rows (New-View) { } -DryRun -StatusProbe $script:AllGood
        $result.NeedsElevation | Should -BeTrue
    }

    It 'does not flag elevation when no machine-scope row is selected' {
        $view = New-View
        ($view | Where-Object Id -eq 'docker').Selected = $false
        $result = Invoke-Rows $view { } -DryRun -StatusProbe $script:AllGood
        $result.NeedsElevation | Should -BeFalse
    }

    It 'skips a row that is already installed even if selected' {
        $view = New-View
        ($view | Where-Object Id -eq 'scoop').Status = 'installed'
        $result = Invoke-Rows $view { } -DryRun -StatusProbe $script:AllGood
        $result.Skipped.Id | Should -Contain 'scoop'
    }

    It 'still runs a partial row' {
        $view = New-View
        ($view | Where-Object Id -eq 'scoop').Status = 'partial'
        $ran = [System.Collections.ArrayList]::new()
        Invoke-Rows $view { param($cmd) [void] $ran.Add($cmd) } -StatusProbe $script:AllGood | Out-Null
        $ran | Should -Contain 'install-scoop'
    }
}

Describe 'Format-Summary' {
    It 'names the failing command so it can be re-run by hand' {
        $result = @{
            Succeeded = @(@{ Id='scoop'; Command='install-scoop' })
            Skipped   = @()
            Failed    = @(@{ Id='wezterm'; Command='install-wezterm'; Error='boom'; Missing=@('wezterm') })
            NeedsElevation = $false
        }
        $text = (Format-Summary $result) -join "`n"
        $text | Should -Match 'install-wezterm'
        $text | Should -Match 'boom'
        $text | Should -Match '1 installed'
        $text | Should -Match '1 failed'
    }

    It 'lists what is still missing after a failure' {
        $result = @{
            Succeeded = @()
            Skipped   = @()
            Failed    = @(@{ Id='toolbelt'; Command='install-belt'; Error='still missing'; Missing=@('bat','eza') })
            NeedsElevation = $false
        }
        (Format-Summary $result) -join "`n" | Should -Match 'bat, eza'
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Invoke-Pester install/tests/exec.Tests.ps1 -Output Detailed`
Expected: FAIL — `install/lib/exec.ps1` does not exist.

- [ ] **Step 3: Write exec.ps1**

Create `install/lib/exec.ps1`:

```powershell
function Invoke-Rows {
    param(
        [Parameter(Mandatory)] $View,
        [Parameter(Mandatory)] [scriptblock] $Runner,
        [switch] $DryRun,
        [scriptblock] $StatusProbe = { param($row) Test-RowStatus $row $row.Resolved }
    )

    $selected = @($View | Where-Object Selected)

    $result = @{
        Succeeded = @()
        Skipped   = @()
        Failed    = @()
        NeedsElevation = [bool] @($selected |
            Where-Object { $_.Resolved -and $_.Resolved.Scope -eq 'machine' }).Count
    }

    foreach ($row in $selected) {
        if ($row.Status -eq 'installed') {
            $result.Skipped += @{ Id = $row.Id; Command = $null; Error = $null; Missing = @() }
            continue
        }
        if (-not $row.Resolved) {
            $result.Skipped += @{ Id = $row.Id; Command = $null; Error = 'no viable source'; Missing = @($row.Missing) }
            continue
        }

        $command = $row.Resolved.Install

        if ($DryRun) {
            Write-Host "would run: $command"
            $result.Succeeded += @{ Id = $row.Id; Command = $command; Error = $null; Missing = @() }
            continue
        }

        # The runner's own failure is recorded but does not decide anything: a
        # manager that refuses to reinstall an already-present tool exits
        # non-zero on a run that did what was asked.
        $runError = $null
        try { & $Runner $command } catch { $runError = $_.Exception.Message }

        $after = & $StatusProbe $row

        if ($after.Status -eq 'installed') {
            $result.Succeeded += @{ Id = $row.Id; Command = $command; Error = $null; Missing = @() }
        } else {
            $reason = if ($runError) { $runError } else { "still missing after install" }
            $result.Failed += @{
                Id = $row.Id; Command = $command; Error = $reason; Missing = @($after.Missing)
            }
        }
    }

    return $result
}

function Format-Summary {
    param([Parameter(Mandatory)] $Result)

    $lines = @()
    $lines += ''
    $lines += ('{0} installed, {1} skipped, {2} failed' -f
        $Result.Succeeded.Count, $Result.Skipped.Count, $Result.Failed.Count)

    foreach ($failure in $Result.Failed) {
        $lines += ''
        $lines += "  failed: $($failure.Id)"
        $lines += "    command: $($failure.Command)"
        $lines += "    error:   $($failure.Error)"
        if (@($failure.Missing).Count -gt 0) {
            $lines += "    missing: $(@($failure.Missing) -join ', ')"
        }
    }

    return $lines
}
```

- [ ] **Step 4: Run it to verify it passes**

Run: `Invoke-Pester install/tests/exec.Tests.ps1 -Output Detailed`
Expected: 12 passed.

- [ ] **Step 5: Write exec.sh**

Create `install/lib/exec.sh`:

```sh
#!/bin/sh
# run_rows <state> <runner> <dry_run>
# state records:
#   selected|id|group|label|manager|scope|reason|status|missing|checks|checkpath|install
# Sets RUN_OK, RUN_SKIP, RUN_FAIL (counts) and RUN_FAILURES (id\tcommand\terror
# lines). Expects row_status from resolver.sh; ROW_STATUS_FN allows tests to
# replace it.

ROW_STATUS_FN=row_status

run_rows() {
  state="$1"; runner="$2"; dry="$3"
  RUN_OK=0; RUN_SKIP=0; RUN_FAIL=0; RUN_FAILURES=""; RUN_NEEDS_ELEVATION=0

  # Decided before the first command rather than partway through.
  case "$(printf '%s\n' "$state" | awk -F'|' '$1 == "1" && $6 == "machine"')" in
    "") RUN_NEEDS_ELEVATION=0 ;;
    *)  RUN_NEEDS_ELEVATION=1 ;;
  esac

  OLD_IFS="$IFS"
  while IFS='|' read -r sel id grp label manager scope reason status missing checks checkpath install; do
    [ "$sel" = "1" ] || continue

    if [ "$status" = "installed" ] || [ -n "$reason" ]; then
      RUN_SKIP=$((RUN_SKIP + 1))
      continue
    fi

    if [ "$dry" = "1" ]; then
      printf 'would run: %s\n' "$install"
      RUN_OK=$((RUN_OK + 1))
      continue
    fi

    if err=$("$runner" "$install" 2>&1); then
      err=""
    fi

    after=$("$ROW_STATUS_FN" "$checks" "$checkpath")
    if [ "$after" = "installed" ]; then
      RUN_OK=$((RUN_OK + 1))
    else
      RUN_FAIL=$((RUN_FAIL + 1))
      [ -n "$err" ] || err="still missing after install: $ROW_MISSING"
      RUN_FAILURES="$RUN_FAILURES$id	$install	$err
"
    fi
  done <<EOF
$state
EOF
  IFS="$OLD_IFS"
}

format_summary() {
  printf '\n%d installed, %d skipped, %d failed\n' "$RUN_OK" "$RUN_SKIP" "$RUN_FAIL"
  [ -n "$RUN_FAILURES" ] || return 0
  printf '%s' "$RUN_FAILURES" | while IFS='	' read -r id command err; do
    [ -n "$id" ] || continue
    printf '\n  failed: %s\n    command: %s\n    error:   %s\n' "$id" "$command" "$err"
  done
}
```

- [ ] **Step 6: Add POSIX exec cases**

Insert into `install/tests/run.sh` before `harness_summary`:

```sh
. install/lib/exec.sh

echo "run_rows"

EXEC_STATE='1|scoop|PM|scoop|self|user||missing|scoop|scoop||install-scoop
1|wezterm|CORE|wezterm|brew|user||missing|wezterm|wezterm||install-wezterm
0|neovim|CORE|neovim|brew|user||missing|nvim|nvim||install-neovim
1|docker|AI|docker|system|machine||missing|docker|docker||install-docker'

fake_runner() { echo "ran $1" >> "$RUN_LOG"; }
failing_runner() { [ "$1" != "install-wezterm" ] || { echo "boom" >&2; return 1; }; }
status_all_good() { ROW_MISSING=""; printf 'installed\n'; }
status_never_good() { ROW_MISSING="bat"; printf 'missing\n'; }

t_runs_selected() {
  RUN_LOG=$(mktemp)
  ROW_STATUS_FN=status_all_good
  run_rows "$EXEC_STATE" fake_runner 0
  assert_eq "$(wc -l < "$RUN_LOG" | tr -d ' ')" "3"
}
it "runs only the selected rows" t_runs_selected

t_continues_after_failure() {
  RUN_LOG=$(mktemp)
  ROW_STATUS_FN=status_never_good
  run_rows "$EXEC_STATE" failing_runner 0
  assert_eq "$RUN_FAIL" "3"
}
it "reports a failure without aborting" t_continues_after_failure

t_exit_code_does_not_decide() {
  RUN_LOG=$(mktemp)
  ROW_STATUS_FN=status_all_good
  run_rows "$EXEC_STATE" failing_runner 0
  assert_eq "$RUN_FAIL" "0" && assert_eq "$RUN_OK" "3"
}
it "counts a row whose checks pass even when the command failed" t_exit_code_does_not_decide

t_dry_run() {
  RUN_LOG=$(mktemp)
  ROW_STATUS_FN=status_all_good
  run_rows "$EXEC_STATE" fake_runner 1 >/dev/null
  assert_eq "$(wc -c < "$RUN_LOG" | tr -d ' ')" "0"
}
it "runs nothing under dry run" t_dry_run

t_elevation_flag() {
  ROW_STATUS_FN=status_all_good
  run_rows "$EXEC_STATE" fake_runner 1 >/dev/null
  assert_eq "$RUN_NEEDS_ELEVATION" "1"
}
it "flags that elevation is needed" t_elevation_flag

t_skips_installed() {
  ROW_STATUS_FN=status_all_good
  run_rows "$(printf '%s\n' "$EXEC_STATE" | sed '1s/|missing|/|installed|/')" fake_runner 1 >/dev/null
  assert_eq "$RUN_SKIP" "1"
}
it "skips a row that is already installed" t_skips_installed
```

- [ ] **Step 7: Run both suites**

Run: `Invoke-Pester install/tests -Output Detailed` and `& 'C:\Program Files\Git\bin\bash.exe' install/tests/run.sh`
Expected: both green.

- [ ] **Step 8: Commit**

```bash
git add install/lib/exec.ps1 install/lib/exec.sh install/tests
git commit -m "feat(install): execute rows in order and report what happened

The runner is injected, so ordering, dry run, and failure handling are
all asserted without installing anything. A failing row is captured and
the run continues; the summary prints the exact command that failed so
it can be repeated by hand. Whether elevation will be needed is decided
before the first command rather than partway through.

A row is judged by whether its checks pass afterwards rather than by the
exit code its command returned. Package managers refuse to reinstall what
is already present and exit non-zero doing so, which would have failed
every partial row on every run; and a command that exits zero while
leaving its tools absent is a failure that only re-probing catches. The
exit code survives as the reason attached to a failure."
```

---

### Task 8: Linking with backups

**Files:**
- Create: `install/lib/link.ps1`
- Create: `install/lib/link.sh`
- Create: `install/tests/link.Tests.ps1`
- Modify: `install/tests/run.sh`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `New-ConfigLink([string] $Target, [string] $Source, [string] $Stamp) -> hashtable` with `Action` (`created|already-linked|backed-up-and-created`), `Backup` (path or `$null`). Uses a junction on Windows.
  - `Get-LinkTargets([string] $RepoRoot, [string] $Os) -> hashtable[]` — `@{ Target; Source }` pairs for wezterm and nvim.
  - `link_config <target> <source> <stamp>` and `link_targets <repo_root> <os>` in `link.sh`.

- [ ] **Step 1: Write the failing test**

Create `install/tests/link.Tests.ps1`:

```powershell
BeforeAll {
    . "$PSScriptRoot/../lib/link.ps1"
}

Describe 'Get-LinkTargets' {
    It 'points wezterm and nvim at the repo on windows' {
        $targets = Get-LinkTargets 'C:\repo' 'windows'
        ($targets | Where-Object { $_.Source -eq 'C:\repo\wezterm' }).Target | Should -Match 'wezterm'
        ($targets | Where-Object { $_.Source -eq 'C:\repo\nvim' }).Target | Should -Match 'nvim'
    }

    It 'uses XDG paths elsewhere' {
        $targets = Get-LinkTargets '/repo' 'linux'
        ($targets | ForEach-Object Target) -join ' ' | Should -Match '\.config'
    }
}

Describe 'New-ConfigLink' {
    BeforeEach {
        $script:Root = Join-Path ([IO.Path]::GetTempPath()) ("linktest-" + [guid]::NewGuid())
        $script:Source = Join-Path $script:Root 'repo/wezterm'
        $script:Target = Join-Path $script:Root 'config/wezterm'
        New-Item -ItemType Directory -Force $script:Source | Out-Null
        New-Item -ItemType Directory -Force (Split-Path $script:Target) | Out-Null
        Set-Content (Join-Path $script:Source 'wezterm.lua') 'return {}'
    }

    AfterEach {
        Remove-Item -Recurse -Force $script:Root -ErrorAction SilentlyContinue
    }

    It 'creates the link when nothing is there' {
        $result = New-ConfigLink $script:Target $script:Source '20260801-120000'
        $result.Action | Should -Be 'created'
        Test-Path (Join-Path $script:Target 'wezterm.lua') | Should -BeTrue
    }

    It 'backs up a real directory instead of deleting it' {
        New-Item -ItemType Directory -Force $script:Target | Out-Null
        Set-Content (Join-Path $script:Target 'old.lua') 'keep me'

        $result = New-ConfigLink $script:Target $script:Source '20260801-120000'
        $result.Action | Should -Be 'backed-up-and-created'
        $result.Backup | Should -Match 'bak-20260801-120000'
        Test-Path (Join-Path $result.Backup 'old.lua') | Should -BeTrue
    }

    It 'is a no-op when the link already points at the source' {
        New-ConfigLink $script:Target $script:Source '20260801-120000' | Out-Null
        $again = New-ConfigLink $script:Target $script:Source '20260801-120001'
        $again.Action | Should -Be 'already-linked'
        $again.Backup | Should -BeNullOrEmpty
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Invoke-Pester install/tests/link.Tests.ps1 -Output Detailed`
Expected: FAIL — `install/lib/link.ps1` does not exist.

- [ ] **Step 3: Write link.ps1**

Create `install/lib/link.ps1`:

```powershell
function Get-LinkTargets {
    param(
        [Parameter(Mandatory)] [string] $RepoRoot,
        [Parameter(Mandatory)] [string] $Os
    )

    $home_ = if ($env:HOME) { $env:HOME } else { $env:USERPROFILE }

    if ($Os -eq 'windows') {
        return @(
            @{ Target = Join-Path $home_ '.config\wezterm'; Source = Join-Path $RepoRoot 'wezterm' }
            @{ Target = Join-Path $env:LOCALAPPDATA 'nvim';  Source = Join-Path $RepoRoot 'nvim' }
        )
    }

    return @(
        @{ Target = "$home_/.config/wezterm"; Source = "$RepoRoot/wezterm" }
        @{ Target = "$home_/.config/nvim";    Source = "$RepoRoot/nvim" }
    )
}

function New-ConfigLink {
    param(
        [Parameter(Mandatory)] [string] $Target,
        [Parameter(Mandatory)] [string] $Source,
        [Parameter(Mandatory)] [string] $Stamp
    )

    $backup = $null

    if (Test-Path $Target) {
        $item = Get-Item $Target -Force
        $isLink = $item.LinkType -in @('Junction', 'SymbolicLink')

        if ($isLink -and $item.Target -and (Resolve-Path $item.Target[0]).Path -eq (Resolve-Path $Source).Path) {
            return @{ Action = 'already-linked'; Backup = $null }
        }

        $backup = "$Target.bak-$Stamp"
        Move-Item -Path $Target -Destination $backup
    }

    $parent = Split-Path $Target
    if ($parent -and -not (Test-Path $parent)) {
        New-Item -ItemType Directory -Force $parent | Out-Null
    }

    New-Item -ItemType Junction -Path $Target -Target $Source | Out-Null

    return @{
        Action = if ($backup) { 'backed-up-and-created' } else { 'created' }
        Backup = $backup
    }
}
```

- [ ] **Step 4: Run it to verify it passes**

Run: `Invoke-Pester install/tests/link.Tests.ps1 -Output Detailed`
Expected: 5 passed.

- [ ] **Step 5: Write link.sh**

Create `install/lib/link.sh`:

```sh
#!/bin/sh
# link_config <target> <source> <stamp> -> prints created|already-linked|backed-up-and-created
# Sets LINK_BACKUP when a backup was made.

link_config() {
  target="$1"; source="$2"; stamp="$3"
  LINK_BACKUP=""

  if [ -L "$target" ]; then
    current=$(readlink "$target")
    if [ "$current" = "$source" ]; then
      printf 'already-linked\n'
      return 0
    fi
    rm "$target"
    ln -s "$source" "$target"
    printf 'created\n'
    return 0
  fi

  if [ -e "$target" ]; then
    LINK_BACKUP="$target.bak-$stamp"
    mv "$target" "$LINK_BACKUP"
    mkdir -p "$(dirname "$target")"
    ln -s "$source" "$target"
    printf 'backed-up-and-created\n'
    return 0
  fi

  mkdir -p "$(dirname "$target")"
  ln -s "$source" "$target"
  printf 'created\n'
}

# link_targets <repo_root> <os> -> target<TAB>source lines
link_targets() {
  repo="$1"
  printf '%s/.config/wezterm\t%s/wezterm\n' "$HOME" "$repo"
  printf '%s/.config/nvim\t%s/nvim\n' "$HOME" "$repo"
}
```

- [ ] **Step 6: Add POSIX link cases**

Insert into `install/tests/run.sh` before `harness_summary`:

```sh
. install/lib/link.sh

echo "link_config"

setup_link_test() {
  LINK_ROOT=$(mktemp -d)
  mkdir -p "$LINK_ROOT/repo/wezterm" "$LINK_ROOT/config"
  echo 'return {}' > "$LINK_ROOT/repo/wezterm/wezterm.lua"
}

t_creates() {
  setup_link_test
  out=$(link_config "$LINK_ROOT/config/wezterm" "$LINK_ROOT/repo/wezterm" 20260801-120000)
  assert_eq "$out" "created" && [ -f "$LINK_ROOT/config/wezterm/wezterm.lua" ]
}
it "creates the link when nothing is there" t_creates

t_backs_up() {
  setup_link_test
  mkdir -p "$LINK_ROOT/config/wezterm"
  echo keep > "$LINK_ROOT/config/wezterm/old.lua"
  out=$(link_config "$LINK_ROOT/config/wezterm" "$LINK_ROOT/repo/wezterm" 20260801-120000)
  assert_eq "$out" "backed-up-and-created" &&
    [ -f "$LINK_ROOT/config/wezterm.bak-20260801-120000/old.lua" ]
}
it "backs up a real directory instead of deleting it" t_backs_up

t_idempotent() {
  setup_link_test
  link_config "$LINK_ROOT/config/wezterm" "$LINK_ROOT/repo/wezterm" 20260801-120000 >/dev/null
  out=$(link_config "$LINK_ROOT/config/wezterm" "$LINK_ROOT/repo/wezterm" 20260801-120001)
  assert_eq "$out" "already-linked"
}
it "is a no-op when already linked" t_idempotent
```

- [ ] **Step 7: Run both suites**

Run: `Invoke-Pester install/tests -Output Detailed` and `& 'C:\Program Files\Git\bin\bash.exe' install/tests/run.sh`
Expected: both green.

- [ ] **Step 8: Commit**

```bash
git add install/lib/link.ps1 install/lib/link.sh install/tests
git commit -m "feat(install): link configs with timestamped backups

An existing directory is renamed rather than removed, a link that
already points at the repo is left alone, and Windows uses a junction
so no administrator rights or Developer Mode are required."
```

---

### Task 9: Entry points

**Files:**
- Create: `install.ps1`
- Create: `install.sh`

**Interfaces:**
- Consumes: every library from Tasks 2–8.
- Produces: the two executable entry points named in the README one-liners.

- [ ] **Step 1: Write install.ps1**

Create `install.ps1`:

```powershell
#Requires -Version 7.0
[CmdletBinding()] param()

$ErrorActionPreference = 'Stop'

$RepoUrl  = 'https://github.com/arthurpessoa/dotfiles'
$RepoRoot = Join-Path $HOME '.dotfiles'

# When run through 'irm | iex' the library is not on disk yet, so clone first.
if (-not (Test-Path (Join-Path $PSScriptRoot 'install/lib/args.ps1'))) {
    if (-not (Test-Path $RepoRoot)) {
        git clone $RepoUrl $RepoRoot
    } else {
        git -C $RepoRoot pull --ff-only
    }
    & (Join-Path $RepoRoot 'install.ps1') @args
    return
}

. "$PSScriptRoot/install/lib/args.ps1"
. "$PSScriptRoot/install/lib/probe.ps1"
. "$PSScriptRoot/install/lib/catalog.ps1"
. "$PSScriptRoot/install/lib/resolver.ps1"
. "$PSScriptRoot/install/lib/ui.ps1"
. "$PSScriptRoot/install/lib/exec.ps1"
. "$PSScriptRoot/install/lib/link.ps1"

$options = Get-InstallerArgs $args

if ($options.Help) {
    @(
        'usage: install.ps1 [--all] [--only a,b,c] [--yes] [--dry-run]'
        '                   [--scope user|machine] [--manager NAME]'
    ) | Write-Host
    return
}

$environment = Get-Environment
$catalog = Import-Catalog "$PSScriptRoot/install/catalog.psd1"

$problems = Test-Catalog $catalog
if ($problems) { throw "catalog is invalid:`n" + ($problems -join "`n") }

$view = Get-CatalogView $catalog $environment

if ($options.All) {
    foreach ($row in $view) {
        if ($row.Status -ne 'installed' -and $row.Resolved) { $row.Selected = $true }
    }
} elseif ($options.Only) {
    foreach ($row in $view) { $row.Selected = $row.Id -in $options.Only }
} elseif (-not [Console]::IsInputRedirected) {
    $cursor = 0
    while ($true) {
        Clear-Host
        Format-Menu $view $environment $cursor | Write-Host

        $pressed = [Console]::ReadKey($true)
        $key = switch ($pressed.Key) {
            'UpArrow'    { 'up' }
            'DownArrow'  { 'down' }
            'Spacebar'   { 'space' }
            'Enter'      { 'enter' }
            default      { $pressed.KeyChar.ToString().ToLower() }
        }

        if ($key -eq 'd') { $options.DryRun = -not $options.DryRun; continue }

        $step = Invoke-MenuKey $view $cursor $key
        $view = $step.View
        $cursor = $step.Cursor
        if ($step.Cancelled) { Write-Host 'cancelled'; return }
        if ($step.Done) { break }
    }
} else {
    throw 'no interactive terminal: pass --all or --only a,b,c'
}

$result = Invoke-Rows $view { param($cmd) Invoke-Expression $cmd } -DryRun:$options.DryRun

if (($view | Where-Object { $_.Id -eq 'dotfiles' -and $_.Selected }) -and -not $options.DryRun) {
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    foreach ($pair in Get-LinkTargets $RepoRoot $environment.Os) {
        $link = New-ConfigLink $pair.Target $pair.Source $stamp
        Write-Host "$($pair.Target): $($link.Action)"
        if ($link.Backup) { Write-Host "  backup: $($link.Backup)" }
    }
}

Format-Summary $result | Write-Host
```

- [ ] **Step 2: Verify the dry run end to end**

Run: `pwsh -NoProfile -File install.ps1 --all --dry-run`

Expected: the probe summary, then one `would run:` line per selected row, then `N installed, M skipped, 0 failed`. Nothing is installed. Confirm by eye that `wezterm` resolves through `scoop` with `versions/wezterm-nightly`, that already-installed rows are skipped, and that any row reported as partial names how much of it is missing.

- [ ] **Step 3: Verify the no-tty refusal**

Run: `echo '' | pwsh -NoProfile -File install.ps1`

Expected: it exits with `no interactive terminal: pass --all or --only a,b,c` rather than installing anything.

- [ ] **Step 4: Write install.sh**

Create `install.sh`:

```sh
#!/bin/sh
set -eu

REPO_URL='https://github.com/arthurpessoa/dotfiles'
REPO_ROOT="$HOME/.dotfiles"

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)

# Under 'curl | sh' there is no script directory, so clone and re-exec.
if [ ! -f "$SCRIPT_DIR/install/lib/args.sh" ]; then
  if [ ! -d "$REPO_ROOT" ]; then
    git clone "$REPO_URL" "$REPO_ROOT"
  else
    git -C "$REPO_ROOT" pull --ff-only
  fi
  exec sh "$REPO_ROOT/install.sh" "$@"
fi

. "$SCRIPT_DIR/install/lib/args.sh"
. "$SCRIPT_DIR/install/lib/probe.sh"
. "$SCRIPT_DIR/install/catalog.sh"
. "$SCRIPT_DIR/install/lib/resolver.sh"
. "$SCRIPT_DIR/install/lib/ui.sh"
. "$SCRIPT_DIR/install/lib/exec.sh"
. "$SCRIPT_DIR/install/lib/link.sh"

parse_args "$@" || exit 1

if [ "$ARG_HELP" = "1" ]; then
  echo 'usage: install.sh [--all] [--only a,b,c] [--yes] [--dry-run]'
  echo '                  [--scope user|machine] [--manager NAME]'
  exit 0
fi

detect_environment

# One record per row:
#   selected|id|group|label|manager|scope|reason|status|missing|checks|checkpath|install
build_state() {
  catalog_rows | while IFS='|' read -r id grp label checks; do
    checkpath=""
    if method=$(resolve_source "$id"); then
      manager=$(printf '%s' "$method" | cut -d'|' -f2)
      scope=$(printf '%s' "$method" | cut -d'|' -f3)
      checkpath=$(printf '%s' "$method" | cut -d'|' -f4)
      install=$(printf '%s' "$method" | cut -d'|' -f5-)
      reason=""
    else
      manager=""; scope=""; install=""; reason="$RESOLVE_REASON"
    fi

    status=$(row_status "$checks" "$checkpath")
    missing="$ROW_MISSING"

    selected=0
    if [ "$status" != "installed" ] && [ -z "$reason" ]; then selected=1; fi

    printf '%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n' \
      "$selected" "$id" "$grp" "$label" "$manager" "$scope" "$reason" \
      "$status" "$missing" "$checks" "$checkpath" "$install"
  done
}

STATE=$(build_state)

if [ "$ARG_ONLY" != "" ]; then
  STATE=$(printf '%s\n' "$STATE" | awk -F'|' -v OFS='|' -v only=",$ARG_ONLY," '
    { $1 = (index(only, "," $2 ",") > 0) ? "1" : "0"; print }')
elif [ "$ARG_ALL" = "1" ]; then
  STATE=$(printf '%s\n' "$STATE" | awk -F'|' -v OFS='|' '
    $7 == "" && $8 != "installed" { $1 = "1" } { print }')
elif [ -t 0 ] || [ -r /dev/tty ]; then
  cursor=0
  while true; do
    clear
    render_menu "$STATE" "$ENV_OS" "$ENV_ARCH" "$ENV_PRIVILEGE" "$ENV_MANAGERS" "$cursor"
    # curl | sh occupies stdin, so read the keyboard from the terminal directly.
    key=$(dd bs=1 count=1 2>/dev/null < /dev/tty)
    case "$key" in
      ' ') key=space ;;
      '')  key=enter ;;
      q)   key=q ;;
    esac
    STATE=$(menu_key "$STATE" "$cursor" "$key")
    cursor="$MENU_CURSOR"
    [ "$MENU_CANCELLED" = "1" ] && { echo cancelled; exit 0; }
    [ "$MENU_DONE" = "1" ] && break
  done
else
  echo 'no interactive terminal: pass --all or --only a,b,c' >&2
  exit 1
fi

shell_runner() { sh -c "$1"; }
run_rows "$STATE" shell_runner "$ARG_DRY_RUN"

if printf '%s\n' "$STATE" | grep -q '^1|dotfiles|' && [ "$ARG_DRY_RUN" != "1" ]; then
  stamp=$(date +%Y%m%d-%H%M%S)
  link_targets "$REPO_ROOT" "$ENV_OS" | while IFS='	' read -r target source; do
    action=$(link_config "$target" "$source" "$stamp")
    printf '%s: %s\n' "$target" "$action"
    [ -n "$LINK_BACKUP" ] && printf '  backup: %s\n' "$LINK_BACKUP"
  done
fi

format_summary
```

- [ ] **Step 5: Verify the shell entry point under Git Bash**

Run: `& 'C:\Program Files\Git\bin\bash.exe' install.sh --all --dry-run`

Expected: the probe summary and `would run:` lines. Git Bash reports itself as a Linux-like environment, so the rows resolve through the Linux methods; this is a syntax and flow check, not a package-manager one.

Run: `& 'C:\Program Files\Git\bin\bash.exe' -c "./install.sh < /dev/null"` and confirm the no-tty refusal.

- [ ] **Step 6: Verify install.sh on real Linux, in WSL**

This is the step that turns "the POSIX half is untested" into a claim with
evidence behind it. WSL Ubuntu-24.04 is a real Linux with real apt; everything
below mutates that distro alone and never touches Windows.

Clone into the distro's own filesystem rather than running from `/mnt/c`, so
line endings, permissions and paths are all genuinely Linux:

```bash
wsl -d Ubuntu-24.04 -- git clone /mnt/c/Users/arthu/.dotfiles "$HOME/.dotfiles"
```

Run 1 — every row resolved, nothing touched:

```bash
wsl -d Ubuntu-24.04 -- sh -c 'cd ~/.dotfiles && sh install.sh --all --dry-run'
```

Expected: a `would run:` line per selected row and `0 failed`. Confirm that
`wezterm` resolves to the nightly AppImage, and that rows needing sudo are
disabled with a reason rather than hidden.

Run 2 — a live install through apt:

```bash
wsl -d Ubuntu-24.04 -- sh -c 'cd ~/.dotfiles && sh install.sh --only git,neovim --yes'
```

Expected: `git` is already present in that distro and is skipped as installed;
`neovim` is absent and is installed. One run therefore covers both paths.
Confirm afterwards with `wsl -d Ubuntu-24.04 -- nvim --version`.

Run 3 — the links, twice:

```bash
wsl -d Ubuntu-24.04 -- sh -c 'cd ~/.dotfiles && sh install.sh --only dotfiles --yes'
wsl -d Ubuntu-24.04 -- sh -c 'cd ~/.dotfiles && sh install.sh --only dotfiles --yes'
```

Expected: the first run creates `~/.config/wezterm` and `~/.config/nvim` as
symlinks into the repo; the second reports them already linked and does **not**
fail. Then prove the backup rule by putting a real directory in the way:

```bash
wsl -d Ubuntu-24.04 -- sh -c 'rm ~/.config/nvim && mkdir -p ~/.config/nvim && touch ~/.config/nvim/keep.lua'
wsl -d Ubuntu-24.04 -- sh -c 'cd ~/.dotfiles && sh install.sh --only dotfiles --yes'
wsl -d Ubuntu-24.04 -- sh -c 'ls -d ~/.config/nvim.bak-* && cat ~/.config/nvim.bak-*/keep.lua'
```

Expected: the directory is renamed to `nvim.bak-<timestamp>` with `keep.lua`
intact, and `~/.config/nvim` is a symlink. Nothing is ever deleted.

Record what actually happened in the commit message for this task, including
anything that had to be fixed. If a run fails, fix the cause and repeat it — the
point of this step is that the claim is earned.

- [ ] **Step 7: Commit**

```bash
git add install.ps1 install.sh
git commit -m "feat(install): add the two entry points

Both scripts clone and re-exec when invoked through a pipe, since the
library is not on disk at that point. The shell version reads keys from
/dev/tty because curl occupies stdin, and both refuse to guess when no
terminal is attached.

install.sh was exercised on real Linux rather than only under Git Bash:
a dry run over every row, a live apt install covering both an
already-present row and a missing one, and the link phase run twice to
prove that re-linking replaces rather than fails and that a real config
directory in the way is renamed rather than removed."
```

---

### Task 10: README one-liners and final verification

**Files:**
- Modify: `README.md`

**Interfaces:**
- Consumes: everything.
- Produces: the published bootstrap instructions.

- [ ] **Step 1: Rename the default branch to main**

The one-liners below fetch from `/main/`. The repository was pushed with
`master` as its default, so rename it before publishing URLs that depend on it,
rather than shipping links that 404:

```bash
git branch -m master main
git push -u origin main
gh repo edit arthurpessoa/dotfiles --default-branch main
git push origin --delete master
```

Confirm with `gh repo view arthurpessoa/dotfiles --json defaultBranchRef`, which
must report `main`, and with
`curl -fsSL -o /dev/null -w '%{http_code}' https://raw.githubusercontent.com/arthurpessoa/dotfiles/main/README.md`,
which must report `200`.

- [ ] **Step 2: Add the bootstrap section to the README**

Insert after the intro in `README.md`:

````markdown
## Install

Windows:

```powershell
irm https://raw.githubusercontent.com/arthurpessoa/dotfiles/main/install.ps1 | iex
```

macOS and Linux:

```bash
curl -fsSL https://raw.githubusercontent.com/arthurpessoa/dotfiles/main/install.sh | sh
```

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

The installer probes the machine, then shows a checklist:

- `space` toggle, `a` all, `n` none, `g` toggle group
- `s` cycle the source for the row under the cursor
- `d` dry run, `enter` install, `q` quit

A row that is already satisfied shows `already installed` and is skipped, so
re-running is a no-op. A row that provides several tools and has only some of
them shows how many are missing and arrives selected, so a catalog that grows a
tool does not leave the machine quietly behind. Rows with no admin-free path on
a machine where you cannot elevate are disabled with the reason shown, never
silently skipped.

Non-interactive: `--all`, `--only git,wezterm,nvim`, `--yes`, `--dry-run`,
`--scope user|machine`, `--manager NAME`. With no terminal attached the script
exits rather than guessing.

**Verified on Windows and on Linux.** `install.ps1` is run on Windows and
`install.sh` on Ubuntu under WSL, including a real package install and the link
phase. **The macOS path is unverified**: its rows are written against Homebrew
and sdkman but have never been run on a Mac.
````

- [ ] **Step 3: Run the full suite one last time**

```powershell
Invoke-Pester install/tests -Output Detailed
& 'C:\Program Files\Git\bin\bash.exe' install/tests/run.sh
nvim -l wezterm/tests/run.lua
```

Expected: all three green.

- [ ] **Step 4: Prove idempotence on this machine**

Run: `pwsh -NoProfile -File install.ps1 --only dotfiles`

Expected: both link targets report `already-linked`, no backup is created, and the summary reports 1 installed, 0 failed. Confirm `~/.config/wezterm` and `%LOCALAPPDATA%\nvim` still resolve into the repo afterwards.

- [ ] **Step 5: Prove a partial row is reported and repaired**

This machine has `rg`, `fzf` and `lazygit` but not `bat`, so the toolbelt row is
genuinely partial rather than synthetically so.

Run: `pwsh -NoProfile -File install.ps1 --dry-run`

Expected: the toolbelt row renders as partial and names how many of its nine
commands are missing, and it arrives selected.

Run: `pwsh -NoProfile -File install.ps1 --only toolbelt --yes`

Expected: the row installs the missing tools and is reported as installed
afterwards even though scoop exits non-zero for the packages that were already
there. Confirm with `bat --version`, then re-run the same command and confirm it
now reports the row as skipped rather than failed.

- [ ] **Step 6: Confirm the standard-user path**

From a non-elevated shell, run `pwsh -NoProfile -File install.ps1 --dry-run` and read the banner. On this machine, confirm that `docker-desktop` either shows `already installed` (Docker Desktop is present here) or, if you test with a synthetic environment, that a machine-scope row with no user-scope alternative renders `needs admin — disabled` and is not selected.

- [ ] **Step 7: Commit**

```bash
git add README.md
git commit -m "docs: add the bootstrap one-liners and the key legend

Both the pipe form and the download-then-read form are shown, because
piping a URL into a shell executes whatever it serves at that moment.
Says which platforms have actually been run: Windows and Linux under
WSL, with macOS written but unverified."
```

---

## Self-Review

**Spec coverage.** Bootstrap one-liners → Task 10. Probe with three privilege outcomes → Task 4. Selection UI with the documented keys → Task 6. Source resolution ladder including the run-time winget user-scope probe → Task 5. Catalog with package managers as rows and wezterm pinned to nightly → Task 3. Non-interactive flags and the no-tty refusal → Tasks 2 and 9. Ordered execution with a single elevation and failure capture → Task 7. Linking with junctions and timestamped backups → Task 8. Verification steps → Tasks 9 and 10. The WezTerm configuration itself is deliberately absent; it is the first plan.

From `docs/specs/2026-08-01-installer-amendments-design.md`: checks as a list with an optional per-method path → Task 3, consumed in Task 5. Three-valued row status → Task 5, rendered in Task 6, obeyed in Tasks 7 and 9. Success judged by re-probing rather than by exit code → Task 7. Docker rows told apart → Task 3. Linux verification executed in WSL → Task 9 Step 6, with the resulting claim in Task 10. Default branch renamed before any URL is published → Task 10 Step 1.

**Placeholder scan.** No `TBD`, no "similar to Task N", no "add error handling". Every code step carries the code. The one deliberate uncertainty — real macOS behaviour — is stated as an untested claim in the README rather than left as a gap.

**Type consistency.** Catalog rows expose `Id`, `Group`, `Label`, `Checks`, `Methods` from Task 3, and each method exposes `Platform`, `Manager`, `Scope`, `Install`, `CheckPath`, `Note`. `Resolve-Source` in Task 5 consumes them and returns `@{Method; Alternatives; Reason}`; `Test-RowStatus` in the same task returns `@{Status; Missing}` and is called again by `Invoke-Rows` in Task 7 through its injected `$StatusProbe`. `Get-CatalogView` sets `Resolved`, `Alternatives`, `Reason`, `Status`, `Missing`, `Selected`, and `Checks`, which is exactly what `Format-Menu` and `Invoke-MenuKey` read in Task 6 and what `Invoke-Rows` reads in Task 7. `Get-Environment` returns `Os`, `Arch`, `Privilege`, `Managers` in Task 4, and every later consumer uses exactly those names. `Test-CommandExists` from Task 4 is the default command probe in Task 5. `Get-LinkTargets` and `New-ConfigLink` from Task 8 are called in Task 9 with the `Target`/`Source`/`Action`/`Backup` names Task 8 defines. The POSIX state record has the same twelve fields wherever it is built or read — Tasks 6, 7 and 9 — with `install` last because it is the only field that may contain a `|`: `selected|id|group|label|manager|scope|reason|status|missing|checks|checkpath|install`.

**Known gaps, carried deliberately.**
1. The macOS installer cannot be executed on its target system from here. Its rows are written against Homebrew and sdkman and are exercised only as syntax. Linux no longer shares this gap: Task 9 Step 6 runs `install.sh` on Ubuntu under WSL, including a real apt install and the link phase. The sdkman and AppImage rows remain unexercised even there, since the WSL runs install through apt.
2. `install/lib/ui.sh` renders `render_menu` inside a pipeline subshell, so its `group` tracking resets per invocation rather than persisting — this is correct for a full redraw but means the function cannot be used incrementally. If partial redraws are ever wanted, the loop needs restructuring to a here-document.
