#!/bin/sh
# Clones this repository and links the WezTerm and Neovim configs into place.
#
# Run it directly, or through the one-liner in the README, which pipes it into
# sh before the repository exists on disk.
#
# It links configuration only. Installing WezTerm, Neovim and the rest is a
# separate installer, still to be built.
set -eu

REPO_URL='https://github.com/arthurpessoa/dotfiles'
REPO_ROOT="$HOME/.dotfiles"
DRY_RUN=0

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    -h|--help) echo 'usage: install.sh [--dry-run]'; exit 0 ;;
    *) echo "unknown option: $arg" >&2; exit 1 ;;
  esac
done

command -v git >/dev/null 2>&1 || { echo 'git is required and was not found on PATH' >&2; exit 1; }

if [ -d "$REPO_ROOT/.git" ]; then
  echo "updating $REPO_ROOT"
  # A pull can fail for reasons that have nothing to do with linking: local
  # commits, a renamed upstream branch, no network. None of those are a reason
  # to leave the configs unlinked, so the failure is reported and the run
  # continues with whatever is already checked out.
  if [ "$DRY_RUN" != "1" ] && ! git -C "$REPO_ROOT" pull --ff-only >/dev/null 2>&1; then
    echo "  could not pull; continuing with the checkout that is already there"
  fi
else
  echo "cloning $REPO_URL into $REPO_ROOT"
  [ "$DRY_RUN" = "1" ] || git clone "$REPO_URL" "$REPO_ROOT"
fi

STAMP=$(date +%Y%m%d-%H%M%S)

# link_config <target> <source> -> prints what it did. Never deletes: an
# existing config is renamed with a timestamp so a mistake stays recoverable.
link_config() {
  target="$1"
  source="$2"

  if [ -L "$target" ] && [ "$(readlink "$target")" = "$source" ]; then
    printf '%-42s %s\n' "$target" "already-linked"
    return 0
  fi

  action="linked"
  if [ -e "$target" ] || [ -L "$target" ]; then
    backup="$target.bak-$STAMP"
    [ "$DRY_RUN" = "1" ] || mv "$target" "$backup"
    action="backed-up-and-linked"
  fi

  [ "$DRY_RUN" = "1" ] || {
    mkdir -p "$(dirname "$target")"
    ln -s "$source" "$target"
  }

  printf '%-42s %s\n' "$target" "$action"
  [ "$action" = "backed-up-and-linked" ] && printf '  previous config kept at %s\n' "$backup"
  return 0
}

link_config "$HOME/.config/wezterm" "$REPO_ROOT/wezterm"
link_config "$HOME/.config/nvim" "$REPO_ROOT/nvim"

# The tools LazyVim's pickers and grep depend on. Package names differ per
# manager, and Debian's fd-find installs the binary as fdfind rather than fd,
# which is why the check below accepts either.
tool_package() {
  case "$1:$2" in
    fd:brew) echo fd ;;      fd:apt) echo fd-find ;;   fd:dnf) echo fd-find ;;   fd:pacman) echo fd ;;
    rg:brew) echo ripgrep ;; rg:apt) echo ripgrep ;;   rg:dnf) echo ripgrep ;;   rg:pacman) echo ripgrep ;;
    fzf:brew) echo fzf ;;    fzf:apt) echo fzf ;;      fzf:dnf) echo fzf ;;      fzf:pacman) echo fzf ;;
  esac
}

have_tool() {
  command -v "$1" >/dev/null 2>&1 && return 0
  [ "$1" = "fd" ] && command -v fdfind >/dev/null 2>&1
}

# Homebrew needs no root. The system managers do, and this script is routinely
# run through a pipe where a sudo password prompt has nowhere to read from --
# so root is used only when it is already available, and otherwise the exact
# command is printed for the reader to run.
install_tool() {
  tool="$1"

  if have_tool "$tool"; then
    printf '%-42s %s\n' "$tool" "already installed"
    return 0
  fi

  if command -v brew >/dev/null 2>&1; then
    manager=brew
    cmd="brew install $(tool_package "$tool" brew)"
  elif command -v apt-get >/dev/null 2>&1; then
    manager=apt
    cmd="apt-get install -y $(tool_package "$tool" apt)"
  elif command -v dnf >/dev/null 2>&1; then
    manager=dnf
    cmd="dnf install -y $(tool_package "$tool" dnf)"
  elif command -v pacman >/dev/null 2>&1; then
    manager=pacman
    cmd="pacman -S --noconfirm $(tool_package "$tool" pacman)"
  else
    printf '%-42s %s\n' "$tool" "no supported package manager found"
    return 0
  fi

  if [ "$DRY_RUN" = "1" ]; then
    printf '%-42s %s\n' "$tool" "would install with $manager"
    return 0
  fi

  if [ "$manager" = "brew" ]; then
    sh -c "$cmd" >/dev/null 2>&1 || true
  elif [ "$(id -u)" = "0" ]; then
    sh -c "$cmd" >/dev/null 2>&1 || true
  elif sudo -n true >/dev/null 2>&1; then
    sh -c "sudo $cmd" >/dev/null 2>&1 || true
  else
    printf '%-42s %s\n' "$tool" "needs root: sudo $cmd"
    return 0
  fi

  # Judged by whether the command answers now, not by the manager's exit code.
  if have_tool "$tool"; then
    printf '%-42s %s\n' "$tool" "installed with $manager"
  else
    printf '%-42s %s\n' "$tool" "failed: $cmd"
  fi
}

# Debian and Ubuntu ship the binary as fdfind, because fd was already taken.
# Neovim's pickers look for fd, so put one on PATH pointing at it rather than
# leaving a tool that is installed and still unusable.
shim_fd() {
  command -v fd >/dev/null 2>&1 && return 0
  command -v fdfind >/dev/null 2>&1 || return 0

  mkdir -p "$HOME/.local/bin"
  ln -sf "$(command -v fdfind)" "$HOME/.local/bin/fd"
  printf '%-42s %s\n' "  fd" "linked ~/.local/bin/fd -> $(command -v fdfind)"

  case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) printf '%-42s %s\n' "  fd" "note: ~/.local/bin is not on PATH" ;;
  esac
}

if [ "${DOTFILES_SKIP_TOOLS:-0}" != "1" ]; then
  echo
  for tool in fd rg fzf; do
    install_tool "$tool"
  done
  # Runs whether or not this script installed anything: a machine that already
  # had fd-find from some earlier day has the same unusable fdfind on it.
  [ "$DRY_RUN" = "1" ] || shim_fd
fi

echo
echo 'WezTerm and Neovim themselves are not installed by this script.'
echo 'requirements: WezTerm nightly, Neovim 0.10+, JetBrainsMono Nerd Font.'
echo 'in Neovim, :checkhealth reports anything still missing.'
