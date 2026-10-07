# Roster and routing

Loaded on demand by coordinators, not in every session.

| Expert | Route here when | Tier |
| --- | --- | --- |
| `systems-architect` | Component boundaries, service decomposition, integration patterns, build-vs-buy, scaling shape, technology selection | deep |
| `data-modeler` | Schema design, migrations, invariants, indexing, consistency, data contracts, storage engine choice | deep |
| `security-analyst` | Threat modelling, authn/authz, secrets, data exposure, dependency risk, compliance surface | deep |
| `critic` | Before committing to any plan or design. Red-teams the proposal and argues the other side | deep |
| `backend-engineer` | Service and API implementation, domain logic, background jobs, error handling | build |
| `frontend-engineer` | UI implementation, state management, rendering performance, accessibility, forms | build |
| `devops-engineer` | Infrastructure, CI/CD, deployment, observability, cost, runbooks, environments | build |
| `qa-engineer` | Test strategy, test authoring, regression risk, coverage gaps, release readiness | build |
| `product-strategist` | Market and competitor analysis, roadmap, prioritisation, requirements, scope | standard |
| `product-designer` | User flows, information architecture, interaction design, design systems, usability | deep |

## Tiers

Claude tiers by model. Codex keeps coding work on its flagship model and buys speed with reasoning
effort rather than a weaker model; only the `standard` and `fast` tiers, which write no code, step
down.

**Split work across both when both are installed, and not to save money.** Two models have
different blind spots, so a codebase written entirely by one carries that one's assumptions
everywhere. Alternating gives the work more than one set of instincts, and it is what makes the
review rule below possible: a unit is reviewed by whichever model did not write it. With one tool,
use its column only; everything else in this file still applies.

| Tier | Claude | Codex | Effort |
| --- | --- | --- | --- |
| deep | `opus` | `gpt-5.6-sol` | high |
| build | `sonnet` | `gpt-5.6-sol` | medium |
| standard | `sonnet` | `gpt-5.6-terra` | medium |
| fast | `haiku` | `gpt-5.6-terra` | low |

Coding work never drops below `gpt-5.6-sol` on the Codex side. Iterate faster by lowering effort:

```
codex exec -m gpt-5.6-sol -c model_reasoning_effort=low ...   # mechanical edits
codex exec -m gpt-5.6-sol -c model_reasoning_effort=medium ... # normal implementation
codex exec -m gpt-5.6-sol -c model_reasoning_effort=high ...   # architecture, review, hard bugs
```

## Routing rules

- **One expert per question** unless the question genuinely spans domains. Two experts on the same
  question produce two reports you then have to reconcile — only worth it when the domains disagree
  in interesting ways.
- **Run `critic` before commitment, not after.** Its value is preventing work, not reviewing it.
- **Review everything that gets written.** Use `/review`: the native defect-finder first, then route
  what it finds through the relevant domain expert for judgement.
- **Review the built thing against whether a person can use it.** Correctness, security, data and
  tests all get an adversarial pass; usability does not, so a flow ships and nobody asks whether
  someone can finish it or what happens when they cannot. Route built screens through
  `product-designer` after implementation, not only the flows before it. A designer who specifies a
  flow and never sees what was built is a designer whose spec quietly becomes fiction.
- **Delegate rather than answer inline.** A specialist reading three files and returning a short
  report is better work than the same reasoning buried in a long conversation, and it leaves a
  report someone can check.
- **Alternate the model that writes**, when both are installed. Route implementation to Claude or
  to Codex deliberately rather than by habit, and record which wrote what — the reviewer is chosen
  to be the other one. With one tool, every unit is written by it and reviewed by a fresh session
  of it.
- **Give the specialist the task, not the conversation.** They start clean. Include what they need:
  the question, relevant paths, constraints, and what "done" looks like.
- **Say when you did not delegate.** If a coordinator answers directly, that is fine — but do not
  present it as a specialist's view.
