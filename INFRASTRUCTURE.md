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

### Port Range Scheme

| Range     | Owner                                                        |
|-----------|--------------------------------------------------------------|
| 1025      | mailpit SMTP (special case — standard dev SMTP port)         |
| 2222      | gitea SSH (special case — standard containerized git SSH)    |
| 3000–3099 | Infrastructure services                                      |
| 8000–8099 | SugarRadar Staging                                           |
| 8100–8199 | SugarRadar Production *(reserved)*                           |
| 9000–9099 | Ops tools *(portainer stays at 9443 — standard portainer port)* |

### Host-Exposed Ports

| Host Port | Container Port | Service                               | Stack              |
|-----------|----------------|---------------------------------------|--------------------|
| 2222      | 22             | `gitea` SSH                           | gitea              |
| 3000      | 3000           | `gitea`                               | gitea              |
| 3025      | 8025           | `mailpit` web UI                      | mailpit            |
| 1025      | 1025           | `mailpit` SMTP                        | mailpit            |
| 9443      | 9443           | `portainer` (localhost only)          | portainer          |
| 8000      | 8080           | `sugarradar-staging-sucrose` API      | sugarradar-staging |
| 8001      | 5173           | `sugarradar-staging-glucose` frontend | sugarradar-staging |
| 8002      | 3000           | `sugarradar-staging-dbgate` DB admin  | sugarradar-staging |
| 8003      | 8080           | `sugarradar-staging-asynqmon`         | sugarradar-staging |

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

### 3. Mailpit (`docker-compose.mailpit.yaml`)

Shared SMTP mail catcher for all app stacks in development/staging. Any service on `shared-network` can send mail to `mailpit:1025`.

| Container | Image                    | Network          | Notes                    |
|-----------|--------------------------|------------------|--------------------------|
| `mailpit` | `axllent/mailpit:latest` | `shared-network` | Web :3025, SMTP :1025    |

Cloudflare route: `mail.setiady.com` → `localhost:3025`

**Usage in app stacks:**
```
SMTP_HOST=mailpit
SMTP_PORT=1025
```

---

### 4. Glances (standalone container)

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

### 5. lajula.app (`docker-compose.lajula.app.yaml`)

| Container      | Image                                      | Network          |
|----------------|--------------------------------------------|------------------|
| `lajuladotapp` | `registry.setiady.com/lajuladotapp:v1.0.0` | `shared-network` |

Cloudflare route: `lajula.app` → `http://lajuladotapp:<port>` (via shared-network)

---

### 6. SugarRadar Staging (`docker-compose.sugarradar-staging.yaml`)

Full staging environment for the SugarRadar app.

#### Services

| Container                      | Image                                                | Network(s)                              | Port (host) |
|--------------------------------|------------------------------------------------------|-----------------------------------------|-------------|
| `sugarradar-staging-sucrose`   | `localhost:3000/sugarradar/sucrose:latest`           | `shared-network`, `sugarradar-internal` | 8000        |
| `sugarradar-sucrose-worker`    | `localhost:3000/sugarradar/sucrose-worker:latest`    | `sugarradar-internal`                   | —           |
| `sugarradar-sucrose-scheduler` | `localhost:3000/sugarradar/sucrose-scheduler:latest` | `sugarradar-internal`                   | —           |
| `sugarradar-staging-glucose`   | `localhost:3000/sugarradar/glucose:latest`           | `shared-network`, `sugarradar-internal` | 8001        |
| `sugarradar-staging-postgres`  | `postgres:16-alpine`                                 | `sugarradar-internal`                   | —           |
| `sugarradar-staging-redis`     | `redis:7-alpine`                                     | `sugarradar-internal`                   | —           |
| `sugarradar-staging-dbgate`    | `dbgate/dbgate:latest`                               | `shared-network`, `sugarradar-internal` | 8002        |
| `sugarradar-staging-asynqmon`  | `hibiken/asynqmon:0.7.2`                             | `shared-network`, `sugarradar-internal` | 8003        |

#### Service Roles

- **sucrose** — Go REST API backend
- **sucrose-worker** — Background job processor (Asynq)
- **sucrose-scheduler** — Periodic task scheduler
- **glucose** — Frontend (Vite/React)
- **dbgate** — Database + Redis admin UI
- **asynqmon** — Asynq queue monitor UI

#### Cloudflare Routes

| Hostname                           | URL              | Service          |
|------------------------------------|------------------|------------------|
| `staging-sucrose.sugarradar.com`   | `localhost:8000` | sucrose API      |
| `staging-glucose.sugarradar.com`   | `localhost:8001` | glucose frontend |
| `staging-dbgate.sugarradar.com`    | `localhost:8002` | dbgate           |
| `staging-asynqmon.sugarradar.com`  | `localhost:8003` | asynqmon         |

#### Key Env Vars

| Variable        | Example Value                   | Notes                                   |
|-----------------|---------------------------------|-----------------------------------------|
| `POSTGRES_HOST` | `sugarradar-staging-postgres`   | Must use container name, not `postgres` |
| `POSTGRES_PORT` | `5432`                          |                                         |
| `POSTGRES_DB`   | `sugarradar`                    |                                         |
| `REDIS_ADDR`    | `sugarradar-staging-redis:6379` | Must use container name                 |
| `SMTP_HOST`     | `mailpit`                       | Shared mailpit on `shared-network`      |
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
| Mailpit       | `https://mail.setiady.com`      | Shared dev mail UI           |

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
5. Deploy **mailpit**
6. Deploy **glances** (standalone `docker run`)
7. Deploy **lajula.app**
8. Deploy **sugarradar-staging**
