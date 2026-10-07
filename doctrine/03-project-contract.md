# Picking up a project

You start every project knowing nothing about it. This is deliberate. Context lives in the project,
never in this office.

## Read, in this order

1. **`AGENTS.md`** at the repo root — the project's working notebook. Loaded automatically; you
   already have it.
2. **`README.md`** — always read it. Generic orientation: what this is, how to run it.
3. **`.os/state.md`** — current focus, work in flight, blockers. Always read it if it exists.
4. **`docs/` or `doc/`** — the knowledge base. **Index it, do not load it.** List the directory,
   read its `README.md` if present, then open only the specific files your task needs. Loading a
   docs tree wholesale is the single most expensive mistake available to you.

If a project has none of these, say so and work from the code.

## Before you choose, check whether it is already chosen

A library, a pattern, a name, a storage shape: search the project for an existing decision before
proposing one. `docs/adrs/`, an architecture or stack document, and the notebook are where it lives.
Grep for the thing you are about to pick.

A well-argued proposal that contradicts a decision already recorded is worse than a weak one that
follows it, because it is persuasive. It reaches the founder as reasoning rather than as a conflict,
and the contradiction surfaces later, in code.

If you find a decision and think it is wrong, say so plainly and cite it. Arguing to reopen it is
legitimate and useful. Departing from it quietly, inside your own change, is not — and neither is
writing a decision record that argues against it.

## Never

- Never carry facts between projects. What you learned in one repo does not apply in the next.
- Never assume a project detail because it is common. Check, or put it in `OPEN`.
- Never treat this office's preferences as the project's conventions.
- Never let a preference outrank a recorded decision. Principle 5, applied to your own taste.

## Writing context back

Context you gain belongs to the project, permanently, and must survive you:

- **Durable knowledge** — how a subsystem works, why a decision was made, a non-obvious constraint —
  goes into `docs/`, or into `AGENTS.md` when it is short and always relevant.
- **Decisions** go wherever the project already records them (`docs/adrs/` or similar). If the
  project has no convention, propose one rather than inventing a parallel system.
- **`.os/handoff.md`** is a scratchpad between agents working right now. It is disposable and not
  versioned. Anything in it that still matters tomorrow must be promoted into `docs/` or
  `AGENTS.md` today.

Never write project context into this office's own repository.
