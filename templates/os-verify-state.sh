#!/usr/bin/env bash
# Verify that .os/state.md describes a repository that actually exists: every pull request it
# names is open, every open pull request is named, and every backticked token containing a slash and
# no whitespace names a repository path or branch unless it is a URL or scp-style remote. The whole
# token is tried first; a trailing line or line-and-column suffix is treated as a source location
# only when the exact token does not exist. `--write` regenerates the fenced list of open pull-request
# numbers and safe head-branch names under "## In flight".
#
# Usage: ./verify-state.sh [--write]
#
# Why this runs at all: a commit touching only .os/state.md goes straight to the default branch
# without review, because a pull request whose own state file says "this PR is in flight" is
# wrong the moment it merges. That exemption removes the only human check on the file, so this
# script is what stands between a stale claim and a file everyone trusts.
#
# Things worth knowing before changing it:
# - A `pull_request` build checks out a merge commit for a PR that, by definition, cannot yet be
#   named in state.md. Rather than skip the completeness assertion on every such build, this
#   script drops the build's own PR number (passed in as GITHUB_PR_NUMBER) from the open-PR list
#   before comparing. A second, unrelated open PR left unnamed during that same build still
#   fails it.
# - `gh` can be missing or unauthenticated. Local runs warn and skip the two pull-request
#   assertions; CI fails closed because a skipped assertion there would read as verification.
# - CI checkouts fetch only the ref the build needs, so branch existence cannot be read from
#   local refs alone. `git ls-remote` asks the remote directly and works whatever was checked out.
# - `--write` replaces only the lines between the two fence markers. It never touches the rest of
#   the section, and it deliberately does not run the assertions below. Those compare the file
#   against GitHub too, and running them here would make the one tool meant to fix drift refuse
#   to do so because drift already exists.
# - The fence's shape is checked before anything else, gh available or not. A missing or malformed
#   fence is a broken file rather than a stale one, and reaching GitHub has nothing to do with it.
# - The branch-and-path assertion skips the generated block's contents. Those branch names come
#   from GitHub and a merge deletes a branch before the block naming it is rewritten, which is a
#   gap with a known owner rather than staleness this script should judge. The fence shape stays
#   checked unconditionally, so a malformed block still fails; only its content is out of scope.
# - No bash arrays. macOS ships bash 3.2, which mishandles an empty array under `set -u`, so
#   lists live in temp files instead.
set -euo pipefail

SELF="$(basename "${BASH_SOURCE[0]}")"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE="$ROOT/.os/state.md"

WRITE=false
case "${1:-}" in
  "") ;;
  --write) WRITE=true ;;
  *) echo "FAILED — unknown argument '$1'; usage: $SELF [--write]" >&2; exit 2 ;;
esac
[ "$#" -le 1 ] || { echo "FAILED — too many arguments; usage: $SELF [--write]" >&2; exit 2; }

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/$(basename "$ROOT")-state-verify.XXXXXX")"
cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

unexpected_error() {
  status=$?
  # HANDLED is set by checks that already printed a specific, actionable message.
  # Without it a deliberate failure reads as a crash, which trains people to ignore it.
  if [ "${HANDLED:-0}" = "1" ]; then exit "$status"; fi
  echo "FAILED — unexpected command failure at $SELF:$1 (exit $status)" >&2
  exit "$status"
}
trap 'unexpected_error $LINENO' ERR

fail() { HANDLED=1; echo "FAILED — $*" >&2; exit 1; }

[ -f "$STATE" ] || fail "$STATE does not exist"

# Whichever remote this repository actually uses. A fresh repository may have none, in which case
# branch checks fall back to local refs.
REMOTE="origin"
if ! git -C "$ROOT" remote get-url "$REMOTE" >/dev/null 2>&1; then
  REMOTE="$(git -C "$ROOT" remote | head -1)"
fi

GH_LIMIT=1000
gh_at_root() { (cd "$ROOT" && command gh "$@"); }

# Parses and, in write mode, rewrites the generated open-PR block under "## In flight". Kept as
# one program so the shape check and the writer can never drift into checking a different shape
# than the one being written.
cat > "$TMP_DIR/block.py" <<'PY'
import json, re, sys, pathlib

HEADING = "## In flight"
START = "<!-- verify-state:generated:start -->"
END = "<!-- verify-state:generated:end -->"
ENTRY_RE = re.compile(rb"^- PR #\d+(?: " + "—".encode("utf-8")
                      + rb" `[A-Za-z0-9._/-]+`)?\r?$")
BRANCH_RE = re.compile(r"^[A-Za-z0-9._/-]+$")

def fail(message):
    sys.stderr.write("FAILED — " + message + "\n")
    sys.exit(1)

mode, state_path = sys.argv[1], pathlib.Path(sys.argv[2])
text = state_path.read_bytes()
lines = text.split(b"\n")

def clean(line):
    return line.rstrip(b"\r").strip()

heading = HEADING.encode()
start_marker = START.encode()
end_marker = END.encode()
heading_idx = next((i for i, line in enumerate(lines) if clean(line) == heading), None)
if heading_idx is None:
    fail(f"'{HEADING}' is missing from .os/state.md; the generated open-PR block lives inside it")

section_end = len(lines)
for i in range(heading_idx + 1, len(lines)):
    if clean(lines[i]).startswith(b"## "):
        section_end = i
        break
section = lines[heading_idx + 1:section_end]

starts = [i for i, line in enumerate(lines) if clean(line) == start_marker]
ends = [i for i, line in enumerate(lines) if clean(line) == end_marker]
restore = (f"put one line `{START}`, the entries, and one line `{END}` under '{HEADING}', "
           "then run `./.os/verify-state.sh --write`")

if not starts or not ends:
    fail(f"the generated open-PR block is missing from '{HEADING}'; {restore}")
if len(starts) > 1 or len(ends) > 1:
    fail(f".os/state.md has more than one open-PR fence marker; {restore}")
start_abs, end_abs = starts[0], ends[0]
if not heading_idx < start_abs < section_end or not heading_idx < end_abs < section_end:
    fail(f"an open-PR fence marker is outside '{HEADING}'; {restore}")
if start_abs >= end_abs:
    fail(f"the open-PR fence in '{HEADING}' has its end before its start; {restore}")

content = lines[start_abs + 1:end_abs]

if mode == "locate":
    sys.exit(0)

# The content-format check runs only for `validate`. `write` locates the fences and replaces
# whatever is between them without judging it first, which is what repairs a block a previous run
# left malformed or stale. Re-checking it here would make that impossible.
if mode == "validate":
    if not content:
        fail(f"the open-PR block under '{HEADING}' is empty; it must contain '- none' or at "
             f"least one '- PR #<number> — `<branch>`' line; {restore}")
    if [clean(line) for line in content] != [b"- none"]:
        for line in content:
            if not ENTRY_RE.fullmatch(line):
                fail(f"'{HEADING}' has a line inside the open-PR block that doesn't fit "
                     f"'- PR #<number> — `<branch>`', '- PR #<number>', or '- none': "
                     f"{line!r}; {restore}")
    if len(sys.argv) >= 4:
        visible = lines[:start_abs + 1] + lines[end_abs:]
        pathlib.Path(sys.argv[3]).write_bytes(b"\n".join(visible))
    sys.exit(0)

try:
    prs = json.loads(pathlib.Path(sys.argv[3]).read_text(encoding="utf-8"))
    if not isinstance(prs, list):
        raise TypeError
    for pr in prs:
        if (not isinstance(pr, dict) or isinstance(pr.get("number"), bool)
                or not isinstance(pr.get("number"), int)
                or not isinstance(pr.get("headRefName", ""), str)):
            raise TypeError
    prs.sort(key=lambda pr: pr["number"])
except (OSError, UnicodeError, json.JSONDecodeError, TypeError):
    fail("gh returned malformed JSON for open pull requests")
line_suffix = b"\r" if lines[start_abs].endswith(b"\r") else b""
new_content = []
for pr in prs:
    line = f"- PR #{pr['number']}"
    branch = pr.get("headRefName", "")
    if BRANCH_RE.fullmatch(branch):
        line += f" — `{branch}`"
    new_content.append(line.encode("utf-8") + line_suffix)
if not new_content:
    new_content = [b"- none" + line_suffix]

new_lines = lines[:start_abs + 1] + new_content + lines[end_abs:]
new_text = b"\n".join(new_lines)

if new_text == text:
    print("UNCHANGED")
else:
    state_path.write_bytes(new_text)
    print("CHANGED")
PY

if $WRITE; then
  # Locate the block before reaching GitHub. Its contents may be stale or malformed because this
  # mode replaces them, but the owning section and the two markers must still be unambiguous.
  python3 "$TMP_DIR/block.py" locate "$STATE" || exit 1
  echo "==> Writing the open-PR block from GitHub"
  command -v gh >/dev/null 2>&1 || fail "gh is required for --write; install it and retry."
  gh_at_root auth status >/dev/null 2>&1 || fail "gh is not authenticated; run 'gh auth login' and retry."
  if ! gh_at_root pr list --state open --limit "$GH_LIMIT" --json number,headRefName 2>"$TMP_DIR/gh-err" \
      > "$TMP_DIR/open-prs.json"; then
    fail "'gh pr list' failed: $(cat "$TMP_DIR/gh-err"). Check 'gh auth status' and retry."
  fi
  pr_count="$(python3 - "$TMP_DIR/open-prs.json" <<'PY'
import json
import pathlib
import sys

try:
    value = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
    if not isinstance(value, list):
        raise TypeError
except (OSError, UnicodeError, json.JSONDecodeError, TypeError):
    sys.stderr.write("FAILED — gh returned malformed JSON for open pull requests\n")
    raise SystemExit(1)
print(len(value))
PY
  )" || exit 1
  [ "$pr_count" -lt "$GH_LIMIT" ] \
    || fail "'gh pr list' returned the limit of $GH_LIMIT open PRs; completeness cannot be verified. Raise the limit before trusting this result."
  # `write` locates the fences itself and fails the same way `validate` does when they are
  # missing, duplicated or out of order. It does not otherwise judge what was between them.
  result="$(python3 "$TMP_DIR/block.py" write "$STATE" "$TMP_DIR/open-prs.json")" || exit 1
  case "$result" in
    CHANGED)   echo "    regenerated — .os/state.md changed" ;;
    UNCHANGED) echo "    unchanged — already matches GitHub" ;;
    *) fail "unexpected output from the block writer: $result" ;;
  esac
  exit 0
fi

echo "==> Checking the generated open-PR block's shape"
# Runs whether or not gh is available: a missing or malformed fence is a broken file regardless
# of whether GitHub can be reached to judge its content.
python3 "$TMP_DIR/block.py" validate "$STATE" "$TMP_DIR/state-visible.md" || exit 1
echo "    ok   fence present, well-formed"

echo "==> Reading .os/state.md"

grep -oE 'PR #[0-9]+' "$STATE" | grep -oE '[0-9]+' | sort -un > "$TMP_DIR/named-prs" || true
named_count="$(wc -l < "$TMP_DIR/named-prs" | tr -d ' ')"
if [ "$named_count" = "0" ]; then
  echo "    pull requests named: none"
else
  echo "    pull requests named: $(sed 's/^/#/' "$TMP_DIR/named-prs" | tr '\n' ' ')"
fi

HANDLED=1
gh_ok=true
if ! command -v gh >/dev/null 2>&1; then
  if [ -n "${CI:-}" ]; then
    fail "gh is not installed; CI cannot skip the pull-request assertions."
  else
    echo "WARNING — gh is not installed; skipping the pull-request assertions." >&2
    gh_ok=false
  fi
elif ! gh_at_root auth status >/dev/null 2>&1; then
  if [ -n "${CI:-}" ]; then
    fail "gh is not authenticated; CI cannot skip the pull-request assertions."
  else
    echo "WARNING — gh is not authenticated; skipping the pull-request assertions." >&2
    gh_ok=false
  fi
elif [ -z "$REMOTE" ]; then
  # A repository with no remote has no pull requests to compare against. Skipping keeps a freshly
  # scaffolded project green instead of red for a reason the operator cannot act on.
  echo "WARNING — this repository has no remote; skipping the pull-request assertions." >&2
  gh_ok=false
fi
HANDLED=0

if $gh_ok; then
  echo "==> Checking every pull request named in the file is open"
  while IFS= read -r n; do
    [ -n "$n" ] || continue
    if ! state="$(gh_at_root pr view "$n" --json state -q .state 2>"$TMP_DIR/gh-err")"; then
      fail "PR #$n is named in .os/state.md but 'gh pr view' failed: $(cat "$TMP_DIR/gh-err"). Fix the number, remove the entry, or check gh's authentication."
    fi
    [ "$state" = "OPEN" ] \
      || fail "PR #$n is named in .os/state.md as in flight, but its actual state is $state. Update .os/state.md to say what happened to it."
  done < "$TMP_DIR/named-prs"
  echo "    ok   $named_count named PR(s), all open"

  echo "==> Checking every open pull request is named in the file"
  if ! gh_at_root pr list --state open --limit "$GH_LIMIT" --json number -q '.[].number' 2>"$TMP_DIR/gh-err" \
      | sort -un > "$TMP_DIR/open-prs"; then
    fail "'gh pr list' failed: $(cat "$TMP_DIR/gh-err"). Check 'gh auth status' and retry."
  fi
  open_count="$(wc -l < "$TMP_DIR/open-prs" | tr -d ' ')"
  [ "$open_count" -lt "$GH_LIMIT" ] \
    || fail "'gh pr list' returned the limit of $GH_LIMIT open PRs; completeness cannot be verified. Raise the limit before trusting this result."
  # This build's own PR cannot be named in a file it is not allowed to modify. Dropping it here,
  # rather than skipping the whole assertion, still catches an unrelated PR left unnamed during
  # the same build.
  self_pr="${GITHUB_PR_NUMBER:-}"
  cp "$TMP_DIR/named-prs" "$TMP_DIR/named-prs-plus-self"
  if [ -n "$self_pr" ]; then echo "$self_pr" >> "$TMP_DIR/named-prs-plus-self"; fi
  sort -un -o "$TMP_DIR/named-prs-plus-self" "$TMP_DIR/named-prs-plus-self"
  # PR numbers are integers, so the set difference is computed as integers. `comm` compares its
  # input lexically: fed these files, which are sorted numerically, it puts "10" before "8" and
  # "9", calls that sorted, and misreports the difference for every open/named split crossing a
  # digit boundary. Sorting lexically instead would satisfy `comm` at the cost of printing
  # 10, 8, 9 to whoever has to read it.
  python3 - "$TMP_DIR/open-prs" "$TMP_DIR/named-prs-plus-self" > "$TMP_DIR/missing-prs" <<'PY'
import sys

with open(sys.argv[1]) as f:
    open_prs = {int(line) for line in f if line.strip()}
with open(sys.argv[2]) as f:
    named_prs = {int(line) for line in f if line.strip()}

for n in sorted(open_prs - named_prs):
    print(n)
PY
  if [ -s "$TMP_DIR/missing-prs" ]; then
    echo "    Open but not named in .os/state.md:" >&2
    sed 's/^/      - PR #/' "$TMP_DIR/missing-prs" >&2
    fail "add the pull request(s) above under 'In flight', or close them if they are stale."
  fi
  if [ -n "$self_pr" ]; then
    echo "    ok   $open_count open PR(s) checked, excluding this build's own PR #$self_pr"
  else
    echo "    ok   $open_count open PR(s), all named"
  fi
else
  echo "==> Skipping the two pull-request assertions"
fi

# A path and a branch name look the same in this file's prose. Both are `word/word` in backticks,
# so one pass checks each token against both possibilities: a real path wins first, a real branch
# wins second, and a token that is neither fails naming what it is.
echo "==> Checking backticked slash tokens as repository paths or branches, local or on the remote"
# The block parser also writes the visible copy, so fence validation and content exclusion use
# one definition of the generated block.
grep -oE '`[^`[:space:]]+`' "$TMP_DIR/state-visible.md" | sed -E 's/^`//; s/`$//' | grep '/' | sort -u > "$TMP_DIR/candidates" || true

# Slash-containing backtick tokens that are neither a real repository path nor a branch, and are
# not already excluded by the no-whitespace rule above. A command line with a package name in it
# is the usual case. Printed every run so the exemption gets reviewed by whoever reads this
# output, instead of being buried in the script. Starts empty.
cat > "$TMP_DIR/ignore" <<'IGNORE'
IGNORE

: > "$TMP_DIR/missing-paths"
checked=0
ignored=0

reference_exists() {
  local reference="$1"
  if [ -e "$ROOT/$reference" ] && python3 - "$ROOT" "$ROOT/$reference" <<'PY'
import os, sys
root = os.path.realpath(sys.argv[1])
path = os.path.realpath(sys.argv[2])
raise SystemExit(0 if os.path.commonpath([root, path]) == root else 1)
PY
  then
    return 0
  fi
  if git -C "$ROOT" show-ref --verify --quiet "refs/heads/$reference"; then return 0; fi
  if [ -n "$REMOTE" ]; then
    if [ ! -f "$TMP_DIR/remote-branches" ]; then
      if ! git -C "$ROOT" ls-remote --heads "$REMOTE" > "$TMP_DIR/remote-branches.raw"; then
        fail "could not reach the remote '$REMOTE' to verify branch names. Check network access and authentication, then retry."
      fi
      awk '{print $2}' "$TMP_DIR/remote-branches.raw" > "$TMP_DIR/remote-branches"
    fi
    if grep -qxF -e "refs/heads/$reference" "$TMP_DIR/remote-branches"; then return 0; fi
  fi
  return 1
}

while IFS= read -r token; do
  [ -n "$token" ] || continue
  case "$token" in
    *://*) continue ;;
  esac
  if printf '%s\n' "$token" | grep -Eq '^[^/:@[:space:]]+@[^/:[:space:]]+:'; then
    continue
  fi
  if grep -qxF -e "$token" "$TMP_DIR/ignore"; then
    ignored=$((ignored + 1))
    continue
  fi
  checked=$((checked + 1))
  if reference_exists "$token"; then continue; fi
  reference="$(printf '%s\n' "$token" | sed -E 's/:[0-9]+(:[0-9]+)?$//')"
  if [ "$reference" != "$token" ] && reference_exists "$reference"; then continue; fi
  echo "$token" >> "$TMP_DIR/missing-paths"
done < "$TMP_DIR/candidates"

if [ "$ignored" -gt 0 ]; then
  echo "    ignored ($ignored): $(tr '\n' ' ' < "$TMP_DIR/ignore")"
else
  echo "    ignored (0): none"
fi
if [ -s "$TMP_DIR/missing-paths" ]; then
  echo "Named in .os/state.md but neither a repository path nor a branch (local or on the remote):" >&2
  sed 's/^/  - `/; s/$/`/' "$TMP_DIR/missing-paths" >&2
  fail "update .os/state.md after the rename or deletion, or add a deliberate exemption to the ignore list."
fi
echo "    ok   $checked backticked slash token(s) checked"

echo
echo "VERIFICATION PASSED"
echo "  This check does not read whether a named PR's description still matches what its"
echo "  branch contains, whether a branch is the right one for the work attached to it, or"
echo "  anything in the file's prose that is not a PR number or a backticked slash token"
echo "  without whitespace, unless that token is a URL or scp-style remote."
