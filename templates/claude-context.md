# Server Operations Context

This is an Ubuntu/Debian VPS provisioned by [tetrixdev/vps-setup](https://github.com/tetrixdev/vps-setup):
Docker-based web apps behind the proxy-nginx reverse proxy.

You are a **non-interactive agent** — prefer commands that complete without
prompting. Commands marked ⚠️ are interactive; run those only when the user is
present, or use the non-interactive form noted alongside.

## VPS toolkit

| Command | Notes |
|---------|-------|
| `vps_check` | Reports whether a vps-setup update is available. Non-interactive. |
| `vps_update` | `git pull` + run new migrations. Auto-escalates via `sudo`. Non-interactive. |

Toolkit source: `/opt/vps-setup/`. Operations log: `/var/log/vps-setup.log`.

## GitHub CLI

`gh` is installed. If `gh auth status` shows it is not logged in, run `ghsetup`
and supply a GitHub token — it wires up git push, the `gh` CLI, and ghcr.io in
one step. Once authenticated, `gh pr`, `gh issue`, `gh repo` etc. all work
non-interactively.

## Working with app containers

Web apps live in `~/docker-apps/<app>/`, each with a `compose.yml`. Containers
are named `<app>-<service>` (e.g. `myapp-php`, `myapp-postgres`).

To run a one-off command in a container, target it directly — non-interactive,
no TTY:

```
docker exec <app>-php php artisan migrate --force
docker exec <app>-postgres psql -U postgres -c '\l'
```

`cd` into the project directory first, then:

| Command | Notes |
|---------|-------|
| `up` | Start the Compose project. Non-interactive. |
| `down` | Graceful shutdown — Laravel maintenance mode, waits for queued jobs. Non-interactive. |
| `bashphp` / `bashpostgres` / `bashnginx` / `bashredis` | ⚠️ Open an **interactive** shell — for human operators. As an agent, use `docker exec <app>-<service> <command>` instead. |
| `syncvolume` | ⚠️ **Destructive & interactive.** Rsyncs Docker volumes between servers and **overwrites data on the target**. Never run unattended — confer with the user first. |

## proxy-nginx — domains & TLS

Reverse proxy on ports 80/443. Install dir: `/opt/proxy-nginx/`. Backend
containers must join the `main-network` Docker network. Commands run inside the
container via `docker exec` (non-interactive unless marked).

### Manage domains — `/scripts/domain.sh`

This script covers all normal domain configuration. Use it rather than editing
nginx config by hand.

```
# Proxy a domain to a backend container
docker exec proxy-nginx /scripts/domain.sh upsert --domain=app.example.com --upstream=myapp-nginx

# Redirect a domain
docker exec proxy-nginx /scripts/domain.sh upsert --domain=example.com --redirect=https://www.example.com

# Restrict by IP (Tailscale subnet + a specific IP)
docker exec proxy-nginx /scripts/domain.sh upsert --domain=staging.example.com \
  --upstream=staging-nginx --whitelist="100.64.0.0/10,203.0.113.50"

# Remove a domain
docker exec proxy-nginx /scripts/domain.sh delete --domain=old.example.com

# List managed domains
docker exec proxy-nginx /scripts/domain.sh list
```

`upsert` options: `--domain` (required), `--upstream`, `--redirect`,
`--whitelist`, `--basic-auth` (`user:hash`), `--max-body-size` (default `256M`),
`--websocket-timeout` (default `600s`), `--comment`, `--no-reload`.

### Basic auth — `/scripts/htpasswd.sh`

```
docker exec proxy-nginx /scripts/htpasswd.sh add --user=admin --password=secret
docker exec proxy-nginx /scripts/htpasswd.sh hash --password=secret   # print hash only
docker exec proxy-nginx /scripts/htpasswd.sh remove --user=admin
docker exec proxy-nginx /scripts/htpasswd.sh list
```

### TLS certificates (Let's Encrypt, auto-renewing twice daily)

```
docker exec proxy-nginx certbot renew          # renew all certs — non-interactive
```

⚠️ Requesting a **new** certificate is interactive on first use (prompts for an
email and ToS agreement):

```
docker exec -it proxy-nginx certbot --nginx -d app.example.com
```

For an unattended request, pass `--non-interactive --agree-tos -m <email>` — but
confirm the contact email with the user first.

### Inspecting / reloading nginx

```
docker exec proxy-nginx nginx -t          # test config syntax
docker exec proxy-nginx nginx -s reload   # apply config changes
docker logs proxy-nginx                   # container logs
```

### Anything `domain.sh` doesn't cover

`domain.sh` handles all normal usage. For a configuration it cannot express,
**confer with the user before hand-editing** `/opt/proxy-nginx/default.conf`. If
you do, wrap blocks in `# BEGIN <domain>` / `# END <domain>` markers so the
script can still manage them, then run `nginx -t` and reload.

## Key paths

| Path | Purpose |
|------|---------|
| `/opt/vps-setup/` | VPS toolkit source (git-managed; `vps_update` pulls it) |
| `/opt/proxy-nginx/` | proxy-nginx install (`compose.yml`, `default.conf`, `letsencrypt/`) |
| `~/docker-apps/` | Web app Compose projects |
| `/etc/vps-setup.conf` | Setup config (access mode, install date) |
| `/var/log/vps-setup.log` | Operations log |

## Guardrails

- Don't change SSH or firewall hardening (`/etc/ssh/sshd_config.d/`,
  `/etc/iptables/`) without the user's say-so — a mistake can lock the server out.
- Don't switch the access-restriction mode; vps-setup blocks this by design.
- The firewall only exposes whitelisted ports — expose app ports through
  proxy-nginx, not by publishing host ports.

## Project stacks (dev servers)

On dev servers hosting several related repos, group them as a "stack" so a new
Claude session can orient itself without re-exploring the code.

**Before starting development or review work in a repo**, check the `### Stacks`
index (the operator adds it below the managed block of this file). If the repo
belongs to a stack, orient yourself from its tracking files first:

- `README.md` — read in full.
- `sessions/` — read the latest ~10 files in full.
- `tasks/doing/` — read every file in full; this is the active work.
- `tasks/open/` — do **not** bulk-read; the backlog can be dozens of files.
  Scan one line per task with
  `grep -H -m1 -e '^title:' -e '^goal:' tasks/open/*.md`, then open in full
  only the individual tasks the work actually touches.

A stack lives at `~/Repositories/_stacks/<stack-name>/`:

- `README.md` — stable overview: what the stack is, the repos that compose it,
  and the primary + intermediate goal(s).
- `sessions/` — one markdown file per work session (`YYYY-MM-DD-slug.md`);
  a running history of what was done, ~1-2 tight paragraphs each.
- `tasks/` — a kanban board: one markdown file per task, in `open/`, `doing/`,
  or `done/`. The folder a file sits in is the task's state. Each task has a
  `title:` in its frontmatter so the backlog can be scanned a line at a time.

When creating or updating a stack, follow the file formats in the worked
example at `/opt/vps-setup/templates/project-stack/`. Once a server has real
stacks, prefer copying the pattern of its existing `_stacks/` files over the
example. Index each stack in the operator-owned part of this server's
`~/CLAUDE.md` under a `### Stacks` heading.

Move task files between folders as work progresses. At a natural stopping
point, offer to write a `sessions/` summary (write it only once confirmed) —
there is no automated trigger for `/clear` or compaction.

This is a convention, not enforced infrastructure — no scripts depend on it,
and prod servers typically won't need it.

## Development method

How software is built on this server, so any session works the way the operator
expects. The governing idea: **the operator reviews the structure, not the
lines.** Automated tests and an AI reviewer cover correctness; the human owns
the architecture and the product vision.

### Docs are the contract

Every project keeps two living docs the operator reviews *instead of* the code.
Skeletons and a "how to read these" live in
`/opt/vps-setup/templates/project-docs/`; the filled-in docs live in the project
repo (e.g. its `docs/`).

- **`DATA-MODEL.md`** — the nouns: tables, their fields and types, and how they
  relate.
- **`ARCHITECTURE.md`** — the verbs: components, the key flows, and **Boundaries**
  (every place data crosses into a subsystem we don't fully control — an LLM
  prompt, an external API, a generated query, a serialized event).

Before building a feature or system, make sure these exist and are current.
**Update them in the same change that alters the structure** — a structural
change with stale docs is an incomplete change. They are written in business
language — plain-prose tables and diagrams — never code. Make the
**human-reviewed** representation the guarded one: when a diagram and a prose
table carry the same facts, guard the prose (it reviews and diffs more cleanly)
and treat the diagram as an optional picture, not a second source of truth.

**They mirror what *is built*, never what is *planned*.** Roadmaps and
not-yet-built design belong in a separate design/vision corpus (e.g. a project's
`docs/game-design/`), never in DATA-MODEL/ARCHITECTURE. A table or field that
exists only in the vision is a *gap* — migrate it (then mirror it) or note it in
the design corpus; it is not a mirror entry. The two doc kinds coexist with
different jobs and are not merged: the design corpus is "what it should be"; the
mirror is "what it is". Keep them honest — where a cheap automated check is
possible (e.g. a test that the real schema matches `DATA-MODEL.md`), add it, and
when it fails decide which is wrong: the doc (design changed) or the code (it
drifted).

### Grow the doc set on signal — don't pre-create

A topic starts as a *section* inside `ARCHITECTURE.md` and graduates to its own
doc only when it earns it: the operator keeps asking about it, we keep getting
it wrong, or it outgrows ~one screen. The same signal that promotes a section to
a file is the one that justifies a doc at all. Don't invent docs nobody needs.

### Reviewing AI-authored change — modes, not file-by-file

When a change is large and AI-authored, the operator cannot read every line and
must not have to. Every reviewable surface is assigned a **review mode** that
says how the operator gains confidence in it without reading it all. Five modes,
cheapest first:

1. **Skip.** Not reviewed — it carries no operator-meaningful risk, or another
   surface covers it transitively. Migration *files* (the schema they produce is
   reviewed via its mirror), seeders/static data, generated code, unit-test
   bodies. Declared explicitly, so "skipped" never silently means "forgotten".
2. **Behavioural.** Confirmed by *observing it run* — a feature test plus the
   operator using the app — because correctness lives in behaviour, not in a file
   (views/UX, forms, end-to-end flows). The feature test is the durable form;
   manual play is the final check.
3. **Direct read.** A human or reviewer subagent reads the actual files — for
   **irreducible logic** no smaller artifact captures. Every direct-read surface
   is **explicitly enumerated in the surface register** (below); if the operator
   has to *discover* what needs reading, the mode has failed and you are back to
   reading everything.
4. **Direct + companion doc + agent verification.** When direct-read logic also
   needs a written companion (a flow, a boundary, a contract) but **no automated
   test can prove the doc true** — e.g. `ARCHITECTURE.md` — the guard is a
   **verification subagent**: on each review it reads the companion doc against
   the code changes over *the operator's intended comparison* (the merge target,
   e.g. branch→main — NOT just what's uncommitted) and reports any drift. A soft
   guard, but a guard.
5. **Mirror + guard.** A unified, human-friendly doc plus an **automated test**
   proving it matches reality. Reserved for **repeating patterns** where the same
   element recurs enough that a doc + test pays for itself (the schema; a family
   of similar jobs once abstracted; any pattern of roughly a dozen-plus alike).

**The iron rule (modes 4 & 5 alike): an unguarded claim is a hope.** A mirror
with no passing alignment test, a companion doc no agent re-verifies, or a
behaviour no feature test pins — all are prose trusted on faith, and prose
drifts. The guard ships in the *same change* as the thing it guards, never
"later".

### The escalation ladder — and when to build a new mirror

A surface climbs only as far as it needs:

- one or two files of unique logic → **Direct read** (just read them);
- that logic grows or needs a flow/contract explained → **Direct + companion doc
  + agent verification**;
- **the same shape recurs** (many tables, many fields, many near-identical
  commands) → **Mirror + guard**.

The trigger to add a new mirror is **a repeating pattern**, not raw file count.
Where the repetition is hidden behind dissimilar code (say, several artisan
commands that all perform a one-way sync), first introduce an **abstraction a
human would recognise** — a "one-way sync" base with named inputs and outputs —
then mirror+guard the family. The abstraction must map to a concept the operator
holds in their head; a purely technical decomposition (a "JSON-to-HTML renderer"
shattered into ten collaborators) buys nothing for review and is the wrong kind.
Codify the rule for the AI: **when a pattern repeats, lift it into a
human-meaningful structure and promote it to mirror+guard.**

### Non-human actors are review surfaces too

When agents, jobs or integrations — not just people — read and write the data
model, their **capabilities are a surface**. Give each non-human actor its own
doc declaring: which tables/fields it may read and write, the field-level
instructions it is handed (the prompt-side guidance), and the validation that
applies to *its* writes. Locate these where they **vary**: if every actor gets
the same field instructions, they can live with the model; if they differ per
actor (one agent creates a full record, another only a hollow stub the next
fills in), they belong in the per-actor doc, not smeared across the model.
Front-end validation is then **Behavioural**, with a verification subagent
confirming it matches the server-side rules.

### The surface register

Each project keeps a **surface register** in `docs/CONVENTIONS.md`: every
reviewable surface, its mode, and its guard (the test, or the doc + agent that
verifies it). The register is what tells the operator *exactly* what to read and
what is covered for them — the antidote to "read all the files". Framework-
standard structures get default modes (the Laravel table below); project business
logic is split into its own sections the same way, and climbs the same ladder.

**Laravel structures — default modes** (the framework baseline every project on
this server starts from):

| Structure | Default mode |
|---|---|
| Migration files | **Skip** — the schema they produce is reviewed via its mirror |
| Schema (as data) | **Mirror+guard** — `DATA-MODEL.md` prose tables + a schema-drift test |
| Models — data shape | **Mirror+guard** — fields → `DATA-MODEL.md` |
| Models — methods / events | **Direct read** — and **listed in the register** so they're findable |
| Routes (+ their middleware/guards) | **Mirror+guard** — a generated route+middleware list, asserted (catches an unguarded route) |
| Form Requests / validation | **Per-actor doc + agent verification** where it varies by actor; **Behavioural** for the form itself |
| Controllers | **Direct read** while thin; business logic inside escalates the ladder |
| Blade / JS / CSS (views) | **Behavioural** |
| Events / Listeners | **Mirror** (the who-fires-what flow) + **Direct** (handler logic) |
| Jobs / queue / scheduled / console commands | The ladder: one → Direct(+doc); a family → abstract + Mirror+guard. Add **scale-shaped tests + observability** when behaviour is scale-dependent (fine on 10 rows, wrong on 10,000) |
| Services / Actions / domain logic | **Direct read** (enumerated in the register) |
| Config (behaviour-driving) | **Mirror**; else **Skip** |
| Seeders / static data, unit-test bodies | **Skip** |

### The build loop

For each feature or fix:

1. Build it.
2. Write and run automated tests; then **actually run the thing** yourself to
   confirm it behaves.
3. Spawn a reviewer subagent and iterate until it is clean. The reviewer checks
   the change *against the docs* — does it match `DATA-MODEL.md`/`ARCHITECTURE.md`,
   and if it changed the structure, did it update them? Cap the rounds; escalate
   to the operator any *structural* disagreement.
4. Only then hand the operator a review, in the format below.

### Review hand-back format

Always this shape, one screen, structure first, business language (assume the
operator does not read the code). Keep each item to **1–4 lines** (4 is the high
end).

- **Structural delta** — "No structural change", or what changed in the docs +
  a link to the doc diff. The operator reads this first.
- **Your calls (≤3)** — decisions only the operator can make; one line each plus
  your recommendation. Product, gameplay, and architecture choices always
  escalate here, to protect the operator's vision.
- **Manual test** — only if automated tests don't cover it: exact copy-paste
  steps and the expected result, plus the easiest way the result gets back (if
  logs/DB exist, retrieve it yourself; the operator only flags anomalies).
- **Automated** — tests added and pass count; reviewer verdict (rounds, what it
  caught).

Describe any issue with its **realistic scenario + impact**, so the operator can
judge whether it's worth fixing at all.

### Where this lives

This method and the doc skeletons are project-agnostic and ship from vps-setup
(this file + `templates/project-docs/`). Each project's **surface register** —
its reviewable surfaces, their modes, and their guards — lives in that project's
`docs/CONVENTIONS.md`, beside the code it governs. Operator preferences belong in
auto-memory. Bespoke plan/develop/review *skills* are deferred until the method
has proven itself on a real project — convention first, automation later.
