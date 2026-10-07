Record a lesson for a member of the office. Usage: `/note <member> <lesson>`

## Rules

The lesson must be **craft**, not project knowledge. Apply the test in `04-learning.md`:

- If it names a project, path, schema, or business fact → it is project knowledge. Write it to the
  project's `docs/` or `AGENTS.md` instead, tell the user you did that, and stop.
- If it is about how the member should work, judge, calibrate, or communicate → it is craft. Queue it.

## What to do

1. Resolve `<member>` against the roster. If ambiguous, ask which one.
2. Rewrite the lesson as one line, in the imperative or as a calibration statement. Strip the
   incident; keep the transferable rule.
3. Append it to `<root>/.notes/<member>.md`, where `<root>` is what `cto root` prints, creating the
   file if needed, with today's date.
4. Confirm in one line. Do not restate the lesson back at length.

Notes queue here until `/1on1 <member>` reviews and consolidates them into the member's `LEARNED.md`
in the OS repo.
