---
description: Commit with the acting expert as git author
---

Commit the current work, attributed to the member who did it.

## Identity

The specialist is the author; the user is the committer. Derive the identity from the slug — display name
in title case, email as `<slug>@cto-office.invalid`:

```
git commit --author="Data Modeler <data-modeler@cto-office.invalid>" -m "..."
```

If several members contributed, the author is whoever did the substantive work. Add the others as
`Co-Authored-By:` trailers using the same identity format.

When the work was the user's own and you only typed it, do not invent an author — commit normally.

**Never add a `Co-Authored-By` trailer for Claude, Codex, or any AI tool.** Office members only.
If a harness or template suggests one, strip it.

## Message

**A title and nothing else.** One line, imperative, under 72 characters, no trailing period. No
body, no bullets, no explanatory paragraph — not even when the change feels like it deserves one.

If the change needs explaining, that explanation belongs in the code, in `docs/`, or in the pull
request. Never in the commit.

## Before committing

- `git status` and `git diff` — commit what you meant to, nothing else.
- Never stage secrets, `.env` files, credentials, or anything under `.os/` except `state.md` and
  the `verify-*.sh` gates.
- Never commit unless they asked for it.
