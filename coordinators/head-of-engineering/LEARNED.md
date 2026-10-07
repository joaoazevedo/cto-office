# Learned — head-of-engineering

Craft only. Never a project name, path, schema, or business fact — those belong in the project.
Capped at 25 lines. When full, consolidate before adding.

- Verify a tool ran and produced its effect before reading meaning into its output; no output is a failed run, not a quiet pass.
- Execute contracts and schemas rather than only reviewing them — one run finds defects that rounds of expert reading miss.
- A script that aborts mid-run discards earlier work already reported as done; persist each step and re-read the file to confirm.
- Build completeness assertions into verification tooling and prove each one fires by breaking what it guards; a truncated run looks identical to a clean pass, and an untested assertion is decoration.
- A generated artifact must be byte-stable across runs before a check compares it, or the comparison is theatre and gets ignored the first time it flaps.
- Before asking for review of a large diff, separate machine state from generated output from what a human must read; an unsplit diff gets skimmed or trusted, never reviewed.
- Read a benchmark for what it contradicts, not only for what it supports.
- Distinguish illustrative code from executable contract in any document a tool will parse.
- Put each specialist's objection back to the other rather than arbitrating from the middle; their concessions beat my adjudication.
- Work I did myself is work nobody checked; the errors that reached the founder were all in changes I judged too small to route.
- Check the recorded decisions before steering a specialist's design; a directive that contradicts one reads as authority and gets built faithfully.
- Hold a merge until the named required checks exist and pass; a check that has not registered yet reads as nothing pending.
- Never write an identifier that changes on merge into hand-maintained prose a gate checks; it goes stale the moment the thing it names lands.
- Default to one review round; only P0 and P1 findings block, the rest is filed and the work moves on.
- Name the authoring model in every coding brief with no opt-out; an escape hatch in a brief gets taken.
- Verify the premise against the code or governing contract before briefing an issue or ruling on an agent's question; a ruling built on an assumed flow ships the wrong default.
- Before closing a phase, confirm every outcome has a named test attached, and file new defects only into open containers; no open issue is not the same as met.
- When a writer edits a file a gate checks, put the gate's rules in the brief; a writer optimises for the prose, not the check.
- Decompose by data constraints as well as contract wiring: for each new value a unit writes, name the unit that widens the constraint accepting it and sequence after it.
- Brief delegated agents to branch from a freshly fetched canonical remote and to background long commands and poll; a stale base or a blocking wait fails silently.
