# Claude Instructions

## What this repo is

Docker Swarm stack definitions for a single-node Intel NUC homelab. All stacks are deployed via Portainer. See `INFRASTRUCTURE.md` for the full reference.

## Key facts

- Docker Swarm single-node (manager only)
- `shared-network` is an overlay network — all services that need Cloudflare Tunnel access must be on it
- cloudflared runs as a **native systemd service** on the host, not as a Docker container
- Because cloudflared is on the host, services exposed via Cloudflare Tunnel must have `ports:` mapped to the host (e.g. `"8080:8080"`) — container-name DNS is not reachable from the host
- Domain: `setiady.com`
- Internal container registry: `localhost:3000` (Gitea)

## Network rules

- Never disconnect `cloudflared` or `portainer` from `shared-network` without a confirmed fallback access path (SSH at minimum)
- Always test remote SSH access before disconnecting the monitor during physical maintenance

## Conventions

- Internal service hostnames use the full container name (e.g. `sugarradar-staging-postgres`, not `postgres`)
- Overlay networks are used for all inter-service communication
- Secrets and env vars are set in Portainer — never committed to this repo
- Glances runs as a standalone `docker run` (not a Swarm stack) due to `--pid host` and `--privileged` requirements

## Documentation maintenance

Whenever a service is added, removed, or changed, update **all** of the following that are affected:

- **`INFRASTRUCTURE.md`** — port glossary, stack service table, Cloudflare routes, env vars
- **`CLAUDE.md`** — port ownership table, key facts if anything structural changed
- **`README.md`** — stack list if a compose file was added or removed
- **`RESETUP.md`** — deployment order or setup steps if the stack lineup changed

Do not leave any doc out of sync. If a port is reassigned, update both `INFRASTRUCTURE.md` and `CLAUDE.md`. If a new stack is added, it must appear in `README.md`, `INFRASTRUCTURE.md` (full detail), and `CLAUDE.md` (port table).

---

## Port ownership

Ports already in use on the host — do not reassign:

| Port | Service          |
|------|------------------|
| 3000 | gitea            |
| 2222 | gitea SSH        |
| 9443 | portainer        |
| 8080 | sucrose API      |
| 5173 | glucose frontend |
| 8025 | mailpit UI       |
| 1025 | mailpit SMTP     |
| 8082 | asynqmon         |
| 3001 | dbgate           |
