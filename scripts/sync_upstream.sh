#!/usr/bin/env bash
# Brings the latest Musify changes into Ongaku.
#
# Ongaku keeps its own code in lib/ongaku/ and touches upstream files as little
# as possible (see ONGAKU.md), so merges are normally conflict-free. If a
# conflict does happen, it is in one of the small "Ongaku:" hooks listed there.
#
# Usage: scripts/sync_upstream.sh [upstream-branch]   (default: master)
set -euo pipefail

UPSTREAM_URL="https://github.com/gokadzev/Musify.git"
BRANCH="${1:-master}"

git remote get-url upstream >/dev/null 2>&1 || git remote add upstream "$UPSTREAM_URL"
git fetch upstream "$BRANCH"

if git merge-base --is-ancestor "upstream/$BRANCH" HEAD; then
  echo "Already up to date with Musify."
  exit 0
fi

echo "Merging upstream/$BRANCH ..."
git merge --no-edit "upstream/$BRANCH" || {
  echo
  echo "Merge conflict. Conflicts should only be in the 'Ongaku:' hooks:"
  git diff --name-only --diff-filter=U
  echo "Resolve them (keep both sides), then: git commit && scripts/verify.sh"
  exit 1
}

scripts/verify.sh
