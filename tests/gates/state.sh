# Checks for templates/os-verify-state.sh. Sourced by tests/run-gates.sh.

# A project with .os/ installed from the templates and a bare repository as its origin. Prints the
# project path.
state_repo() {
  local d="$WORK/$1"
  rm -rf "$d" "$d.remote"
  mkdir -p "$d/.os"
  git -C "$d" init -q
  git init -q --bare "$d.remote"
  cp "$TEMPLATES/os-verify-state.sh" "$d/.os/verify-state.sh"
  cp "$TEMPLATES/os-state.md.tmpl" "$d/.os/state.md"
  G -C "$d" add -A
  G -C "$d" commit -qm init
  G -C "$d" branch -M main
  git -C "$d" remote add origin "$d.remote"
  G -C "$d" push -q origin main 2>/dev/null
  echo "$d"
}

# SV <PATH> [args]: run the script from / so a working directory inside the project cannot help it.
SV() { local p=$1; shift; (cd / && PATH="$p" "$B" "$D/.os/verify-state.sh" "$@"); }

reset_state() { cp "$WORK/state.orig" "$D/.os/state.md"; }

# Puts `<token>` in backticks under "## Focus" of the pristine file.
with_token() {
  python3 - "$WORK/state.orig" "$D/.os/state.md" "$1" <<'PY'
import sys
token = sys.argv[3].replace("\\r", "\r").replace("\\v", "\v")
text = open(sys.argv[1]).read().replace("## Focus\n", "## Focus\n\nSee `%s` here.\n" % token, 1)
open(sys.argv[2], "w").write(text)
PY
}

state_write_checks() {
  local rc diff
  printf '%s' '[{"number": 7, "headRefName": "feat/x"}, {"number": 9, "headRefName": "bad`name"}, {"number": 12, "headRefName": "evil\u2028## Focus"}, {"number": 13, "headRefName": "-f/dev/zero"}, {"number": 14, "headRefName": "a\nb"}]' > "$WORK/prs-hostile.json"
  FAKEGH_PRS="$WORK/prs-hostile.json" SV "$GH_PATH" --write >/dev/null 2>&1; rc=$?
  expect "state: --write keeps only numbers and safe branch names" \
    "0|- PR #7 — \`feat/x\`|- PR #9|- PR #12|- PR #13 — \`-f/dev/zero\`|- PR #14" \
    "$rc|$(sed -n '17,21p' "$D/.os/state.md" | paste -sd'|' -)"
  FAKEGH_PRS="$WORK/prs-hostile.json" SV "$GH_PATH" >/dev/null 2>&1; rc=$?
  expect "state: file written by --write validates" 0 "$rc"
  reset_state

  python3 - "$D/.os/state.md" <<'PY'
import sys
path = sys.argv[1]
data = open(path, "rb").read().replace(b"\n", b"\r\n")
data = data.replace(b"## Focus\r\n", b"## Focus\n\xe2\x80\xa8x\x0cy\x1cz\rq\r\n").rstrip(b"\r\n")
open(path, "wb").write(data)
PY
  cp "$D/.os/state.md" "$WORK/state.crlf"
  FAKEGH_PRS="$WORK/prs-hostile.json" SV "$GH_PATH" --write >/dev/null 2>&1; rc=$?
  diff=$(python3 - "$WORK/state.crlf" "$D/.os/state.md" <<'PY'
import difflib, sys
a = open(sys.argv[1], "rb").read().split(b"\n")
b = open(sys.argv[2], "rb").read().split(b"\n")
lines = difflib.unified_diff([repr(x) for x in a], [repr(x) for x in b], lineterm="", n=0)
print("|".join(l for l in lines if l[:1] in "+-" and l[:3] not in ("---", "+++")))
PY
)
  expect "state: --write on a CRLF file changes only the fenced lines" \
    "0 -b'- none\\r'|+b'- PR #7 \\xe2\\x80\\x94 \`feat/x\`\\r'|+b'- PR #9\\r'|+b'- PR #12\\r'|+b'- PR #13 \\xe2\\x80\\x94 \`-f/dev/zero\`\\r'|+b'- PR #14\\r'" \
    "$rc $diff"
  FAKEGH_PRS="$WORK/prs-hostile.json" SV "$GH_PATH" >/dev/null 2>&1; rc=$?
  expect "state: CRLF file validates after --write" 0 "$rc"
  reset_state
}

state_limit_and_gh_checks() {
  local rc i json
  python3 -c 'import json; print(json.dumps([{"number": i, "headRefName": "b%d" % i} for i in range(1, 1001)]))' > "$WORK/prs-1000.json"
  python3 -c 'import json; print(json.dumps([{"number": i, "headRefName": "b%d" % i} for i in range(1, 1000)]))' > "$WORK/prs-999.json"
  FAKEGH_PRS="$WORK/prs-1000.json" SV "$GH_PATH" --write >/dev/null 2>&1; rc=$?
  expect "state: --write refuses when gh returns the limit" 1 "$rc"
  FAKEGH_PRS="$WORK/prs-999.json" SV "$GH_PATH" --write >/dev/null 2>&1; rc=$?
  expect "state: --write accepts one below the limit" 0 "$rc"
  FAKEGH_PRS="$WORK/prs-999.json" SV "$GH_PATH" >/dev/null 2>&1; rc=$?
  expect "state: validate accepts one below the limit" 0 "$rc"
  FAKEGH_PRS="$WORK/prs-1000.json" SV "$GH_PATH" >/dev/null 2>&1; rc=$?
  expect "state: validate refuses when gh returns the limit" 1 "$rc"
  reset_state

  echo '[]' > "$WORK/prs-none.json"
  CI= SV "$NOGH_PATH" >/dev/null 2>&1; rc=$?
  expect "state: missing gh warns and skips locally" 0 "$rc"
  CI=true SV "$NOGH_PATH" >/dev/null 2>&1; rc=$?
  expect "state: missing gh fails in CI" 1 "$rc"
  CI= FAKEGH_AUTH=0 FAKEGH_PRS="$WORK/prs-none.json" SV "$GH_PATH" >/dev/null 2>&1; rc=$?
  expect "state: unauthenticated gh warns and skips locally" 0 "$rc"
  CI=true FAKEGH_AUTH=0 FAKEGH_PRS="$WORK/prs-none.json" SV "$GH_PATH" >/dev/null 2>&1; rc=$?
  expect "state: unauthenticated gh fails in CI" 1 "$rc"

  i=0
  for json in 'not json' '{"a":1}' '[{"number":"7"}]' '[{"number":7,"headRefName":null}]' '[1,2]' '' \
              '[{"number":true}]' '[{"number":false,"headRefName":"x"}]'; do
    i=$((i + 1))
    printf '%s' "$json" > "$WORK/bad-$i.json"
    FAKEGH_PRS="$WORK/bad-$i.json" SV "$GH_PATH" --write > "$WORK/out" 2>&1; rc=$?
    expect "state: malformed gh JSON '$json' fails cleanly" \
      "1|FAILED — gh returned malformed JSON for open pull requests|- none" \
      "$rc|$(tail -1 "$WORK/out")|$(sed -n 17p "$D/.os/state.md")"
    reset_state
  done

  printf '[{"number": 7, "headRefName": "feat/gone"}]' > "$WORK/prs-7.json"
  printf '[{"number": 7, "headRefName": "feat/gone"}, {"number": 8, "headRefName": "feat/self"}]' > "$WORK/prs-78.json"
  printf '[{"number": 7, "headRefName": "feat/gone"}, {"number": 8, "headRefName": "feat/self"}, {"number": 9, "headRefName": "x"}]' > "$WORK/prs-789.json"
  FAKEGH_PRS="$WORK/prs-7.json" SV "$GH_PATH" --write >/dev/null 2>&1
  GITHUB_PR_NUMBER=8 CI=true FAKEGH_PRS="$WORK/prs-78.json" SV "$GH_PATH" >/dev/null 2>&1; rc=$?
  expect "state: own PR and generated branch names are exempt" 0 "$rc"
  GITHUB_PR_NUMBER=8 CI=true FAKEGH_PRS="$WORK/prs-789.json" SV "$GH_PATH" >/dev/null 2>&1; rc=$?
  expect "state: an unrelated unnamed PR still fails" 1 "$rc"
  reset_state
}

state_token_checks() {
  local entry token want rc
  G -C "$D" branch feat/deep/x
  G -C "$D" push -q origin feat/deep/x 2>/dev/null
  G -C "$D" branch -q -D feat/deep/x
  G -C "$D" branch feat/local
  G -C "$D" branch 'feat/x@y'
  mkdir -p "$WORK/outside" "$D/etc" "$D/src" "$D/logs"
  echo x > "$WORK/outside/file"
  ln -s "$WORK/outside" "$D/linkout"
  echo x > "$D/etc/passwd"
  echo x > "$D/src/m.py"
  echo x > "$D/logs/a:b"
  echo x > "$D/logs/run:2"
  echo x > "$D/src/a@b.py"
  G -C "$D" add -A
  G -C "$D" commit -qm fixtures
  cp "$D/.os/state.md" "$WORK/state.orig"

  for entry in '-f/dev/zero|1' 'deep/x|1' 'feat/*|1' 'feat/[d]eep/x|1' 'feat/deep/x|0' \
               '../outside/file|1' 'linkout/file|1' 'etc/./passwd|0' '--help/x|1' 'main/../main|1' \
               'gone/branch|1' 'feat/local|0' \
               'src/m.py:2|0' 'src/m.py:2:7|0' 'src/gone.py:2|1' 'src/gone.py:2:7|1' 'feat/local:3|0' \
               'feat/deep/x:3|0' 'feat/nope:3|1' 'a/b:|1' 'a/b:x|1' 'a/b:1:2:3|1' 'src/m.py:1:2:3|1' \
               'C:/x|1' 'host:/path|1' 'logs/a:b|0' 'https://example.com/x|0' 'file:///etc/passwd|0' \
               'logs/run:2|0' 'git@github.com:o/r.git|0' 'user@host:dir/path|0' 'src/a@b.py|0' \
               'src/c@d.py|1' 'feat/x@y|0' 'feat/z@w|1' \
               'x/y	z|0' 'x/y\rz|0' 'x/y\vz|0'; do
    token=${entry%|*}
    want=${entry##*|}
    with_token "$token"
    SV "$NOGH_PATH" >/dev/null 2>&1; rc=$?
    expect "state: token \`$token\`" "$want" "$rc"
  done

  with_token gone/branch
  git -C "$D" remote set-url origin "$WORK/no-such-remote"
  SV "$NOGH_PATH" > "$WORK/out" 2>&1; rc=$?
  expect "state: unreachable remote gets its own message" "1 yes" "$rc $(grep -q 'could not reach the remote' "$WORK/out" && echo yes)"
  git -C "$D" remote set-url origin "$D.remote"
  reset_state
}

state_fence_checks() {
  local inject rc1 rc2
  for inject in '## Blocked\n\n<!-- verify-state:generated:start -->\nWaiting on `gone/branch`.\n' \
                '## Blocked\n\n<!-- verify-state:generated:end -->\n' \
                '## Focus\n\n```\n    <!-- verify-state:generated:start -->\n```\n'; do
    python3 - "$WORK/state.orig" "$D/.os/state.md" "$inject" <<'PY'
import sys
inject = sys.argv[3].replace("\\n", "\n")
heading = inject.split("\n")[0] + "\n"
open(sys.argv[2], "w").write(open(sys.argv[1]).read().replace(heading, inject, 1))
PY
    SV "$NOGH_PATH" >/dev/null 2>&1; rc1=$?
    FAKEGH_PRS="$WORK/prs-7.json" SV "$GH_PATH" --write >/dev/null 2>&1; rc2=$?
    expect "state: stray fence marker fails validate and --write ($(printf '%s' "$inject" | cut -c1-30))" "1 1" "$rc1 $rc2"
  done
  reset_state
}

state_checks() {
  D=$(state_repo state)
  cp "$D/.os/state.md" "$WORK/state.orig"
  state_write_checks
  state_limit_and_gh_checks
  state_token_checks
  state_fence_checks
}
