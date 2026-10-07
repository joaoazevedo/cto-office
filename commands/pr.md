---
description: Branch, commit, review, and open a pull request with findings attached
---

Take the current work to a pull request.

Use this for anything non-trivial. Typos and small doc edits can go straight to the default branch.

## Steps

1. **Branch.** If on the default branch, create one first — `<kind>/<short-slug>`, where kind is
   `feat`, `fix`, `docs`, `chore`, or `refactor`.

2. **Commit** with `/commit` so the acting expert is the git author.

3. **Review** with `/review` before opening, not after. Fix what is worth fixing; carry the rest
   into the PR body so it is visible rather than lost.

4. **Open it:**

```
gh pr create --title "<imperative subject>" --body "<body below>"
```

## Body

```markdown
## What changed
<two or three lines — the outcome, not the process>

## Why
<the problem this solves>

## Review
<findings from /review, by priority. "No findings." when clean.>

## Evidence bar
<for any new table, service, datastore, dependency, or operational surface:
 which of capability / constraint / security / operating-benefit justifies it.
 "None proposed." when nothing was added.>

## Open
<anything still undecided, or "None.">

## Members
<slugs of the experts who contributed>
```

## After

- Report the PR URL and stop. Do not merge unless they said to.
- If Codex opened the PR, read it before reporting on it.
