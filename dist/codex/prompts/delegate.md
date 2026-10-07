Delegate implementation to Codex. Volume implementation goes there; judgement, architecture, and
review stay here.

This needs the Codex CLI (`command -v codex`). Without it, say so in one line and hand the work to
the relevant specialist subagent instead, with the same brief. Run from inside Codex, this command
does not apply: do the work, or use Codex's own subagents.

## Decide whether to delegate

Delegate when the work is **well-specified, mechanical, and large**. Keep it here when it needs
judgement about what to build, or when the specification is still moving.

## Build the brief

The Codex agent starts clean and has no access to this conversation. The brief must stand alone:

- The task, stated as an outcome.
- The paths it should read and the paths it may change.
- Constraints: conventions to follow, things not to touch, what must not break.
- What "done" looks like, including how to verify.
- Run anything long in the background and poll it. A blocking wait that times out looks like a
  finished command.

## Run it

Branch from the canonical remote as it is now, and stop if the base is stale. An agent working
from an old base reports success on code that no longer exists:

```
git fetch origin && git merge-base --is-ancestor origin/<default-branch> HEAD
```

Choose effort by the work, not by the cost — the model stays at flagship either way:

```
mkdir -p .os/inbox
codex exec -m gpt-5.6-sol -c model_reasoning_effort=<low|medium|high> \
  -C <repo> -s workspace-write \
  --output-schema ~/.codex/protocols/report.schema.json \
  -o .os/inbox/<id>.json \
  "<brief>" < /dev/null
```

**Launch it as a tracked background task**, never with a bare `&`, and never piped through `tail`.
A detached process is invisible to the harness, and `tail` buffers the whole run so the output stays
empty until it exits. Both make a delegate impossible to watch.

**If the brief needs Docker**, `workspace-write` denies the socket because it sits outside the
workspace. Grant just that path rather than dropping the sandbox:

```
  -c 'sandbox_workspace_write.writable_roots=["<dir holding docker.sock>"]' \
  -c 'sandbox_workspace_write.network_access=true' \
```

Find the directory with `docker context inspect`. Without this a container-backed brief reports its
verification as blocked, and you inherit the verifying. `-s danger-full-access` also works and
removes every protection; prefer the targeted grant.

`low` for mechanical edits, `medium` for normal implementation, `high` for hard debugging.

**`< /dev/null` is required.** Without it `codex exec` blocks forever waiting on stdin. This is not
optional and it is not a style preference.

## After

1. Read `.os/inbox/<id>.json`. Do not report a result you have not read.
2. Check the work — `git diff`. The report says what it believes it did; the diff says what it did.
3. Run `/review` on the change.
4. Append a `/handoff` entry.

If the result is wrong, say so plainly and say whether the brief was at fault. A bad brief is the
usual cause and it is fixable.
