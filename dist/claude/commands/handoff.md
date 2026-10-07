---
description: Write a handoff entry so the other tool or coordinator can pick up where you left off
---

Append a handoff entry to `.os/handoff.md` in the current project, creating it if needed.

This file is disposable transport between agents working right now. It is not versioned. Anything
in it that still matters tomorrow must be promoted into `docs/` or `AGENTS.md` today — do that
promotion now if it applies, and say you did.

## Entry format

```
## <ISO date> — <actor: hoe | hop | claude | codex | expert slug>
DID: <what changed, one or two lines>
STATE: <where things stand>
NEXT: <the immediate next action for whoever picks this up>
WATCH: <anything half-finished, risky, or easy to miss — or "nothing">
```

Keep it under ten lines. If it needs more, it needed a doc.

Then update `.os/state.md` to reflect current focus, in-flight work, and blockers. That file is
versioned and is what makes moving between machines work — keep it accurate and short.
