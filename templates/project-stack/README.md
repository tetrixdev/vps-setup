<!--
TEMPLATE — worked example of the "project stack" convention (see the
"Project stacks" section of ~/CLAUDE.md). Copy this directory's structure when
creating a real stack at ~/Repositories/_stacks/<stack-name>/. The content
below describes a fictional "notes-stack" purely for illustration. In real
files, replace the content and DELETE every HTML comment like this one.
-->

# notes-stack

A logical grouping of related repos that work together. The repos are **not**
moved — they stay where they are under `~/Repositories/`. This directory only
holds shared goals, session history, and tasks.

## What this stack is

<!-- One short paragraph: what the repos do together, from a user's view. -->

A self-hosted notes application: a REST API plus a web client that consumes it.

## Repos

<!-- One row per repo. `Path` is the real checkout location. -->

| Repo | Path | Stack | Role |
|------|------|-------|------|
| notes-api | `~/Repositories/notes-api/` | Go | REST API and storage |
| notes-web | `~/Repositories/notes-web/` | TypeScript / React | Browser client |

## How they connect

<!-- Bullet the real dependencies / shared contracts between the repos. -->

- `notes-web` calls the HTTP endpoints exposed by `notes-api`.
- The shared API schema lives in `notes-api/openapi.yaml`.

## Primary goal

<!-- A few paragraphs. The product outcome — the thing that actually ships and
     by which progress is measured. -->

Ship a stable self-hosted notes app that a small team can rely on day to day.

## Intermediate goal

<!-- Zero or more secondary goals that serve the primary one. Add a subsection
     only when a goal genuinely exists — do not pre-create empty ones. -->

**A documented, versioned API**, so other clients (mobile, CLI) could be built
against `notes-api` later without reverse-engineering it.

## How this directory works

- `README.md` (this file) — stable; edit only when the repos or goals change.
- `sessions/` — one `YYYY-MM-DD-slug.md` file per work session; a running
  history.
- `tasks/` — a kanban board: one markdown file per task, in `open/`, `doing/`,
  or `done/`. The folder the file sits in is its state.

At the start of a session on this stack, read this README, the latest ~10
`sessions/` files, and everything in `tasks/open/` + `tasks/doing/`. At a
natural stopping point, offer to write a `sessions/` summary.
