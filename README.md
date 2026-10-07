# CTO Office

A portable team of specialists for one person doing the work of a department.

Works in both **Claude Code** and **OpenAI Codex**, in any project, on any machine.

## The one rule

**The office carries capability. The project carries truth.**

Nothing about any specific project lives in this repository — not a name, not a path, not a schema.
Members arrive at a project knowing nothing and pick up context from the project itself. That is
what lets the same team work on unrelated codebases without leaking one client into another.

## Read this before installing

`cto sync` installs the office as your **global** instructions. It adds a block to
`~/.claude/CLAUDE.md` and `~/.codex/AGENTS.md`, and agents, commands and skills beside them, so the
doctrine applies to every Claude Code and Codex session on the machine, not only to projects you
run `cto init` in. Among other things it tells agents to keep answers short, to push back, to
commit with a specialist as the git author, and never to add an AI `Co-Authored-By` trailer.

Your own content in those two files stays. The office owns only the lines between
`<!-- cto-office:start -->` and `<!-- cto-office:end -->`, and `sync` copies the file to
`<name>.cto-backup-<timestamp>` before it changes anything. If you have instructions of your own
there, both sets are in force; where they contradict each other the model has to pick, so read
`doctrine/` first. It is what you are installing.

## Requirements

- Python 3.8 or later, and git.
- Claude Code, the Codex CLI, or both. With both, each model reviews the code the other wrote.
  With one, reviews run in a fresh session of the same model and say so, and `/delegate` hands
  work to a specialist subagent instead of Codex.
- The GitHub CLI, `gh`, authenticated, for `/pr` and for `.os/verify-state.sh`.

`cto doctor` checks what is installed.

## Get your own copy

Members learn. `/1on1` edits their `LEARNED.md` in your clone, so the clone is yours to commit to.
Don't work from a plain clone of this repository, because your lessons would have nowhere to go.

Make a private copy that keeps this repository's history, so later updates merge normally. Create
an empty private repository in your own account or organisation (no README, no license), then:

```bash
git clone --bare https://github.com/joaoazevedo/cto-office.git
cd cto-office.git
git push --mirror git@github.com:<you>/cto-office.git
cd .. && rm -rf cto-office.git
```

The lessons that ship here are a starting point; edit or empty them as you like.

To take later changes:

```bash
git remote add upstream https://github.com/joaoazevedo/cto-office.git
git pull upstream main
cto build && cto sync
```

Conflicts land in `LEARNED.md`, where your lessons and upstream's meet, and in `dist/`. Keep your
lessons, then rebuild rather than resolving `dist/` by hand: `cto build` regenerates it from the
merged sources, and `git add dist` marks it resolved.

## Install

```bash
git clone <your-copy> cto-office      # anywhere you like
cd cto-office && ./bin/cto sync       # installs for each tool present, links the launcher
cto doctor
```

Nothing assumes where the repo lives. `cto root` resolves it, and `cto sync` re-links the launcher
if you move it.

`sync` symlinks `~/.local/bin/cto` at the repo, so `cto` works from any directory and a `git pull`
updates the command itself. If `cto` is not found, add this to your shell profile:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

`sync` installs for Claude Code if `claude` is on your PATH or `~/.claude` exists, and likewise for
Codex. `--claude` or `--codex` forces one. Restart Claude Code, or start a new Codex session, to
pick up the roster.

## Use it in a project

```bash
cd ~/Projects/some-project
cto init
```

That creates `AGENTS.md` (the project notebook, read natively by both tools), `.os/state.md`,
`.os/verify-state.sh`, and `.os/verify-mutation.sh`, and adds the right `.gitignore` entries. If
the project already ignores `.os/` as a whole, `init` rewrites that rule so the state file and the
gates can be committed. Fill in the notebook. Long-form knowledge goes in `docs/`.

`.os/state.md` skips pull-request review, so the office ships the check for the gap that opens.
`.os/verify-state.sh` asserts that every pull request the file names is open, every open pull
request is named, and every backticked name containing a slash exists as a repository path or a
branch, local or on the remote. A bare word in backticks is not checked, because it can't be told apart from code.
Nothing runs it for you; `cto init` prints the CI step and repeats it in `AGENTS.md`. In CI (when
`CI` is set) a missing or unauthenticated `gh` fails the check. Locally it warns and skips the
pull-request assertions.

`.os/state.md` has two halves. The prose is yours. The fenced block under "## In flight" is
generated: `./.os/verify-state.sh --write` rewrites it from GitHub's open pull requests, listing
each one's number and branch, and touches nothing else in the file. Pull-request titles are never
copied in, because anyone can open a pull request and agents read this file as trusted context.
Branch names inside the block are exempt from the branch-and-path assertion, because a merge
deletes a branch before the block is next rewritten.

`.os/verify-mutation.sh` answers a different question: would a gate notice? A gate that passes and
a gate that had nothing to check produce identical output, so the office ships the way to tell them
apart. It breaks one line, runs the gates you name, restores the file, and fails unless a gate
failed.

```bash
./.os/verify-mutation.sh --file <path> --delete-line '<ERE pattern>' --gate '<command>'
./.os/verify-mutation.sh --file <path> --replace <literal> --with <literal> --gate '<command>'
```

`--gate` is required and repeats, and it takes a whole shell command rather than a task name,
because nothing here knows what a project calls its gates or what runs them.

| Exit | Meaning |
| --- | --- |
| 0 | a gate caught the mutation: it failed with any other non-zero status, including a crash such as an `assert` |
| 1 | no gate did, which is the finding |
| 2 | refused or inconclusive: bad arguments, a dirty, symlinked or hard-linked target, a gate already red, a gate that modifies the target, or a gate killed by HUP, INT, QUIT, KILL or TERM |
| 3 | the mutation matched nothing, so the run proved nothing |
| 4 | the restore did not take; the backup is kept and its path printed |
| 129, 130, 143 | interrupted by HUP, INT or TERM; the file was restored |

It runs the gates on the committed tree first and refuses to continue if one is already red. It
refuses a target with uncommitted changes, and it restores the file on every exit including an
interrupt. It belongs in no CI pipeline: the mutation is the argument.

## The team

Two coordinators you talk to directly, ten specialists they delegate to.

| | |
| --- | --- |
| `/hoe` | Head of Engineering — direction, delivery, sequencing |
| `/hop` | Head of Product — problem definition, prioritisation, scope |

Specialists: `systems-architect`, `data-modeler`, `security-analyst`, `critic`,
`backend-engineer`, `frontend-engineer`, `devops-engineer`, `qa-engineer`,
`product-strategist`, `product-designer`.

See `routing/roster.md` for what each one is for.

## Commands

| | |
| --- | --- |
| `/hoe`, `/hop` | enter a coordinator persona |
| `/review` | cross-model defect-finder, then domain-expert judgement |
| `/commit` | commit with the acting expert as git author |
| `/pr` | branch, commit, review, open a PR with findings attached |
| `/delegate` | hand implementation to Codex with a schema-validated result |
| `/handoff` | leave a note for whoever picks this up next |
| `/note` | record a craft lesson for a member |
| `/1on1` | review and consolidate a member's lessons |

## How members improve

Each carries a `LEARNED.md` of craft: how to judge, calibrate, and communicate. Never project
facts; those go to the project. Capture lessons with `/note`, consolidate them with `/1on1`, and
run `cto build && cto sync` to make them take effect. Capped at 25 lines, so growth means
consolidation rather than accumulation.

`git log experts/<slug>/LEARNED.md` is that member's history.

## CLI

```
cto build                    generate dist/ from doctrine, experts, coordinators, commands, skills
cto sync [--force] [--claude] [--codex]
                             install dist/ for each tool present, and link the launcher
cto status [--claude] [--codex]
                             report drift between dist/ and what is installed
cto init [dir]               scaffold a project notebook and .os/
cto doctor                   check each installed tool and its install targets
cto identities               print the git author identity for every member
cto root                     print the repository root, wherever it was cloned
cto remove [--yes]           uninstall from this machine (dry run without --yes)
```

Install and uninstall are manifest-driven. `sync` records every file it wrote, with a hash of what
it wrote, in `.os-manifest.json` in each tool home. `remove` deletes exactly those files, and only
the office block from `CLAUDE.md` and `AGENTS.md`, after another timestamped copy. It never globs a
directory, so your settings, credentials, sessions, and any other files living beside ours are
untouched. Directories are pruned only when they held our files and are left empty.

The office never takes over a file it didn't write. If you already have an agent, command or
skill at a path the office uses, `sync` refuses before writing anything and names it; move yours
aside and run it again. It also refuses a destination that is a symlink or sits under one inside
the tool home, and writes through directory handles so nothing can redirect it outside.

If you edited an installed file, or the office block, since the last sync, `sync` leaves it alone
and says so. `cto sync --force` overwrites it after copying your version aside to
`<name>.cto-edited-<timestamp>`, and `remove` keeps an edited file rather than deleting it. An
interrupted `sync` or `remove` is finished by running it again. The launcher symlink is replaced or
removed only when it already points at an office checkout.

Projects keep their `AGENTS.md` and `.os/`. The repository survives; `cto sync` reinstalls.

## Adding a member

1. `mkdir experts/<slug>` with `EXPERT.md` (the role), `LEARNED.md` (seeded with the header and
   `_No lessons recorded yet._`), and `meta.yaml`:

   ```yaml
   name: <slug>
   description: <one line; the routing description both tools show>
   tier: deep | build | standard | fast
   claude_model: opus | sonnet | haiku
   codex_model: <model>
   codex_effort: low | medium | high
   tools: Read, Grep, Glob, Bash
   ```

2. Add a row to `routing/roster.md`.
3. `cto build && cto sync`.

## Tests

```bash
tests/run-cto.sh                        # bin/cto: build, sync, status, remove, init, doctor
tests/run-gates.sh /bin/bash            # the two gate scripts, under each bash you name
```

Both need git and Python 3.8 or later; the gate checks that need `make` or `cc` print SKIP
without them. All state goes in a temporary directory with `HOME` pointed into it, so your own
install is never touched. CI runs both on Linux and macOS, including macOS's bash 3.2, and checks
that `dist/` matches a fresh build.

## Layout

```
doctrine/     principles, report contract, project contract, learning, delivery
routing/      the roster and routing rules
experts/      ten specialists
coordinators/ Head of Engineering, Head of Product
commands/     slash commands, shared by both tools
skills/       skills installed alongside the office
protocols/    JSON Schema for structured specialist reports
templates/    project notebook, state, and gate scaffolds
tests/        checks for bin/cto and the gate scripts
bin/cto       the generator and installer
dist/         generated; committed so changes are reviewable
```

## Models

Claude tiers by model; Codex keeps coding work on its flagship model and varies reasoning effort.
The tiers and the reason for splitting work across both are in `routing/roster.md`. Change the
models in each member's `meta.yaml` to match what your plans include.

## Credits

The `human-voice-and-tone` skill is based on
[Henrique Cruz's natural voice skill file](https://www.linkedin.com/pulse/my-claude-natural-voice-skill-file-henrique-cruz-5pple/).

## License

MIT. See `LICENSE`.
