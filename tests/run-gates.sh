#!/usr/bin/env bash
# Checks for templates/os-verify-state.sh and templates/os-verify-mutation.sh. Needs git and
# python3 >= 3.8. The make-cache check also needs make, and the assert check needs cc; without
# them those checks print SKIP. Checks that force a failed restore are skipped as root, because
# root ignores the file permissions they rely on. All state lives in a mktemp directory, and gh
# is a fake this script writes there, so nothing reaches GitHub.
#
#   tests/run-gates.sh                          run every check under the bash on PATH
#   tests/run-gates.sh /bin/bash /opt/homebrew/bin/bash    run every check under each bash given
#   GATES_TEMPLATES=/path/to/templates tests/run-gates.sh  test other copies of the two scripts
#
# One line per check: PASS, FAIL or SKIP, the bash it ran under, and the check's name. Exit status
# is 1 when any check fails and 2 when the prerequisites are missing.
set -u
# The scripts change behaviour on CI and GITHUB_PR_NUMBER, and gh reads the GH_* variables. Start
# every run from none of them, so a CI runner sees the same checks as a laptop; checks that need
# one set it themselves.
unset CI GITHUB_PR_NUMBER GH_REPO GH_HOST GH_TOKEN GITHUB_TOKEN
here=$(cd "$(dirname "$0")" && pwd)
TEMPLATES=${GATES_TEMPLATES:-$here/../templates}
TEMPLATES=$(cd "$TEMPLATES" && pwd) || { echo "no templates directory at $TEMPLATES" >&2; exit 2; }
command -v git >/dev/null 2>&1 || { echo "git is required" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 is required" >&2; exit 2; }
python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 8) else 1)' ||
  { echo "python3 >= 3.8 is required" >&2; exit 2; }

if [ "$#" -eq 0 ]; then set -- "$(command -v bash)"; fi
for b in "$@"; do
  [ -x "$b" ] || { echo "not an executable bash: $b" >&2; exit 2; }
done

WORK=$(mktemp -d "${TMPDIR:-/tmp}/gates-tests.XXXXXX") || exit 2
trap 'chmod -R u+w "$WORK" 2>/dev/null; rm -rf "$WORK"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

. "$here/gates/lib.sh"
. "$here/gates/mutation.sh"
. "$here/gates/state.sh"

setup_fake_gh
for B in "$@"; do
  LABEL="bash-$("$B" -c 'echo "${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]}"')"
  mutation_checks
  state_checks
done

echo "$PASSES passed, $FAILS failed, $SKIPS skipped"
[ "$FAILS" -eq 0 ]
