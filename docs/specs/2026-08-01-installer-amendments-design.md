# Installer Amendments Design

Amends: `docs/plans/2026-08-01-dotfiles-installer.md`
Spec it extends: `docs/specs/2026-08-01-wezterm-dotfiles-design.md`

The installer plan was written before the WezTerm configuration existed and
before anyone had run its catalog against a real machine. Reading its rows
against this one turned up three places where a row reports a state that is not
true, and one place where the plan claims less coverage than the machine can
actually provide. The plan stands otherwise: four phases, both shells, pure
functions over injected inputs, catalog as data.

## 1. A row's checks are a list, not a command

**Today.** Each row carries `Check`, a single command whose presence means
installed.

**The problem.** `toolbelt` installs nine tools — ripgrep, fd, fzf, bat, eza,
zoxide, lazygit, gh, jq — behind `Check='rg'`. On a machine with ripgrep but
without bat, the row reports installed and bat never arrives. A partial install
is invisible and permanent. `nerdfont` and `dotfiles` carry `Check=''`, which no
probe can satisfy, so they can never report done.

**The change.** A row carries:

- `Checks` — every command the row provides. `toolbelt` lists all nine.
- `CheckPath` — optional. A path whose existence means the row is done, for the
  rows that install no command: the font file for `nerdfont`, the
  `~/.config/wezterm` link for `dotfiles`.

A row is **installed** when every check passes, **partial** when some do, and
**missing** when none do. The menu renders partial distinctly from both
neighbours, and partial rows arrive selected: they are the rows with work left.

The path prober is injected exactly as the command prober is, so resolution
stays pure and testable and nothing reads the real filesystem at import time.

## 2. Success is measured by the checks, not the exit code

**Today.** `Invoke-Rows` records a row as failed when its install command exits
non-zero.

**The problem.** This is wrong for exactly the rows the previous section
introduces. Re-running `scoop install main/ripgrep main/bat` where ripgrep is
already present exits non-zero, and the summary would report a failure for a run
that did precisely what was asked. Every partial row would fail on every run.

**The change.** A row succeeds when its checks pass after its command has run.
The exit code and captured output become the *reason* attached to a failure, not
the verdict. This makes re-running the installer honest, which is the normal
case once a machine is half set up, and it costs one extra probe per row.

## 3. The docker rows get checks that tell them apart

**Today.** `docker-desktop` and `docker-cli` both carry `Check='docker'`, so
installing either marks both installed and the second row can never be offered.

**The change.** `docker-desktop` is identified by a path — the application
itself — and `docker-cli` keeps the `docker` command. They are different things:
one is a daemon with a GUI, the other a client binary.

## 4. Linux verification moves from claimed to executed

**Today.** The plan carries a known gap: the macOS and Linux installers cannot
be executed on their target systems, and Git Bash exercises POSIX syntax and
control flow but never a real package manager.

**The change.** This machine has WSL Ubuntu-24.04. `install.sh` is executed
there for real, with the results recorded in the task that runs them:

1. `--dry-run --all`, which must resolve every row without touching anything.
2. `--only git,neovim --yes`, a live install through apt. `git` is already
   present in that distro and `neovim` is not, so one run covers both the
   installed path and the missing path.
3. `--only dotfiles --yes`, which clones and links, then a second run of the
   same to prove re-linking replaces rather than fails, and that an existing
   config directory is renamed rather than removed.

Real apt, real symlinks, real downloads, mutating that distro alone and never
Windows.

macOS remains unverified. The README says so plainly rather than implying
coverage the work does not have. Git Bash still covers the POSIX paths that run
under Windows, which is what the sdkman row needs.

## 5. The default branch is renamed before the URLs are written

The repository was pushed with `master` as its default branch; the plan's
bootstrap one-liners and the design spec both fetch from `/main/`. The branch is
renamed to `main` and pushed before Task 9 writes any entry point, so the
one-liners are correct when written rather than corrected afterwards.

## Interfaces affected

| Task | Change |
| --- | --- |
| 3 — catalog | `Check` becomes `Checks` (array) plus optional `CheckPath`. `Test-Catalog` validates that every row has at least one of the two. |
| 5 — resolver | `Get-CatalogView` takes a path prober alongside the command prober and sets `Status` of `installed`, `partial` or `missing` in place of the `Installed` boolean. |
| 6 — menu | Renders three states rather than two. Partial rows start selected. |
| 7 — execution | Verdict comes from re-probing the checks; exit code and output become the failure reason. |
| 9 — entry points | Verification runs `install.sh` inside WSL Ubuntu-24.04. |
| 10 — README | States that macOS is unverified, and carries `main` URLs. |

Tasks 1, 2, 4 and 8 are untouched.

## Out of scope

Splitting `toolbelt` into one row per tool. The bundle stays a bundle; the
checks simply tell the truth about it.

Any change to the four-phase architecture, the preference for user scope over
elevation, the single elevation for machine-scope rows, or the timestamped
backup rule for linking. Those were settled by the original spec and nothing
found here disturbs them.
