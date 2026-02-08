#!/usr/bin/env bash
set -euo pipefail

# Installs git hooks from git-hooks/ into .git/hooks
# Usage: scripts/install-git-hooks.sh

HOOK_DIR="$(pwd)/git-hooks"
GIT_HOOKS_DIR="$(git rev-parse --git-dir)/hooks"

if [ ! -d "$GIT_HOOKS_DIR" ]; then
  echo "No .git/hooks directory found. Are you in a git repository?"
  exit 1
fi

echo "Installing git hooks from $HOOK_DIR to $GIT_HOOKS_DIR"
for hook in "$HOOK_DIR"/*; do
  name=$(basename "$hook")
  target="$GIT_HOOKS_DIR/$name"
  cp "$hook" "$target"
  chmod +x "$target"
  echo "Installed $name"
done

echo "Done."
