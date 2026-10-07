# How this office learns

Each member carries a `LEARNED.md` — craft learned on the job, accumulated across every project
they have worked on. It is inlined into their prompt at build time.

## The line

`LEARNED.md` holds **craft**, never **facts about a project**.

| Belongs in `LEARNED.md` | Belongs in the project |
| --- | --- |
| "They reject abstractions introduced before the third use case" | "This repo uses the repository pattern" |
| "My confidence on migration safety has been running high" | "Migrations live in `packages/db`" |
| "They want invariants called out explicitly, not implied" | "Orders must never be shipped before payment clears" |

If a lesson names a project, a path, a schema, or a business fact, it is project knowledge and goes
into that project's `docs/` or `AGENTS.md` instead. No exceptions — this is what keeps one client's
context out of another's.

## Capture

When they correct you, that correction is the most valuable signal you will get. Suggest they record
it: `/note <expert> <lesson>`. Notes queue until the next 1:1.

## Consolidation

`LEARNED.md` is capped at 25 lines. When it is full, nothing new goes in until something is merged
or dropped. A lesson that has become automatic no longer needs writing down — remove it and make
room. Growth is not accumulation.

## A lesson about verification is not finished as prose

Some lessons cannot be enforced. "They reject abstractions introduced before the third use case" is
judgement, and writing it down is the whole of the fix.

Lessons about whether something was actually verified are different, and they are what this rule
exists for. A lesson of the form *check that the thing ran*, *confirm the mutation applied*, *do not
read a pass as a result* names a mechanical condition, and a mechanical condition can be asserted by
a command. Left as prose it fails in a particular way: it is read, agreed with, and then not done,
because the moment it applies is the moment nothing is prompting you.

So a verification lesson is carried to the project as a check, not only to `LEARNED.md` as a line.
The line may stay — it explains why the check exists — but the check is the deliverable, and a
lesson with no check behind it is still open.

The office ships `.os/verify-mutation.sh` for the general case: it breaks a line on purpose, runs
the gates you name, and requires one of them to notice. Where that does not fit, the project gets
its own gate.

## Effect

Learning takes effect on `cto build && cto sync`, not before. There is always an explicit moment where a
member changed, and `git log experts/<slug>/LEARNED.md` is the record of how they got there.
