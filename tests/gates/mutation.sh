# Checks for templates/os-verify-mutation.sh. Sourced by tests/run-gates.sh.

# A git repository whose project lives in proj/, one level below the toplevel, so every check
# also covers the monorepo layout. Prints the repository path.
mut_repo() {
  local d="$WORK/$1"
  rm -rf "$d"
  mkdir -p "$d/proj/.os" "$d/proj/src"
  git -C "$d" init -q
  cp "$TEMPLATES/os-verify-mutation.sh" "$d/proj/.os/verify-mutation.sh"
  printf 'keep = 1\nrule = 2\nlast = 3\n' > "$d/proj/src/a.txt"
  G -C "$d" add -A
  G -C "$d" commit -qm init
  echo "$d"
}

VM() { (cd "$M/proj" && "$B" .os/verify-mutation.sh "$@"); }

tree_status() { git -C "$M" status --porcelain; }

# Deletes lines matching <pattern> from src/<file> and prints the exit status and the bytes the
# gate saw with the mutation applied.
delete_and_show() {
  rm -f "$WORK/seen"
  VM --file "src/$1" --delete-line "$2" \
    --gate "python3 -c 'import sys; print(repr(open(sys.argv[1], \"rb\").read()))' src/$1 > '$WORK/seen'" \
    >/dev/null 2>&1
  local rc=$?
  echo "$rc $(cat "$WORK/seen" 2>/dev/null)"
}

mutation_final_newline_checks() {
  local f
  M=$(mut_repo fn)
  for f in "lf-noeol:keep = 1\nrule = 2\nlast = 3" "crlf-noeol:keep = 1\r\nrule = 2\r\nlast = 3" \
           "lf-eol:keep = 1\nrule = 2\nlast = 3\n" "crlf-eol:keep = 1\r\nrule = 2\r\nlast = 3\r\n" \
           "single:rule = 2" "only-newline:\n" "two-newlines:\n\n" "trailing-cr:keep\nlast\r" \
           "nul-last:keep = 1\nrule = 2\nla\000st = 3" "nul-first:ke\000ep = 1\nrule = 2\nlast = 3"; do
    printf "${f#*:}" > "$M/proj/src/${f%%:*}"
  done
  G -C "$M" add -A
  G -C "$M" commit -qm fixtures

  expect "mutation: LF, no final newline, middle line deleted" "1 b'keep = 1\\nlast = 3'" "$(delete_and_show lf-noeol '^rule')"
  expect "mutation: LF, no final newline, last line deleted" "1 b'keep = 1\\nrule = 2\\n'" "$(delete_and_show lf-noeol '^last')"
  expect "mutation: LF, no final newline, first line deleted" "1 b'rule = 2\\nlast = 3'" "$(delete_and_show lf-noeol '^keep')"
  expect "mutation: CRLF, no final newline, middle line deleted" "1 b'keep = 1\\r\\nlast = 3'" "$(delete_and_show crlf-noeol '^rule')"
  expect "mutation: CRLF, no final newline, last line deleted" "1 b'keep = 1\\r\\nrule = 2\\r\\n'" "$(delete_and_show crlf-noeol '^last')"
  expect "mutation: LF, final newline, last line deleted" "1 b'keep = 1\\nrule = 2\\n'" "$(delete_and_show lf-eol '^last')"
  expect "mutation: CRLF, final newline, middle line deleted" "1 b'keep = 1\\r\\nlast = 3\\r\\n'" "$(delete_and_show crlf-eol '^rule')"
  expect "mutation: single unterminated line deleted" "1 b''" "$(delete_and_show single rule)"
  expect "mutation: file that is only a newline" "1 b''" "$(delete_and_show only-newline '^$')"
  expect "mutation: file of two newlines" "1 b''" "$(delete_and_show two-newlines '^$')"
  expect "mutation: bare CR at end, last line deleted" "1 b'keep\\n'" "$(delete_and_show trailing-cr last)"
  expect "mutation: bare CR at end, last line kept" "1 b'last\\r'" "$(delete_and_show trailing-cr keep)"
  expect "mutation: NUL in kept last line" "1 b'keep = 1\\nla\\x00st = 3'" "$(delete_and_show nul-last '^rule')"
  expect "mutation: NUL in deleted last line, match before NUL" "1 b'keep = 1\\nrule = 2\\n'" "$(delete_and_show nul-last '^la')"
  expect "mutation: NUL in deleted last line, match after NUL" "1 b'keep = 1\\nrule = 2\\n'" "$(delete_and_show nul-last 'st = 3')"
  expect "mutation: NUL in kept first line" "1 b'ke\\x00ep = 1\\nlast = 3'" "$(delete_and_show nul-first '^rule')"
  expect "mutation: NUL in deleted first line" "1 b'rule = 2\\nlast = 3'" "$(delete_and_show nul-first 'ep = 1')"
  expect "mutation: tree clean after the final-newline runs" "" "$(tree_status)"
}

mutation_pattern_checks() {
  local rc out expected
  M=$(mut_repo ere)
  VM --file src/a.txt --delete-line '(' --gate true >/dev/null 2>&1; rc=$?
  expect "mutation: invalid ERE '(' refused" 2 "$rc"
  if grep_rejects_open_brace; then expected=2; else expected=3; fi
  VM --file src/a.txt --delete-line 'a{1' --gate true >/dev/null 2>&1; rc=$?
  expect "mutation: 'a{1' follows this grep's ERE dialect" "$expected" "$rc"
  out=$(VM --file src/a.txt --delete-line 'rule = [[:digit:]]$' --gate true 2>&1); rc=$?
  expect "mutation: POSIX class matches one line" "1 1" "$rc $(printf '%s\n' "$out" | sed -n 's/^==> \([0-9]*\) site.*/\1/p')"
  VM --file src/a.txt --delete-line 'zzz' --gate true >/dev/null 2>&1; rc=$?
  expect "mutation: pattern matching nothing exits 3" 3 "$rc"
  VM --file src/a.txt --replace "$(printf 'rule = 2\n')" --with "$(printf 'X\r')" \
    --gate "python3 -c 'import sys; print(repr(open(sys.argv[1], \"rb\").read()))' src/a.txt > '$WORK/seen'" >/dev/null 2>&1; rc=$?
  expect "mutation: CR in --with is written byte for byte" "1 b'keep = 1\\nX\\r\\nlast = 3\\n'" "$rc $(cat "$WORK/seen")"
}

mutation_path_checks() {
  local entry label f rc cmd
  M=$(mut_repo paths)
  mkdir -p "$M/proj/app/[slug]" "$M/proj/app/s"
  printf 'rule = 2\n' > "$M/proj/src/café.txt"
  printf 'rule = 2\n' > "$M/proj/src/tab	x.txt"
  printf 'rule = 2\n' > "$M/proj/src/x1.txt"
  printf 'rule = 2\n' > "$M/proj/src/new
line.txt"
  printf 'rule = 2\n' > "$M/proj/src/-dash.txt"
  printf 'rule = 2\n' > "$M/proj/app/[slug]/page.tsx"
  printf 'other\n' > "$M/proj/app/s/page.tsx"
  G -C "$M" add -A
  G -C "$M" commit -qm names

  for entry in "non-ASCII|src/café.txt" "tab|src/tab	x.txt" "bracket glob|app/[slug]/page.tsx" \
               "newline|src/new
line.txt" "leading dash|src/-dash.txt"; do
    label=${entry%%|*}
    f=${entry#*|}
    echo uncommitted >> "$M/proj/$f"
    VM --file "$f" --replace rule --with RULE --gate true >/dev/null 2>&1; rc=$?
    expect "mutation: dirty $label name refused" 2 "$rc"
    G -C "$M" checkout -q -- proj

    if is_root; then
      skip "mutation: failed restore of $label name exits 4" "root ignores the read-only bit"
      skip "mutation: printed recovery command for $label name works" "root ignores the read-only bit"
    else
      VM --file "$f" --replace rule --with RULE \
        --gate 'for f in src/* app/*/*; do grep -q RULE "$f" && chmod a-w "$f"; done; true' > "$WORK/out" 2>&1; rc=$?
      find "$M/proj" -type f -not -path '*/.os/*' -exec chmod u+w {} +
      expect "mutation: failed restore of $label name exits 4" 4 "$rc"
      cmd=$(sed -n '/Run: /,$p' "$WORK/out" | sed '1s/^ *Run: //')
      "$B" -c "$cmd" >/dev/null 2>&1; rc=$?
      expect "mutation: printed recovery command for $label name works" "0 " "$rc $(tree_status)"
    fi
    G -C "$M" checkout -q -- proj

    VM --file "$f" --replace rule --with RULE --gate true >/dev/null 2>&1; rc=$?
    expect "mutation: clean run on $label name restores it" "1 " "$rc $(tree_status)"
  done

  printf 'rule = 2\n' > "$M/proj/src/x[1].txt"
  VM --file 'src/x[1].txt' --replace rule --with RULE --gate true >/dev/null 2>&1; rc=$?
  expect "mutation: untracked name that globs to a tracked file refused" 2 "$rc"
  rm "$M/proj/src/x[1].txt"

  ln "$M/proj/src/x1.txt" "$M/hardlink"
  VM --file src/x1.txt --replace rule --with RULE --gate true >/dev/null 2>&1; rc=$?
  expect "mutation: hard-linked target refused" 2 "$rc"
  rm "$M/hardlink"

  ln -s x1.txt "$M/proj/src/link.txt"
  G -C "$M" add proj/src/link.txt
  G -C "$M" commit -qm link
  VM --file src/link.txt --replace rule --with RULE --gate true >/dev/null 2>&1; rc=$?
  expect "mutation: tracked symlink refused" 2 "$rc"
  ln -s src "$M/proj/srclink"
  VM --file srclink/x1.txt --replace rule --with RULE --gate true >/dev/null 2>&1; rc=$?
  expect "mutation: target reached through a symlinked directory runs" "1 ?? proj/srclink" "$rc $(tree_status)"
  rm "$M/proj/srclink"

  for f in 'echo x >> src/x1.txt' 'rm src/x1.txt' 'echo x >> src/x1.txt; exit 1' 'ln -sf /etc/hosts src/x1.txt'; do
    VM --file src/x1.txt --replace rule --with RULE --gate "$f" >/dev/null 2>&1; rc=$?
    expect "mutation: baseline gate \`$f\` refused and undone" "2 " "$rc $(tree_status)"
    G -C "$M" checkout -q -- proj
  done

  M=$(mut_repo mono)
  echo uncommitted >> "$M/proj/src/a.txt"
  VM --file src/a.txt --replace rule --with RULE --gate true >/dev/null 2>&1; rc=$?
  expect "mutation: dirty file in a subdirectory project refused" 2 "$rc"
}

mutation_build_cache_check() {
  local rc next
  if ! have make; then skip "mutation: make sees the restored file as newer than its output" "make not found"; return; fi
  M=$(mut_repo make)
  printf 'out.txt: src/a.txt\n\tcp src/a.txt out.txt\ntest: out.txt\n\tgrep -q "rule = 2" out.txt\n' > "$M/proj/Makefile"
  echo out.txt > "$M/proj/.gitignore"
  G -C "$M" add -A
  G -C "$M" commit -qm make
  touch -t 202001010000 "$M/proj/src/a.txt"
  # The sleep keeps the mutated write and the rebuild in different seconds for make's timestamps.
  VM --file src/a.txt --replace 'rule = 2' --with 'rule = 9' --gate 'make -s test; rc=$?; sleep 1; exit $rc' >/dev/null 2>&1; rc=$?
  (cd "$M/proj" && make -s test >/dev/null 2>&1); next=$?
  expect "mutation: make sees the restored file as newer than its output" "0 0" "$rc $next"
}

mutation_gate_status_checks() {
  local rc entry sig want
  M=$(mut_repo status)
  if have cc; then
    cat > "$M/proj/src/a.c" <<'C'
#include <assert.h>
#define RULE 2
int main(void) { assert(RULE == 2); return 0; }
C
    G -C "$M" add -A
    G -C "$M" commit -qm c
    VM --file src/a.c --replace 'RULE 2' --with 'RULE 3' --gate "cc -o '$WORK/assert' src/a.c && '$WORK/assert'" >/dev/null 2>&1; rc=$?
    expect "mutation: failing C assert counts as a catch" "0 " "$rc $(tree_status)"
  else
    skip "mutation: failing C assert counts as a catch" "cc not found"
  fi
  VM --file src/a.txt --replace rule --with RULE --gate 'grep -q RULE src/a.txt && exit 255; true' >/dev/null 2>&1; rc=$?
  expect "mutation: gate exiting 255 counts as a catch" 0 "$rc"
  for entry in QUIT:2 TERM:2 KILL:2 HUP:2 INT:2 ABRT:0 SEGV:0; do
    sig=${entry%:*}
    want=${entry#*:}
    VM --file src/a.txt --replace rule --with RULE --gate "grep -q RULE src/a.txt && kill -$sig \$\$; true" >/dev/null 2>&1; rc=$?
    expect "mutation: gate killed by SIG$sig in the mutated run" "$want " "$rc $(tree_status)"
    VM --file src/a.txt --replace rule --with RULE --gate "kill -$sig \$\$" >/dev/null 2>&1; rc=$?
    expect "mutation: gate killed by SIG$sig in the baseline" "2 " "$rc $(tree_status)"
  done
}

mutation_signal_checks() {
  local sig phase target pid rc want gate i
  M=$(mut_repo signals)
  gate="if grep -q RULE src/a.txt; then touch '$WORK/phase-mutated'; else touch '$WORK/phase-baseline'; fi; sleep 3"
  for sig in INT TERM HUP; do
    case $sig in INT) want=130 ;; TERM) want=143 ;; HUP) want=129 ;; esac
    for phase in baseline mutated; do
      for target in pid group; do
        rm -f "$WORK/phase-baseline" "$WORK/phase-mutated"
        (cd "$M/proj" && exec python3 -c 'import os, signal, sys
signal.signal(signal.SIGINT, signal.SIG_DFL)
os.setpgrp()
os.execvp(sys.argv[1], sys.argv[1:])' "$B" .os/verify-mutation.sh --file src/a.txt --replace rule --with RULE --gate "$gate" >/dev/null 2>&1) &
        pid=$!
        i=0
        while [ ! -e "$WORK/phase-$phase" ] && [ "$i" -lt 100 ]; do sleep 0.1; i=$((i + 1)); done
        if [ "$target" = group ]; then kill -"$sig" -- -"$pid" 2>/dev/null; else kill -"$sig" "$pid" 2>/dev/null; fi
        wait "$pid" 2>/dev/null; rc=$?
        expect "mutation: SIG$sig to the script's $target during the $phase restores" "$want " "$rc $(tree_status)"
        G -C "$M" checkout -q -- proj
      done
    done
  done
}

mutation_checks() {
  mutation_final_newline_checks
  mutation_pattern_checks
  mutation_path_checks
  mutation_build_cache_check
  mutation_gate_status_checks
  mutation_signal_checks
}
