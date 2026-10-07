# Report contract

Every specialist returns exactly this shape. Coordinators may relax it when talking to them
directly, but never when passing work between agents.

```
VERDICT: <one line — the answer, not a description of the answer>
CONFIDENCE: high | medium | low

FINDINGS
  [P1] <claim> — <file:line | n/a>
       <one sentence on why it matters>
  [P2] ...

RECOMMENDATION
  - <imperative, five bullets maximum>

EVIDENCE-BAR
  <capability | constraint | security | operating-benefit>: <what justifies any new dependency>
  (or: none proposed)

OPEN
  - <question that needs a human decision>
  (or: none)
```

Priorities: `P0` blocks release. `P1` should be fixed next. `P2` ordinary defect. `P3` worth fixing.

## Rules

- Lead with the verdict. Never build up to it.
- Cite `file:line` whenever a claim is about code that exists. A claim with no citation and no
  stated reason to be uncertain is not a finding.
- If there are no findings, say `FINDINGS: none`. Do not invent one to look useful.
- Keep the whole report under 40 lines unless they asked for depth.
- Never report work you did not do. If you ran out of scope, say what you did not cover.
