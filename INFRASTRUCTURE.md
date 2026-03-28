# Setiadyslab Infrastructure

## Overview

Single-node homelab running on an Intel NUC, managed via Docker Swarm. All external access is routed through a Cloudflare Tunnel — no open inbound ports on the router.

- **Host OS:** Linux (Debian/Ubuntu)
- **Orchestration:** Docker Swarm (single node, manager)
- **Domain:** `setiady.com`
- **Remote access:** Cloudflare Zero Trust Tunnel (cloudflared as native systemd service)

---

## Hardware

| Component | Detail                                                     |
|-----------|------------------------------------------------------------|
| Device    | Intel NUC                                                  |
| BIOS      | AC Power Recovery → Power On (auto-boots after power loss) |

---

## Networking

### Docker Networks

| Network                | Driver                         | Purpose                                           |
|------------------------|--------------------------------|---------------------------------------------------|
| `shared-network`       | overlay (attachable, external) | Services reachable by cloudflared and cross-stack |
| `sugarradar-internal`  | overlay                        | Internal sugarradar-staging services only         |
| `gitea-internal`       | overlay                        | Internal Gitea + DB only                          |
| `agent_network`        | overlay                        | Portainer agent communication                     |

> **Rule:** Any service that needs to be exposed via Cloudflare Tunnel must be on `shared-network`.

### Cloudflare Tunnel

cloudflared runs as a native **systemd service** (not Docker) so it can reach host-exposed ports via `localhost` and is immune to Docker network changes.

```
systemctl status cloudflared
```

All public hostnames are configured in **Cloudflare Zero Trust → Networks → Tunnels → your tunnel → Public Hostnames**.

---

## Port Glossary

### Host-Exposed Ports

| Host Port | Container Port | Service                                | Stack              |
|-----------|----------------|----------------------------------------|--------------------|
| 3000      | 3000           | `gitea`                                | gitea              |
| 2222      | 22             | `gitea` SSH                            | gitea              |
| 9443      | 9443           | `portainer` (localhost only)           | portainer          |
| 8080      | 8080           | `sugarradar-staging-sucrose` API       | sugarradar-staging |
| 5173      | 5173           | `sugarradar-staging-glucose` frontend  | sugarradar-staging |
| 8025      | 8025           | `sugarradar-staging-mailpit` web UI    | sugarradar-staging |
| 1025      | 1025           | `sugarradar-staging-mailpit` SMTP      | sugarradar-staging |
| 8082      | 8080           | `sugarradar-staging-asynqmon` queue UI | sugarradar-staging |
| 3001      | 3000           | `sugarradar-staging-dbgate` DB admin   | sugarradar-staging |

### Internal-Only (no host binding)

| Container Port | Service                       | Reachable via                 |
|----------------|-------------------------------|-------------------------------|
| 5432           | `sugarradar-staging-postgres` | `sugarradar-internal` network |
| 6379           | `sugarradar-staging-redis`    | `sugarradar-internal` network |
| 5432           | `gitea-db`                    | `gitea-internal` network      |

---

## Stacks

### 1. Portainer (`portainer-agent-stack.yml`)

Container management UI with Swarm agent.

| Container   | Image                        | Network                           | Notes                     |
|-------------|------------------------------|-----------------------------------|---------------------------|
| `portainer` | `portainer/portainer-ce:lts` | `agent_network`, `shared-network` | HTTPS on `127.0.0.1:9443` |
| `agent`     | `portainer/agent:lts`        | `agent_network`                   | Global mode (all nodes)   |

Cloudflare route: `portainer.setiady.com` → `localhost:9443` (HTTPS, no TLS verify)

---

### 2. Gitea (`docker-compose.gitea.yaml`)

Self-hosted Git + container registry (`localhost:3000`).

| Container  | Image                | Network                            | Notes                 |
|------------|----------------------|------------------------------------|-----------------------|
| `gitea`    | `gitea/gitea:latest` | `shared-network`, `gitea-internal` | HTTP :3000, SSH :2222 |
| `gitea-db` | `postgres:16-alpine` | `gitea-internal`                   | Internal only         |

Cloudflare route: `gitea.setiady.com` → `localhost:3000`

**Env vars required:**
- `GITEA_DB_PASSWORD`

---

### 3. Glances (standalone container)

System monitoring. Not a Swarm stack — requires `--pid host` and `--privileged` which Swarm does not support.

```bash
docker run -d --restart unless-stopped \
  --pid host --privileged \
  --network shared-network \
  -v /var/run/docker.sock:/var/run/docker.sock:ro \
  -v /etc/os-release:/etc/os-release:ro \
  -e GLANCES_OPT="-w" \
  --name glances \
  nicolargo/glances:latest-full
```

Cloudflare route: `glances.setiady.com` → `http://glances:61208` (via shared-network)

---

### 4. lajula.app (`docker-compose.lajula.app.yaml`)

| Container      | Image                                      | Network          |
|----------------|--------------------------------------------|------------------|
| `lajuladotapp` | `registry.setiady.com/lajuladotapp:v1.0.0` | `shared-network` |

Cloudflare route: `lajula.app` → `http://lajuladotapp:<port>` (via shared-network)

---

### 5. SugarRadar Staging (`docker-compose.sugarradar-staging.yaml`)

Full staging environment for the SugarRadar app.

#### Services

| Container                      | Image                                                | Network(s)                              | Port (host) |
|--------------------------------|------------------------------------------------------|-----------------------------------------|-------------|
| `sugarradar-staging-sucrose`   | `localhost:3000/sugarradar/sucrose:latest`           | `shared-network`, `sugarradar-internal` | 8080        |
| `sugarradar-sucrose-worker`    | `localhost:3000/sugarradar/sucrose-worker:latest`    | `sugarradar-internal`                   | —           |
| `sugarradar-sucrose-scheduler` | `localhost:3000/sugarradar/sucrose-scheduler:latest` | `sugarradar-internal`                   | —           |
| `sugarradar-staging-glucose`   | `localhost:3000/sugarradar/glucose:latest`           | `shared-network`, `sugarradar-internal` | 5173        |
| `sugarradar-staging-postgres`  | `postgres:16-alpine`                                 | `sugarradar-internal`                   | —           |
| `sugarradar-staging-redis`     | `redis:7-alpine`                                     | `sugarradar-internal`                   | —           |
| `sugarradar-staging-dbgate`    | `dbgate/dbgate:latest`                               | `shared-network`, `sugarradar-internal` | 3001        |
| `sugarradar-staging-mailpit`   | `axllent/mailpit:latest`                             | `shared-network`, `sugarradar-internal` | 8025, 1025  |
| `sugarradar-staging-asynqmon`  | `hibiken/asynqmon:0.7.2`                             | `shared-network`, `sugarradar-internal` | 8082        |

#### Service Roles

- **sucrose** — Go REST API backend
- **sucrose-worker** — Background job processor (Asynq)
- **sucrose-scheduler** — Periodic task scheduler
- **glucose** — Frontend (Vite/React)
- **dbgate** — Database + Redis admin UI
- **mailpit** — SMTP mail catcher for staging emails
- **asynqmon** — Asynq queue monitor UI

#### Cloudflare Routes

| Hostname                    | URL              | Service          |
|-----------------------------|------------------|------------------|
| `staging-api.setiady.com`   | `localhost:8080` | sucrose API      |
| `staging.setiady.com`       | `localhost:5173` | glucose frontend |
| `staging-mail.setiady.com`  | `localhost:8025` | mailpit UI       |
| `staging-queue.setiady.com` | `localhost:8082` | asynqmon         |
| `staging-db.setiady.com`    | `localhost:3001` | dbgate           |

#### Key Env Vars

| Variable        | Example Value                   | Notes                                   |
|-----------------|---------------------------------|-----------------------------------------|
| `POSTGRES_HOST` | `sugarradar-staging-postgres`   | Must use container name, not `postgres` |
| `POSTGRES_PORT` | `5432`                          |                                         |
| `POSTGRES_DB`   | `sugarradar`                    |                                         |
| `REDIS_ADDR`    | `sugarradar-staging-redis:6379` | Must use container name                 |
| `SMTP_HOST`     | `sugarradar-staging-mailpit`    |                                         |
| `SMTP_PORT`     | `1025`                          |                                         |
| `AI_PROVIDER`   | `gemini`                        |                                         |
| `SPACES_REGION` | `sgp1`                          | DigitalOcean Spaces                     |

---

## Remote Access Summary

| Access Method | URL                             | Notes                        |
|---------------|---------------------------------|------------------------------|
| SSH           | `ssh ssh.setiady.com`           | Via cloudflared ProxyCommand |
| Portainer     | `https://portainer.setiady.com` | Stack management             |
| Gitea         | `https://gitea.setiady.com`     | Git + registry               |
| Glances       | `https://glances.setiady.com`   | System monitoring            |

**Laptop SSH config (`~/.ssh/config`):**
```
Host ssh.setiady.com
  ProxyCommand cloudflared access ssh --hostname ssh.setiady.com
  User dennysetiady
```

---

## Stack Deployment Order

When setting up from scratch, deploy in this order:

1. Initialize Docker Swarm: `docker swarm init`
2. Create shared-network: `docker network create --driver overlay --attachable shared-network`
3. Deploy **portainer** → connect to shared-network
4. Deploy **gitea** (registry needed for custom images)
5. Deploy **glances** (standalone `docker run`)
6. Deploy **lajula.app**
7. Deploy **sugarradar-staging**

