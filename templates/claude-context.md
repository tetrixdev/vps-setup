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

`gh` is installed. If `gh auth status` shows it is not logged in, run `ghlogin`
— it reuses the token git already uses (or `$GH_TOKEN`). Once authenticated,
`gh pr`, `gh issue`, `gh repo` etc. all work non-interactively.

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
