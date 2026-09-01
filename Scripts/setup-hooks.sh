#!/usr/bin/env sh

# One-shot bootstrap for the versioned git hooks in .githooks/.
# Eyrie has no npm toolchain, so instead of husky the hooks are plain sh
# wired in via core.hooksPath. Run once after cloning:
#
#   ./Scripts/setup-hooks.sh

set -e
cd "$(git rev-parse --show-toplevel)"

chmod +x .githooks/*
git config core.hooksPath .githooks

echo "✅ git hooks installed (core.hooksPath -> .githooks)"
