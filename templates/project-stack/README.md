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

<!-- About three paragraphs (no hard rule). The product outcome — the thing
     that actually ships and by which progress is measured. Say what "done"
     looks like, who it is for, and what is explicitly out of scope. -->

Ship a stable self-hosted notes app that a small team can rely on day to day.
"Done" means a team of five to ten people can run the stack on a single VPS,
create and search notes, and trust that their data is durable across restarts
and upgrades — without an operator babysitting it.

The audience is small self-hosting teams, not a public multi-tenant service.
That shapes every trade-off: simple single-tenant deployment over horizontal
scale, predictable upgrades over feature velocity, and sane defaults over
configurability. A change that makes the app harder to self-host is a
regression even if it adds a feature.

Explicitly out of scope for this goal: mobile apps, real-time collaboration,
and third-party integrations. Those may happen later, but progress is measured
only against a dependable single-team web experience — so they do not count
toward "done" and should not block it.

## Intermediate goal

<!-- Zero or more secondary goals that serve the primary one, about two
     paragraphs each. Add a subsection only when a goal genuinely exists — do
     not pre-create empty ones. -->

**A documented, versioned API.** `notes-api` should expose a stable, versioned
HTTP contract described in `openapi.yaml`, so other clients (mobile, CLI) could
be built against it later without reverse-engineering the endpoints.

This serves the primary goal indirectly: a clean contract keeps `notes-web`
decoupled from storage internals and makes upgrades safer, since breaking
changes become visible as schema diffs. It is a means, not the product — if it
ever competes with shipping a dependable app, the primary goal wins.

## How this directory works

- `README.md` (this file) — stable; edit only when the repos or goals change.
- `sessions/` — one `YYYY-MM-DD-slug.md` file per work session; a running
  history.
- `tasks/` — a kanban board: one markdown file per task, in `open/`, `doing/`,
  or `done/`. The folder the file sits in is its state.

At the start of a session on this stack, read this README and the latest ~10
`sessions/` files in full, read every file in `tasks/doing/` in full, and
scan `tasks/open/` a line at a time with
`grep -H -m1 -e '^title:' -e '^goal:' tasks/open/*.md` — opening an open task
in full only when the work touches it. At a natural stopping point, offer to
write a `sessions/` summary.
