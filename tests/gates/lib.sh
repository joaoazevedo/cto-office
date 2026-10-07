# Shared helpers for tests/run-gates.sh. Sourced, not run.

PASSES=0
FAILS=0
SKIPS=0
LABEL=bash

record() {
  case "$1" in
    PASS) PASSES=$((PASSES + 1)) ;;
    FAIL) FAILS=$((FAILS + 1)) ;;
    SKIP) SKIPS=$((SKIPS + 1)) ;;
  esac
  if [ -n "${3:-}" ]; then
    printf '%s %s %s: %s\n' "$1" "$LABEL" "$2" "$3"
  else
    printf '%s %s %s\n' "$1" "$LABEL" "$2"
  fi
}

# expect <name> <expected> <actual>. Callers capture $? into a variable before building <actual>,
# because any command substitution in the arguments would overwrite it.
expect() {
  if [ "$2" = "$3" ]; then record PASS "$1"; else record FAIL "$1" "expected [$2] got [$3]"; fi
}

skip() { record SKIP "$1" "$2"; }

have() { command -v "$1" >/dev/null 2>&1; }

is_root() { [ "$(id -u)" = 0 ]; }

G() { git -c user.email=gates@example.invalid -c user.name=gates "$@"; }

# The file's bytes as a Python literal, so CR, NUL and a missing final newline are visible.
bytes_of() { python3 -c 'import sys; print(repr(open(sys.argv[1], "rb").read()))' "$1"; }

# A fake gh driven by environment variables: FAKEGH_AUTH=0 fails `auth status`, and FAKEGH_PRS
# names a JSON file that `pr list` prints and `pr view` reads.
setup_fake_gh() {
  mkdir -p "$WORK/fakebin"
  cat > "$WORK/fakebin/gh" <<'GH'
#!/bin/sh
case "$1 $2" in
  "auth status") [ "${FAKEGH_AUTH:-1}" = 1 ] && exit 0; echo "not logged in" >&2; exit 1 ;;
  "pr list")
    case "$*" in
      *"-q .[].number"*)
        python3 -c 'import json, sys; [print(p["number"]) for p in json.load(open(sys.argv[1]))]' "$FAKEGH_PRS" ;;
      *) cat "$FAKEGH_PRS" ;;
    esac ;;
  "pr view")
    python3 -c 'import json, sys; n = int(sys.argv[2]); print("OPEN" if any(p["number"] == n for p in json.load(open(sys.argv[1]))) else "MERGED")' "$FAKEGH_PRS" "$3" ;;
  *) exit 1 ;;
esac
GH
  chmod +x "$WORK/fakebin/gh"

  # A PATH with no gh at all. A directory that holds a real gh is replaced by links to everything
  # else in it, so tools that live beside gh stay reachable.
  mkdir -p "$WORK/nogh-shim"
  NOGH_PATH="$WORK/nogh-shim"
  old_ifs=$IFS
  IFS=:
  for dir in $PATH; do
    [ -n "$dir" ] && [ -d "$dir" ] || continue
    if [ -e "$dir/gh" ]; then
      for f in "$dir"/*; do
        name=$(basename "$f")
        [ "$name" = gh ] && continue
        [ -x "$f" ] && [ ! -e "$WORK/nogh-shim/$name" ] && ln -s "$f" "$WORK/nogh-shim/$name"
      done
    else
      NOGH_PATH="$NOGH_PATH:$dir"
    fi
  done
  IFS=$old_ifs
  GH_PATH="$WORK/fakebin:$NOGH_PATH"
}

# Exit status of `grep -E 'a{1'`: BSD grep rejects the unbalanced brace, GNU grep reads it as a
# literal. verify-mutation uses whichever grep is present, so the expectation follows it.
grep_rejects_open_brace() {
  printf 'a{1\n' | LC_ALL=C grep -E -e 'a{1' >/dev/null 2>&1
  [ $? -eq 2 ]
}
