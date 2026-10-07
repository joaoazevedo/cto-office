#!/usr/bin/env bash
# Break one line on purpose, run gates, and require at least one gate to notice.
#
# Usage:
#   ./verify-mutation.sh --file <path> --replace <literal> --with <literal> --gate <command>...
#   ./verify-mutation.sh --file <path> --delete-line <ere>                  --gate <command>...
#
# Why this runs at all: a gate that passes and a gate that had nothing to check produce identical
# output. So does a gate wired into no workflow, a test that reads its subject matter from the
# file its subject matter is missing from, and a patch that silently failed to apply. Each of
# those reads as confirmation. The only way to tell them apart is to break the thing the gate
# guards and watch the gate fail, and this is that, as a command rather than as a discipline.
#
# Exit codes:
#
#   0  PASSED   a gate failed with the mutation applied, so it is load-bearing
#   1  FAILED   every gate stayed green, so nothing guards the mutated line
#   2  FATAL    refused to run, a baseline gate was red, or a mutated run was interrupted
#   3  FAILED   the mutation matched nothing, so no gate was given anything to catch
#   4  FATAL    the target could not be restored, whether or not the mutation was applied
# 129  FATAL    interrupted by HUP; the file was restored
# 130  FATAL    interrupted by INT; the file was restored
# 143  FATAL    interrupted by TERM; the file was restored
#
# Exit 3 is the one that earns the script. A mutation that does not apply produces a green run
# indistinguishable from proof, so the file is read back and byte-compared rather than trusted to
# any tool's exit code. Exit 2 covers the mirror image: a gate that was red before the mutation
# would have been red after it, and reading that as a catch is the same mistake pointing the other
# way.
#
# Things worth knowing before changing it:
# - `--gate` takes a whole shell command, not this script's idea of one. It knows nothing about
#   your package manager, your task runner, or what your gates are called. `--gate 'make test'`
#   and `--gate 'npm run lint'` are both just strings handed to `sh -c`, which is also how a gate
#   that needs an environment variable in front of it gets one.
# - There is no default gate. A guess would be a project fact living in a tool that is not allowed
#   to hold one, and a wrong guess fails as a missing script rather than as a missing gate.
# - Build caches are the quiet failure here. A cached task did not run, and a task that did not run
#   cannot have noticed anything, so a mutation outside whatever the cache keys on comes back green
#   and reads as "no gate covers this". If your runner caches, defeat it in the gate string.
# - `cmd 2>&1 | head` reports head's exit status, not cmd's. Gate output goes to a file and `$?` is
#   read directly. Never put a pipe between a gate and its status.
# - A gate gets `/dev/null` on stdin. Anything that would prompt has to fail rather than block, and
#   without it a gate would eat the loop's own input.
# - It refuses symlinks, multiply linked files, and files with uncommitted changes. The backup
#   and restore trap exist before any gate runs, and a baseline gate that changes the target is
#   refused.
# - SIGKILL cannot be trapped. Under bash 3.2, SIGQUIT can also kill the shell without running the
#   restore trap. Either can leave the mutation in place, which is why the dirty guard exists.
# - Replacement is byte-for-byte. `--delete-line` uses the system's ERE implementation and keeps
#   every byte from lines that do not match, including CRLF endings.
# - No bash arrays. macOS ships bash 3.2, which mishandles an empty array under `set -u`, so lists
#   live in temp files instead.
set -euo pipefail

SELF="$(basename "${BASH_SOURCE[0]}")"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  sed -n '4,6p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

WORK="$(mktemp -d)"
GATE_LIST="$WORK/gates"
CAUGHT="$WORK/caught"
SURVIVED="$WORK/survived"
: >"$GATE_LIST"
: >"$CAUGHT"
: >"$SURVIVED"

FILE=""
REPLACE=""
WITH=""
WITH_SET=0
DELETE_LINE=""
DELETE_SET=0

while [ $# -gt 0 ]; do
  case "$1" in
    --file)        [ $# -ge 2 ] || { echo "FATAL: --file needs a path" >&2; exit 2; }
                   FILE="$2"; shift 2 ;;
    --replace)     [ $# -ge 2 ] || { echo "FATAL: --replace needs a literal" >&2; exit 2; }
                   REPLACE="$2"; shift 2 ;;
    --with)        [ $# -ge 2 ] || { echo "FATAL: --with needs a literal (\"\" to delete)" >&2; exit 2; }
                   WITH="$2"; WITH_SET=1; shift 2 ;;
    --delete-line) [ $# -ge 2 ] || { echo "FATAL: --delete-line needs a pattern" >&2; exit 2; }
                   DELETE_LINE="$2"; DELETE_SET=1; shift 2 ;;
    --gate)        [ $# -ge 2 ] || { echo "FATAL: --gate needs a command" >&2; exit 2; }
                   printf '%s\n' "$2" >>"$GATE_LIST"; shift 2 ;;
    -h|--help)     usage; exit 0 ;;
    *)             echo "FATAL: unknown argument $1" >&2; usage >&2; exit 2 ;;
  esac
done

[ -n "$FILE" ] || { echo "FATAL: --file is required" >&2; usage >&2; exit 2; }

if [ -n "$REPLACE" ] && [ "$DELETE_SET" -eq 1 ]; then
  echo "FATAL: --replace and --delete-line are two mutations; pass one" >&2; exit 2
fi
if [ -z "$REPLACE" ] && [ "$DELETE_SET" -eq 0 ]; then
  echo "FATAL: pass --replace <literal> --with <literal>, or --delete-line <ere>" >&2; exit 2
fi
if [ -n "$REPLACE" ] && [ "$WITH_SET" -eq 0 ]; then
  echo "FATAL: --replace needs --with; pass --with \"\" to delete the literal" >&2; exit 2
fi
if [ "$DELETE_SET" -eq 1 ] && [ "$WITH_SET" -eq 1 ]; then
  echo "FATAL: --with belongs to --replace, not to --delete-line" >&2; exit 2
fi

GATE_COUNT="$(wc -l <"$GATE_LIST" | tr -d ' ')"
if [ "$GATE_COUNT" -eq 0 ]; then
  echo "FATAL: --gate is required, and repeats. It takes the command you would type yourself:" >&2
  echo "         --gate 'make test'" >&2
  echo "         --gate 'npm run lint' --gate 'npm test'" >&2
  echo "       There is no default, because nothing here knows what your gates are called." >&2
  exit 2
fi

FILE_DIR="$(dirname "$FILE")"
[ -d "$FILE_DIR" ] || { echo "FATAL: $FILE — no such directory" >&2; exit 2; }
TARGET="$(cd "$FILE_DIR" && pwd -P)/$(basename "$FILE")"
[ ! -L "$TARGET" ] || { echo "FATAL: $FILE is a symlink; refusing to mutate its referent." >&2; exit 2; }
[ -f "$TARGET" ] || { echo "FATAL: $FILE — no such file" >&2; exit 2; }
if [ -n "$(find "$TARGET" -links +1 -print)" ]; then
  echo "FATAL: $FILE has more than one hard link; refusing to break the other name on restore." >&2
  exit 2
fi

GIT_TOPLEVEL="$(git -C "$ROOT" rev-parse --show-toplevel 2>/dev/null)" || {
  echo "FATAL: $ROOT is not inside a git repository." >&2
  exit 2
}
TRACKED="$WORK/tracked"
if ! git -C "$GIT_TOPLEVEL" -c core.quotePath=false --literal-pathspecs \
    ls-files -z --full-name --error-unmatch -- "$TARGET" >"$TRACKED" 2>/dev/null; then
  echo "FATAL: $FILE is not tracked by git, so there is nothing to restore it from." >&2
  exit 2
fi
RELATIVE_PATH="$WORK/relative"
if ! python3 - "$TRACKED" "$RELATIVE_PATH" <<'PY'
import pathlib
import sys

paths = pathlib.Path(sys.argv[1]).read_bytes().split(b"\0")
if paths and paths[-1] == b"":
    paths.pop()
if len(paths) != 1:
    raise SystemExit(2)
pathlib.Path(sys.argv[2]).write_bytes(paths[0])
PY
then
  echo "FATAL: $FILE did not resolve to exactly one tracked file." >&2
  exit 2
fi
# The sentinel prevents command substitution from stripping newlines that belong to the path.
RELATIVE="$({ cat "$RELATIVE_PATH"; printf '/'; })"
RELATIVE="${RELATIVE%/}"

if [ -n "$(git -C "$GIT_TOPLEVEL" --literal-pathspecs status --porcelain -- "$RELATIVE")" ]; then
  echo "FATAL: $RELATIVE has uncommitted changes." >&2
  echo "       $SELF rewrites the file and restores it from a copy. Commit or stash first, so a" >&2
  echo "       failed restore cannot eat work that is not in git." >&2
  exit 2
fi

MUTATION="$([ -n "$REPLACE" ] \
  && printf "replace '%s' with '%s'" "$REPLACE" "$WITH" \
  || printf "delete lines matching '%s'" "$DELETE_LINE")"

# Fail on a typo before spending a whole gate sweep on it. The byte comparison after the write is
# still the assertion that decides, because a match can still write nothing back.
if [ -n "$REPLACE" ]; then
  if ! HITS="$(python3 - "$TARGET" "$REPLACE" <<'DRY'
import os
import pathlib
import sys

data = pathlib.Path(sys.argv[1]).read_bytes()
print(data.count(os.fsencode(sys.argv[2])))
DRY
  )"; then
    echo "FATAL: could not read $RELATIVE to count the replacement." >&2
    exit 2
  fi
  MATCH="the literal '$REPLACE'"
else
  set +e
  HITS="$(LC_ALL=C grep -acE -e "$DELETE_LINE" "$TARGET" 2>"$WORK/pattern-error")"
  GREP_STATUS=$?
  set -e
  if [ "$GREP_STATUS" -eq 2 ]; then
    echo "FATAL: --delete-line is not a valid extended regular expression: $DELETE_LINE" >&2
    sed 's/^/       /' "$WORK/pattern-error" >&2
    exit 2
  fi
  [ "$GREP_STATUS" -le 1 ] || {
    echo "FATAL: could not read $RELATIVE to count matching lines." >&2
    exit 2
  }
  MATCH="the pattern '$DELETE_LINE'"
fi
if [ "$HITS" -eq 0 ]; then
  echo "FAILED — $MATCH is nowhere in $RELATIVE, so the mutation would be a no-op."
  echo "         Check it against the file, whitespace included:"
  echo "           grep -n <pattern> $RELATIVE"
  exit 3
fi
echo "==> $HITS site(s) in $RELATIVE match the mutation"

if [ "$DELETE_SET" -eq 1 ]; then
  FINAL_SEGMENT_SURVIVED=0
  if python3 - "$TARGET" "$WORK/final-segment" <<'PY'
import pathlib
import sys

data = pathlib.Path(sys.argv[1]).read_bytes()
if data.endswith(b"\n"):
    raise SystemExit(1)
pathlib.Path(sys.argv[2]).write_bytes(data.rsplit(b"\n", 1)[-1])
PY
  then
    set +e
    LC_ALL=C grep -qaE -e "$DELETE_LINE" "$WORK/final-segment" 2>"$WORK/final-pattern-error"
    FINAL_GREP_STATUS=$?
    set -e
    if [ "$FINAL_GREP_STATUS" -eq 1 ]; then
      FINAL_SEGMENT_SURVIVED=1
    elif [ "$FINAL_GREP_STATUS" -gt 1 ]; then
      echo "FATAL: could not check the final line in $RELATIVE." >&2
      sed 's/^/       /' "$WORK/final-pattern-error" >&2
      exit 2
    fi
  fi
fi

BACKUP="$WORK/backup"
cp -p "$TARGET" "$BACKUP"

RESTORE_FAILED=0
restore() {
  # Idempotent: the interrupt handler restores and then exits, which fires the EXIT trap too.
  [ -f "$BACKUP" ] || return 0
  if [ ! -L "$TARGET" ] && [ -f "$TARGET" ] && cmp -s "$BACKUP" "$TARGET" 2>/dev/null; then
    rm -f "$BACKUP"
    return 0
  fi
  if [ -L "$TARGET" ] || [ ! -f "$TARGET" ]; then
    rm -rf "$TARGET" 2>/dev/null || RESTORE_FAILED=1
  fi
  if [ "$RESTORE_FAILED" -eq 0 ]; then
    cp "$BACKUP" "$TARGET" 2>/dev/null || RESTORE_FAILED=1
  fi
  if [ "$RESTORE_FAILED" -eq 0 ] && ! cmp -s "$BACKUP" "$TARGET"; then
    RESTORE_FAILED=1
  fi
  if [ "$RESTORE_FAILED" -eq 1 ]; then
    echo >&2
    echo "FATAL: could not restore $RELATIVE. The backup has been kept at $BACKUP." >&2
    printf '       Run: git -C %q --literal-pathspecs checkout -- %q\n' \
      "$GIT_TOPLEVEL" "$RELATIVE" >&2
    exit 4
  fi
  rm -f "$BACKUP"
}
trap restore EXIT
trap 'restore; exit 130' INT
trap 'restore; exit 143' TERM

GATE_TAIL=""
GATE_LOG=""
GATE_INDEX=0
GATE_STATUS=0
# Built with printf rather than written as \x1b, which not every sed understands.
ESC="$(printf '\033')"
run_gate() {
  local gate="$1" phase="$2" status
  GATE_INDEX=$((GATE_INDEX + 1))
  GATE_LOG="$WORK/$phase-$GATE_INDEX.log"
  set +e
  (cd "$ROOT" && sh -c "$gate") >"$GATE_LOG" 2>&1 </dev/null
  status=$?
  GATE_STATUS=$status
  set -e
  GATE_TAIL="$(sed "s/${ESC}\[[0-9;]*m//g" "$GATE_LOG" | tail -25 | sed 's/^/      | /')"
  return "$status"
}

echo "==> Baseline: $GATE_COUNT gate(s) on the tree as committed"
while IFS= read -r gate; do
  printf '  %-52s ' "$gate"
  if run_gate "$gate" baseline; then
    echo "PASSED"
  else
    if ! cmp -s "$BACKUP" "$TARGET"; then
      echo "FAILED"
      echo "$GATE_TAIL"
      echo "      full log: $GATE_LOG"
      echo >&2
      echo "FATAL: \`$gate\` modifies $RELATIVE during the baseline run." >&2
      echo "       A gate used to verify this file must leave it byte-identical." >&2
      restore
      exit 2
    fi
    echo "FAILED"
    echo "$GATE_TAIL"
    echo "      full log: $GATE_LOG"
    echo
    echo "FATAL: \`$gate\` is already red without the mutation, so nothing after this point" >&2
    echo "       would mean anything — a red gate stays red whatever is broken underneath it." >&2
    echo "       Get the gate green, then run this again." >&2
    exit 2
  fi
  if ! cmp -s "$BACKUP" "$TARGET"; then
    echo >&2
    echo "FATAL: \`$gate\` modifies $RELATIVE during the baseline run." >&2
    echo "       A gate used to verify this file must leave it byte-identical." >&2
    restore
    exit 2
  fi
done <"$GATE_LIST"

echo
echo "==> Mutating $RELATIVE: $MUTATION"
if [ -n "$REPLACE" ]; then
  if ! python3 - "$TARGET" "$REPLACE" "$WITH" <<'APPLY'
import os
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
old, new = os.fsencode(sys.argv[2]), os.fsencode(sys.argv[3])
data = path.read_bytes()
path.write_bytes(data.replace(old, new))
print(f"    {data.count(old)} occurrence(s) replaced")
APPLY
  then
    echo "FATAL: could not apply the replacement to $RELATIVE." >&2
    exit 2
  fi
else
  set +e
  LC_ALL=C grep -avE -e "$DELETE_LINE" "$TARGET" >"$WORK/mutated" 2>"$WORK/pattern-error"
  GREP_STATUS=$?
  set -e
  if [ "$GREP_STATUS" -gt 1 ]; then
    echo "FATAL: could not apply --delete-line to $RELATIVE." >&2
    sed 's/^/       /' "$WORK/pattern-error" >&2
    exit 2
  fi
  if ! python3 - "$BACKUP" "$WORK/mutated" "$FINAL_SEGMENT_SURVIVED" <<'PY'
import pathlib
import sys

original = pathlib.Path(sys.argv[1]).read_bytes()
mutated_path = pathlib.Path(sys.argv[2])
mutated = mutated_path.read_bytes()
# grep terminates an unterminated line in its output. Remove that byte only when the original's
# final segment survived as the output's final line; deleting that segment leaves the preceding
# line ending intact.
final_segment = original.rsplit(b"\n", 1)[-1]
if (sys.argv[3] == "1" and not original.endswith(b"\n")
        and mutated.endswith(final_segment + b"\n")):
    mutated_path.write_bytes(mutated[:-1])
PY
  then
    echo "FATAL: could not preserve the final-newline state in $RELATIVE." >&2
    exit 2
  fi
  if ! cp "$WORK/mutated" "$TARGET"; then
    echo "FATAL: could not write the line-deletion result to $RELATIVE." >&2
    exit 2
  fi
  echo "    $HITS line(s) deleted"
fi

# The assertion the rest of this run rests on. Read the file back and compare; the count printed
# above and the exit code both come from the tool that was asked to do the work.
if cmp -s "$BACKUP" "$TARGET"; then
  echo
  echo "FAILED — the mutation was a no-op. $RELATIVE is byte-identical afterwards, so no gate"
  echo "         was given anything to catch and this run proves nothing at all."
  echo "         Check the literal or the pattern against the file, whitespace included:"
  echo "           grep -n <pattern> $RELATIVE"
  exit 3
fi

echo
echo "==> Running the same $GATE_COUNT gate(s) against the mutated tree"
GATE_INDEX=0
while IFS= read -r gate; do
  printf '  %-52s ' "$gate"
  if run_gate "$gate" mutated; then
    echo "PASSED — did not notice"
    printf '%s\n' "$gate" >>"$SURVIVED"
  else
    case "$GATE_STATUS" in
      129|130|131|137|143)
        echo "FAILED"
        echo "$GATE_TAIL"
        echo "      full log: $GATE_LOG"
        echo >&2
        echo "FATAL: \`$gate\` was killed by a signal during the mutated run." >&2
        echo "       The run was interrupted, so this does not prove the gate caught the mutation." >&2
        if [ "$GATE_STATUS" -eq 137 ]; then
          echo "       An out-of-memory kill caused by the mutation would be a catch; judge that from the log." >&2
        fi
        restore
        exit 2
        ;;
    esac
    echo "FAILED — caught it"
    echo "$GATE_TAIL"
    echo "      full log: $GATE_LOG"
    printf '%s\n' "$gate" >>"$CAUGHT"
  fi
done <"$GATE_LIST"

CAUGHT_COUNT="$(wc -l <"$CAUGHT" | tr -d ' ')"

echo
if [ "$CAUGHT_COUNT" -gt 0 ]; then
  echo "PASSED — $MUTATION"
  echo "         in $RELATIVE was caught by $CAUGHT_COUNT of $GATE_COUNT gate(s):"
  sed 's/^/  - /' "$CAUGHT"
  echo "Those gates are load-bearing for that line. Nothing to do."
  echo "Logs: $WORK"
  exit 0
fi

echo "FAILED — nothing guards that line. Every gate stayed green with $RELATIVE mutated,"
echo "         and every one was green before it, so the mutation changed no outcome anywhere."
echo "  mutation: $MUTATION"
echo "  green with it applied:"
sed 's/^/    - /' "$SURVIVED"
echo
echo "Two things this can mean, and they are worth telling apart before you write anything."
echo "  1. No gate asserts that rule. Write the assertion, then run this again and watch it fail."
echo "  2. The gate that does assert it was not among the ones you named. The slow ones usually"
echo "     hold the rules a fast sweep cannot reach, so name the gate that owns this file and"
echo "     re-run before concluding the rule is unguarded."
echo "Logs: $WORK"
exit 1
