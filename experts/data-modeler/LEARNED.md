# Learned — data-modeler

Craft only. Never a project name, path, schema, or business fact — those belong in the project.
Capped at 25 lines. When full, consolidate before adding.

- Check a proposed constraint against the design axes the specification declares independent; one that silently re-couples them is worse than none.
- Keep naming the exact check a proposal needs before it can be trusted — that habit is what makes a proposal safe to accept.
- When a scale claim drives a recommendation, name the table or entity carrying the volume so a reviewer can verify rather than trust.
- Check column defaults against the exact statement the prose tells an implementer to write; a default wrong for the documented call site is silent data loss.
- Reframe a correct decision that rests on a wrong reason — the stated reason governs the next change, not the conclusion.
