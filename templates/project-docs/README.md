# Project docs — how to read these

These two docs are the **contract** the operator reviews instead of the code.
The operator owns the structure; tests and an AI reviewer own the lines.

- **`DATA-MODEL.md`** — the nouns: tables, fields, types, relationships.
- **`ARCHITECTURE.md`** — the verbs: components, flows, and Boundaries.

## Rules

- **Keep them current.** Update a doc in the *same change* that alters the
  structure it describes. A structural change with stale docs is incomplete.
- **Business language, not code.** Mermaid diagrams + plain prose. Technical
  enough to matter (e.g. "the response streams"), without the low-level
  mechanism.
- **Grow on signal — don't pre-create.** A topic starts as a section inside
  `ARCHITECTURE.md` and graduates to its own doc only when it's referenced
  repeatedly, keeps causing questions, or outgrows ~one screen.
- **Stay honest.** Where a cheap automated check is possible (e.g. a test that
  the real schema matches `DATA-MODEL.md`), add it. When it fails, decide which
  is wrong — the doc (design changed) or the code (it drifted).

## Rendering Mermaid

Mermaid code blocks render as diagrams on GitHub and in the VS Code Markdown
preview (`Ctrl/Cmd+Shift+V`). For the built-in preview, the "Markdown Preview
Mermaid Support" extension helps; GitHub renders them natively.

Copy `DATA-MODEL.md` and `ARCHITECTURE.md` into the project repo (e.g. its
`docs/`) and fill them in. Delete the `<!-- guidance -->` comments as you go.
