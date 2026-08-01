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
  [ "$DRY_RUN" = "1" ] || git -C "$REPO_ROOT" pull --ff-only
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

echo
echo 'configs linked. WezTerm and Neovim themselves are not installed by this script.'
echo 'requirements: WezTerm nightly, Neovim 0.10+, JetBrainsMono Nerd Font.'
