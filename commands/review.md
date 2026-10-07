---
description: Review written code — native defect-finder first, then domain expert judgement
---

Review the current changes (or the target the user named).

## 1. Find defects, with the model that did not write it

Establish who wrote the change first. `.os/handoff.md` records it; `git log` shows the author. If
neither answers, ask rather than guessing, because a model reviewing its own work confirms instead
of checking.

Then pick the reviewer by what is installed (`command -v codex`, `command -v claude`):

- **Claude-written, Codex installed:** run Codex.

  ```
  codex exec -C <repo> review -m gpt-5.6-sol -c model_reasoning_effort=high --base <branch> < /dev/null
  ```

  `-C` belongs to `exec`, so it goes before `review`. Use `--uncommitted` instead of `--base` for
  work that is not committed yet. `< /dev/null` is required: without it `codex exec` blocks forever
  waiting on stdin.

- **Codex-written, Claude installed:** from Claude Code, use its own `/code-review`. From Codex, run
  Claude non-interactively: `claude -p "Review the changes on this branch against <branch> for
  correctness defects. Cite file:line."` It calls Anthropic's API, and Codex's `workspace-write`
  sandbox denies network by default, so run it with network allowed
  (`-c sandbox_workspace_write.network_access=true`) or ask the user to run it in a terminal.
- **Only one tool installed:** a fresh session of that model with none of the author's context. In
  Claude Code, `/code-review` in a subagent; in Codex, the `codex exec review` above.

Whichever ran, name it in the report and say whether it was cross-model or same-model. A review is
only as good as its independence from the author, and the reader cannot judge that unless you name
it.

Then run one reviewer with no brief: the repository and nothing else, no findings to confirm and
no lens to look through. It is the only pass that can raise what nobody thought to ask about.

## 2. Route findings for judgement

Defect-finding is not the same as knowing what matters. Take what came back and route it:

- Schema, migration, or invariant findings → `data-modeler`
- Authorization, secrets, or data-exposure findings → `security-analyst`
- Boundary or coupling findings → `systems-architect`
- Missing or weak test coverage → `qa-engineer`
- Usability, flow, or error-handling findings on built screens → `product-designer`

Send only the relevant findings plus the paths. Do not forward the whole review to everyone.

The defect-finder reads a diff, so it will not raise usability at all. When the change touches a
screen a person uses, route it to `product-designer` whether or not the review mentioned it.

## 3. Report

One consolidated list, ordered by priority, with the specialist's judgement attached to each item.
Say plainly which findings you think are not worth acting on and why — an unfiltered review is
just noise the user has to filter themselves.
