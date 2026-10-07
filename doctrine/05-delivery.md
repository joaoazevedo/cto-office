# Delivery

## Commit identity

Work is attributed to whoever did it. The specialist is the git **author**; the user is the
**committer**. Identity is derived from the member's slug:

```
git commit --author="Data Modeler <data-modeler@cto-office.invalid>" -m "..."
```

The `.invalid` domain is reserved and deliberate — agent commits carry the role name but do not
link to a GitHub account or count toward their contribution graph.

Use `/commit`. It constructs the identity and the message; do not hand-roll it.

## Never credit the tool

**Never add a `Co-Authored-By` trailer for Claude, Codex, or any AI tool, in any repository.** Not
as a default, not as a courtesy, not because a harness suggests it. This is absolute.

`Co-Authored-By` is reserved for members of this office, and only when a second member did
substantive work on the same commit:

```
Co-Authored-By: Data Modeler <data-modeler@cto-office.invalid>
```

The commit records who did the work and who committed it. Which tool typed it is not part of that
record, and it does not belong in the permanent history of their repositories.

## Commit messages are a title, nothing else

One line. No body, no bullet list, no explanatory paragraph. If the change needs explaining, the
explanation belongs in the code, in `docs/`, or in the pull request — not in the commit.

Subject line: imperative, under 72 characters, no trailing period.

```
docs: add project notebook and working state
```

Pull request bodies are the exception and keep their structure — that is where review happens.

## Review with the model that did not write it

Codex-written code is reviewed by Claude, Claude-written code by Codex. A model does not see its
own blind spots, and a review that shares the author's assumptions confirms rather than checks.
This flips per unit of work, so track which model generated what.

With only one of the two installed (`command -v claude`, `command -v codex`), the reviewer is a
fresh session of the same model that shares none of the author's context: a subagent in Claude
Code, a separate `codex exec review` in Codex. That is weaker, so the review report says it was
same-model.

One reviewer gets no brief at all: the repository and nothing else. Every reviewer pointed at
something finds what it was pointed at, and the unbriefed one is the only one that can find what
nobody thought to ask about. Its noise is the price of that.

## Branches and pull requests

Non-trivial work happens on a branch and lands through a pull request. Typos and small doc edits
may go straight to the default branch.

This is not ceremony. It is where review findings live, it is the unit of revert, and it is what
lets Claude and Codex work at the same time without colliding — each on its own branch, merges
serialized by the PR.

Use `/pr`. It branches, commits, runs review, and opens the PR with findings attached.

## Working state goes straight to the default branch

`.os/state.md` is the exception to the pull request rule. A commit that touches **only** that file
is pushed directly to the default branch, and keeping it current is the coordinator's standing
responsibility rather than something to be asked for.

The reason is that state cannot survive review. A pull request whose own state file says "this PR is
in flight" becomes wrong the moment it merges, and the default branch then claims work is open that
has already landed. State describes now; a queue describes later.

Check the staged file list before pushing. One path, and that path is `.os/state.md`. Anything else
in the commit and it goes through review like everything else.

## Never

- Never commit or push unless they asked for it, with the working-state exception above.
- Never merge your own PR unless they said to.
- Never force-push a shared branch.
