# Claude Instructions

## What this repo is

Docker Swarm stack definitions for a single-node Intel NUC homelab. Most stacks are deployed via Portainer; a few (glances, sugarradar-gh-runner) need privileges Swarm doesn't honor and run as standalone containers. See `INFRASTRUCTURE.md` for the full reference.

## Key facts

- Docker Swarm single-node (manager only)
- `shared-network` is an overlay network — all services that need Cloudflare Tunnel access must be on it
- cloudflared runs as a **native systemd service** on the host, not as a Docker container
- Because cloudflared is on the host, services exposed via Cloudflare Tunnel must have `ports:` mapped to the host — container-name DNS is not reachable from the host
- Domain: `setiady.com`
- Internal container registry: `localhost:3000` (Gitea)
- **mailpit** is a shared infrastructure service — any app stack needing SMTP in staging/dev should use `SMTP_HOST=mailpit`, `SMTP_PORT=1025`

## Network rules

- Never disconnect `cloudflared` or `portainer` from `shared-network` without a confirmed fallback access path (SSH at minimum)
- Always test remote SSH access before disconnecting the monitor during physical maintenance

## Conventions

- Internal service hostnames use the full container name (e.g. `sugarradar-staging-postgres`, not `postgres`)
- Overlay networks are used for all inter-service communication
- Secrets and env vars are set in Portainer — never committed to this repo
- Glances runs as a standalone `docker run` (not a Swarm stack) due to `--pid host` and `--privileged` requirements
- `sugarradar-gh-runner` runs as a standalone `docker compose up -d` (not a Swarm stack) because Swarm strips `device_cgroup_rules:`, which is required for `/dev/kvm` access on cgroup v2 hosts. Its PAT lives at `~/secrets/gh_runner_pat` (mode 0600) on the host, not in a swarm secret

## Port range scheme

| Range     | Owner                                                           |
|-----------|-----------------------------------------------------------------|
| 1025      | mailpit SMTP (special case — standard dev SMTP port)            |
| 2222      | gitea SSH (special case — standard containerized git SSH)       |
| 3000–3099 | Infrastructure services                                         |
| 4000–4099 | Automation & workflow tools                                     |
| 8000–8099 | SugarRadar Staging                                              |
| 8100–8199 | SugarRadar Production                                           |
| 9000–9099 | Ops tools *(portainer stays at 9443 — standard portainer port)* |

When adding a new service, pick the next free port within its stack's range. When adding a new stack, allocate a new range block.

## Port ownership

Ports already in use on the host — do not reassign:

| Port | Service               |
|------|-----------------------|
| 1025 | mailpit SMTP          |
| 2222 | gitea SSH             |
| 3000 | gitea                 |
| 3025 | mailpit web UI        |
| 9443 | portainer             |
| 8000 | sucrose API           |
| 8001 | glucose frontend      |
| 8002 | dbgate                |
| 8003 | asynqmon              |
| 4000 | n8n                   |
| 8100 | sucrose API (prod)    |
| 8101 | glucose frontend (prod)|
| 8102 | dbgate (prod)         |
| 8103 | asynqmon (prod)       |
| 9001 | observability-grafana |

## Documentation maintenance

Whenever a service is added, removed, or changed, update **all** of the following that are affected:

- **`INFRASTRUCTURE.md`** — port glossary, stack service table, Cloudflare routes, env vars
- **`CLAUDE.md`** — port ownership table, key facts if anything structural changed
- **`README.md`** — stack list if a compose file was added or removed
