#!/bin/sh
# Checks for bin/cto. Needs python3 >= 3.8 and git; nothing else. All state lives in a mktemp
# directory and HOME is redirected into it, so your own ~/.claude and ~/.codex are never touched.
#
#   tests/run-cto.sh                 test the working tree
#   CTO_BIN=/path/to/cto tests/run-cto.sh    test another bin/cto (for example `git show <rev>:bin/cto`)
#
# One line per check; exit status is non-zero when any check fails.
set -u
here=$(cd "$(dirname "$0")" && pwd)
command -v git >/dev/null 2>&1 || { echo "git is required" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 is required" >&2; exit 2; }
python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 8) else 1)' ||
  { echo "python3 >= 3.8 is required" >&2; exit 2; }
tmp=$(mktemp -d "${TMPDIR:-/tmp}/cto-tests.XXXXXX") || exit 2
trap 'rm -rf "$tmp"' EXIT INT TERM
CTO_TEST_TMP=$tmp python3 -B "$here/cto/run.py"
