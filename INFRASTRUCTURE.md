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
| `sugarradar-production-internal` | overlay                   | Internal sugarradar-production services only      |
| `gitea-internal`       | overlay                        | Internal Gitea + DB only                          |
| `n8n-internal`         | overlay                        | Internal n8n + DB only                            |
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
| 4000–4099 | Automation & workflow tools                                   |
| 8000–8099 | SugarRadar Staging                                           |
| 8100–8199 | SugarRadar Production                                        |
| 8200–8299 | lajula.app                                                   |
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
| 8001      | 80             | `sugarradar-staging-glucose` frontend | sugarradar-staging |
| 8002      | 3000           | `sugarradar-staging-dbgate` DB admin  | sugarradar-staging |
| 8003      | 8080           | `sugarradar-staging-asynqmon`         | sugarradar-staging |
| 4000      | 5678           | `n8n` web UI                          | n8n                |
| 8100      | 8080           | `sugarradar-production-sucrose` API         | sugarradar-production |
| 8101      | 80             | `sugarradar-production-glucose` frontend    | sugarradar-production |
| 8102      | 3000           | `sugarradar-production-dbgate` DB admin     | sugarradar-production |
| 8103      | 8080           | `sugarradar-production-asynqmon`            | sugarradar-production |
| 8200      | 80             | `lajuladotapp` web service            | lajuladotapp       |
| 9001      | 3000           | `observability-grafana` log dashboard | observability      |
| 9002      | 8090           | `beszel` monitoring dashboard         | beszel             |

### Internal-Only (no host binding)

| Container Port | Service                       | Reachable via                 |
|----------------|-------------------------------|-------------------------------|
| 5432           | `sugarradar-staging-postgres` | `sugarradar-internal` network      |
| 6379           | `sugarradar-staging-redis`    | `sugarradar-internal` network      |
| 5432           | `sugarradar-production-postgres`    | `sugarradar-production-internal` network |
| 6379           | `sugarradar-production-redis`       | `sugarradar-production-internal` network |
| 5432           | `gitea-db`                    | `gitea-internal` network      |
| 5432           | `n8n-postgres`                | `n8n-internal` network        |

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

#### Resource Limits

| Container  | Memory | CPU |
|------------|--------|-----|
| `gitea`    | 1 GB   | 2.0 |
| `gitea-db` | 512 MB | 1.0 |

**Env vars required:**
- `GITEA_DB_PASSWORD`

---

### 3. Mailpit (`docker-compose.mailpit.yaml`)

Shared SMTP mail catcher for all app stacks in development/staging. Any service on `shared-network` can send mail to `mailpit:1025`.

| Container | Image                    | Network          | Notes                    |
|-----------|--------------------------|------------------|--------------------------|
| `mailpit` | `axllent/mailpit:latest` | `shared-network` | Web :3025, SMTP :1025    |

Cloudflare route: `mail.setiady.com` → `localhost:3025`

#### Resource Limits

| Container | Memory | CPU |
|-----------|--------|-----|
| `mailpit` | 128 MB | 0.5 |

**Usage in app stacks:**
```
SMTP_HOST=mailpit
SMTP_PORT=1025
```

---

### 4. Glances (standalone container)

System monitoring. Not a Swarm stack — requires `--pid host` and `--privileged` which Swarm does not support.

The dashboard is customized via `glances/glances.conf` in this repo. It tunes thresholds for the 22-core / 30 GiB host, disables noisy plugins (wifi, raid, smart, ports, irq, gpu, amps, ip, now), filters network interfaces to physical NICs, watches `/var/lib/docker/volumes` and `/var/lib/docker/containers` via the folders plugin, and shows host filesystem usage by bind-mounting `/` at `/rootfs:ro` (so the FS panel reports the real 1.8 TB disk, not the container's overlay).

UI tweaks live in `glances/index.html` — a custom version of the SPA shell with a `<style>` block injecting CSS that Glances' bundled JS doesn't expose otherwise (currently: row-hover highlight on the containers panel, matching the processlist behavior).

To deploy or update, copy the conf to the host and (re)create the container:

```bash
# From repo root:
scp glances/glances.conf dennysetiady@<host>:~/glances/glances.conf
scp glances/index.html  dennysetiady@<host>:~/glances/index.html

# On the host:
docker stop glances && docker rm glances
docker run -d --restart unless-stopped \
  --pid host --privileged \
  --security-opt label=disable \
  --network shared-network \
  -p 127.0.0.1:61208:61208 \
  -v /var/run/docker.sock:/var/run/docker.sock:ro \
  -v /etc/os-release:/etc/os-release:ro \
  -v ~/glances/glances.conf:/etc/glances/glances.conf:ro \
  -v ~/glances/index.html:/app/glances/outputs/static/templates/index.html:ro \
  -v /var/lib/docker:/var/lib/docker:ro \
  -v /:/rootfs:ro \
  -e GLANCES_OPT="-w -C /etc/glances/glances.conf" \
  --name glances \
  nicolargo/glances:latest-full
```

After editing only `glances.conf`, `docker restart glances` is enough — no need to recreate.

Cloudflare route: `glances.setiady.com` → `http://glances:61208` (via shared-network)

---

### 5. lajula.app (`docker-compose.lajuladotapp.yaml`)

| Container      | Image                                             | Network          | Port (host) |
|----------------|---------------------------------------------------|------------------|-------------|
| `lajuladotapp` | `localhost:3000/lajuladotapp/lajuladotapp:latest` | `shared-network` | 8200        |

Port range: **8200–8299**. The image is nginx and listens on container port `80`, published on host `8200`.

Cloudflare route: `lajula.app` → `localhost:8200`

---

### 6. n8n (`docker-compose.n8n.yaml`)

Workflow automation platform backed by PostgreSQL.

#### Services

| Container     | Image                | Network(s)                     | Port (host) |
|---------------|----------------------|--------------------------------|-------------|
| `n8n`         | `n8nio/n8n:latest`   | `shared-network`, `n8n-internal` | 4000        |
| `n8n-postgres`| `postgres:16-alpine` | `n8n-internal`                 | —           |

Cloudflare route: `n8n.setiady.com` → `localhost:4000`

#### Resource Limits

| Container      | Memory | CPU |
|----------------|--------|-----|
| `n8n`          | 1 GB   | 2.0 |
| `n8n-postgres` | 512 MB | 1.0 |

#### Key Env Vars

| Variable              | Example Value         | Notes                                        |
|-----------------------|-----------------------|----------------------------------------------|
| `POSTGRES_DB`         | `n8n`                 |                                              |
| `POSTGRES_USER`       | `n8n`                 |                                              |
| `POSTGRES_PASSWORD`   | *(secret)*            | Set in Portainer                             |
| `N8N_ENCRYPTION_KEY`  | *(secret)*            | `openssl rand -hex 32` — store permanently   |
| `N8N_HOST`            | `n8n.setiady.com`     |                                              |
| `WEBHOOK_URL`         | `https://n8n.setiady.com` |                                          |
| `GENERIC_TIMEZONE`    | `Asia/Jakarta`        |                                              |

---

### 7. SugarRadar Staging (`docker-compose.sugarradar-staging.yaml`)

Full staging environment for the SugarRadar app.

#### Services

| Container                      | Image                                                | Network(s)                              | Port (host) |
|--------------------------------|------------------------------------------------------|-----------------------------------------|-------------|
| `sugarradar-staging-sucrose`   | `localhost:3000/sugarradar/sucrose:0.0.1`            | `shared-network`, `sugarradar-internal` | 8000        |
| `sugarradar-sucrose-worker`    | `localhost:3000/sugarradar/sucrose-worker:0.0.1`     | `sugarradar-internal`                   | —           |
| `sugarradar-sucrose-scheduler` | `localhost:3000/sugarradar/sucrose-scheduler:0.0.1`  | `sugarradar-internal`                   | —           |
| `sugarradar-staging-glucose`   | `localhost:3000/sugarradar/glucose:0.0.1`            | `shared-network`, `sugarradar-internal` | 8001        |
| `sugarradar-staging-postgres`  | `postgres:16-alpine`                                 | `sugarradar-internal`                   | —           |
| `sugarradar-staging-redis`     | `redis:7-alpine`                                     | `sugarradar-internal`                   | —           |
| `sugarradar-staging-dbgate`    | `dbgate/dbgate:7.1.9`                                | `shared-network`, `sugarradar-internal` | 8002        |
| `sugarradar-staging-asynqmon`  | `hibiken/asynqmon:0.7.2`                             | `shared-network`, `sugarradar-internal` | 8003        |

#### Service Roles

- **sucrose** — Go REST API backend
- **sucrose-worker** — Background job processor (Asynq)
- **sucrose-scheduler** — Periodic task scheduler
- **glucose** — Frontend (Vite/React)
- **dbgate** — Database + Redis admin UI
- **asynqmon** — Asynq queue monitor UI

#### Resource Limits

| Container                      | Memory | CPU |
|--------------------------------|--------|-----|
| `sugarradar-staging-sucrose`   | 512 MB | 2.0 |
| `sugarradar-sucrose-worker`    | 512 MB | 2.0 |
| `sugarradar-sucrose-scheduler` | 256 MB | 1.0 |
| `sugarradar-staging-postgres`  | 512 MB | 1.0 |
| `sugarradar-staging-redis`     | 256 MB | 0.5 |
| `sugarradar-staging-glucose`   | 256 MB | 0.5 |
| `sugarradar-staging-dbgate`    | 256 MB | 0.5 |
| `sugarradar-staging-asynqmon`  | 128 MB | 0.5 |

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

### 8. SugarRadar Production (`docker-compose.sugarradar-production.yaml`)

Production environment for the SugarRadar app with automated database backups.

#### Services

| Container                          | Image                                                    | Network(s)                                   | Port (host) |
|------------------------------------|----------------------------------------------------------|----------------------------------------------|-------------|
| `sugarradar-production-sucrose`          | `localhost:3000/sugarradar/sucrose:0.0.1`                | `shared-network`, `sugarradar-production-internal` | 8100        |
| `sugarradar-production-sucrose-worker`   | `localhost:3000/sugarradar/sucrose-worker:0.0.1`         | `sugarradar-production-internal`                   | —           |
| `sugarradar-production-sucrose-scheduler`| `localhost:3000/sugarradar/sucrose-scheduler:0.0.1`      | `sugarradar-production-internal`                   | —           |
| `sugarradar-production-glucose`          | `localhost:3000/sugarradar/glucose:0.0.1`                | `shared-network`, `sugarradar-production-internal` | 8101        |
| `sugarradar-production-postgres`         | `postgres:16-alpine`                                     | `sugarradar-production-internal`                   | —           |
| `sugarradar-production-redis`            | `redis:7-alpine`                                         | `sugarradar-production-internal`                   | —           |
| `sugarradar-production-pg-backup`        | `prodrigestivill/postgres-backup-local:16-alpine`        | `sugarradar-production-internal`                   | —           |
| `sugarradar-production-dbgate`           | `dbgate/dbgate:7.1.9`                                    | `shared-network`, `sugarradar-production-internal` | 8102        |
| `sugarradar-production-asynqmon`         | `hibiken/asynqmon:0.7.2`                                 | `shared-network`, `sugarradar-production-internal` | 8103        |

#### Resource Limits

| Container                           | Memory | CPU |
|-------------------------------------|--------|-----|
| `sugarradar-production-sucrose`           | 512 MB | 2.0 |
| `sugarradar-production-sucrose-worker`    | 512 MB | 2.0 |
| `sugarradar-production-sucrose-scheduler` | 256 MB | 1.0 |
| `sugarradar-production-postgres`          | 512 MB | 1.0 |
| `sugarradar-production-redis`             | 256 MB | 0.5 |
| `sugarradar-production-pg-backup`         | 256 MB | 0.5 |
| `sugarradar-production-glucose`           | 256 MB | 0.5 |
| `sugarradar-production-dbgate`            | 256 MB | 0.5 |
| `sugarradar-production-asynqmon`          | 128 MB | 0.5 |

#### Database Backup

Automated PostgreSQL backups using `postgres-backup-local`:

| Setting              | Value   |
|----------------------|---------|
| Schedule             | Daily   |
| Keep daily backups   | 7 days  |
| Keep weekly backups  | 4 weeks |
| Keep monthly backups | 6 months|
| Backup volume        | `sugarradar-production-pg-backups` |

Backups are stored as compressed SQL dumps in the `sugarradar-production-pg-backups` volume.

To restore a backup:
```bash
# List available backups
docker exec sugarradar-production-pg-backup ls /backups/sugarradar

# Restore a specific backup
docker exec -i sugarradar-production-postgres pg_restore -U <user> -d <db> < backup_file.sql
# Or for plain SQL dumps:
docker exec -i sugarradar-production-postgres psql -U <user> -d <db> < backup_file.sql.gz
```

#### Cloudflare Routes

| Hostname                      | URL              | Service          |
|-------------------------------|------------------|------------------|
| `sucrose.sugarradar.com`      | `localhost:8100` | sucrose API      |
| `glucose.sugarradar.com`      | `localhost:8101` | glucose frontend |
| `prod-dbgate.sugarradar.com`  | `localhost:8102` | dbgate           |
| `prod-asynqmon.sugarradar.com`| `localhost:8103` | asynqmon         |

#### Key Env Vars

| Variable        | Example Value                | Notes                                             |
|-----------------|------------------------------|---------------------------------------------------|
| `POSTGRES_HOST` | `sugarradar-production-postgres`   | Must use container name, not `postgres`           |
| `POSTGRES_PORT` | `5432`                       |                                                   |
| `POSTGRES_DB`   | `sugarradar`                 | Use a separate DB name from staging               |
| `REDIS_ADDR`    | `sugarradar-production-redis:6379` | Must use container name                           |
| `DBGATE_LOGIN`  | *(dbgate username)*          | Basic auth for prod-dbgate.sugarradar.com         |
| `DBGATE_PASSWORD` | *(dbgate password)*        | Basic auth for prod-dbgate.sugarradar.com         |
| `SMTP_HOST`     | *(real SMTP provider)*       | Do NOT use mailpit — use a real email provider    |
| `SMTP_PORT`     | `587`                        |                                                   |
| `AI_PROVIDER`   | `gemini`                     |                                                   |
| `LOG_LEVEL`     | `info`                       | Avoid `debug` in production                       |
| `SPACES_REGION` | `sgp1`                       | Use a separate bucket from staging                |

#### Key Differences from Staging

- Image tag: `:stable` instead of `:latest` — push tested images as `:stable` before deploying
- SMTP: use a real email provider (not mailpit)
- Separate Docker volumes, network, and env vars in Portainer
- Automated daily database backups with retention

---

### 10. SugarRadar GitHub Runner (`docker-compose.sugarradar-gh-runner.yaml`)

Self-hosted GitHub Actions runner registered to the `lajuladotapp/sugarradar` repo. Runs in a privileged container (required for KVM/nested virtualization workloads). No host ports — runner reaches GitHub via outbound HTTPS only.

**Not a Swarm stack.** Swarm strips the `devices:` and `device_cgroup_rules:` compose keys, so it can't grant cgroup access to `/dev/kvm`. On cgroup v2 hosts (Ubuntu 22.04+), `privileged: true` alone is not enough — device control is BPF-managed and requires an explicit cgroup rule. We therefore deploy this stack via plain `docker compose up -d` on the host, not via Portainer/Swarm.

#### Services

| Container              | Image                          | Network(s) | Port (host) |
|------------------------|--------------------------------|------------|-------------|
| `sugarradar-gh-runner` | `myoung34/github-runner:latest` | default    | —           |

#### Resource Limits

| Container              | Memory limit | CPU limit |
|------------------------|--------------|-----------|
| `sugarradar-gh-runner` | 16 GB        | 4.0       |

#### PAT secret

The runner needs a GitHub fine-grained PAT (repo Administration: Read/Write) to register itself. Store it on the host at `~/secrets/gh_runner_pat`, root-owned, mode `0600`. Compose mounts it into the container at `/run/secrets/gh_runner_pat`.

```bash
mkdir -p ~/secrets && chmod 700 ~/secrets
printf '%s' "<your-PAT>" > ~/secrets/gh_runner_pat
chmod 600 ~/secrets/gh_runner_pat
```

#### Key Env Vars (configured in the compose file)

| Variable        | Value                                                |
|-----------------|------------------------------------------------------|
| `REPO_URL`      | `https://github.com/lajuladotapp/sugarradar`         |
| `RUNNER_NAME`   | `sugarradar-setiadyslabs-1`                          |
| `RUNNER_SCOPE`  | `repo`                                               |
| `LABELS`        | `self-hosted,linux,kvm`                              |

#### Deploy / update

From the repo root on the host:

```bash
docker compose -f docker-compose.sugarradar-gh-runner.yaml up -d
docker compose -f docker-compose.sugarradar-gh-runner.yaml logs -f
docker compose -f docker-compose.sugarradar-gh-runner.yaml down  # to stop
```

The container is still visible in Portainer's "Containers" tab — you just can't manage the *stack* from Portainer.

---

## Remote Access Summary

| Access Method | URL                             | Notes                        |
|---------------|---------------------------------|------------------------------|
| SSH           | `ssh ssh.setiady.com`           | Via cloudflared ProxyCommand |
| Portainer     | `https://portainer.setiady.com` | Stack management             |
| Gitea         | `https://gitea.setiady.com`     | Git + registry               |
| Glances       | `https://glances.setiady.com`   | System monitoring            |
| Mailpit       | `https://mail.setiady.com`      | Shared dev mail UI           |
| n8n           | `https://n8n.setiady.com`       | Workflow automation          |
| lajula.app    | `https://lajula.app`            | lajula.app web service       |
| Grafana       | `https://grafana.setiady.com`   | Log aggregation (Loki)       |

**Laptop SSH config (`~/.ssh/config`):**
```
Host ssh.setiady.com
  ProxyCommand cloudflared access ssh --hostname ssh.setiady.com
  User dennysetiady
```

---

### 9. Observability (`docker-compose.observability.yaml`)

Shared log aggregation stack. Promtail auto-discovers all Docker containers and ships structured logs to Loki. Grafana provides search and dashboards.

#### Services

| Container                | Image                      | Network(s)                               | Port (host) |
|--------------------------|----------------------------|------------------------------------------|-------------|
| `observability-loki`     | `grafana/loki:3.0.0`      | `observability-internal`                 | —           |
| `observability-promtail` | `grafana/promtail:3.0.0`  | `observability-internal`                 | —           |
| `observability-grafana`  | `grafana/grafana:11.0.0`  | `shared-network`, `observability-internal` | 9001      |

#### Resource Limits

| Container                | Memory | CPU |
|--------------------------|--------|-----|
| `observability-loki`     | 512 MB | 1.0 |
| `observability-promtail` | 256 MB | 0.5 |
| `observability-grafana`  | 256 MB | 0.5 |

Cloudflare route: `grafana.setiady.com` → `localhost:9001`

#### Key Env Vars

| Variable                 | Example Value | Notes                    |
|--------------------------|---------------|--------------------------|
| `GRAFANA_ADMIN_PASSWORD` | *(secret)*    | Set in Portainer         |

#### Useful Queries (Grafana → Explore → Loki)

```
# All SugarRadar logs
{container=~"sugarradar.*"}

# Errors only
{container=~"sugarradar.*"} | json | level="error"

# Webhook events
{container="sugarradar-staging-sucrose"} |= "webhook"

# Push notifications
{container="sugarradar-staging-sucrose"} | json | component="expo_push_gateway"

# Trace a request
{container="sugarradar-staging-sucrose"} | json | trace_id="<uuid>"

# Slow operations
{container=~"sugarradar.*"} | json | duration_ms > 1000

# All projects
{container=~"gitea.*"}
{container=~"n8n.*"}
```

---

### 11. Beszel (`docker-compose.beszel.yaml`)

Lightweight host + Docker monitoring — the glances replacement. The **hub** (web UI + DB) runs as a Swarm stack; the **agent** (collector) runs as a standalone container because it needs host networking + docker.sock, which Swarm strips (like glances / gh-runner).

#### Services

| Container      | Image                         | Network(s)       | Port (host)  | Deploy                   |
|----------------|-------------------------------|------------------|--------------|--------------------------|
| `beszel`       | `henrygd/beszel:0.18.7`       | `shared-network` | 9002         | Swarm stack              |
| `beszel-agent` | `henrygd/beszel-agent:0.18.7` | host networking  | 45876 (host) | Standalone `docker run`  |

#### Resource Limits

| Container      | Memory | CPU |
|----------------|--------|-----|
| `beszel`       | 256 MB | 0.5 |
| `beszel-agent` | 128 MB | —   |

Cloudflare route: `beszel.setiady.com` → `localhost:9002`

#### Setup

1. Deploy the `beszel` hub stack (Portainer).
2. Open `https://beszel.setiady.com`, create the admin account, click **Add System**, copy the public key.
3. On the host, run the agent (see the commented `docker run` block in `docker-compose.beszel.yaml`) with that `KEY`.
4. In the hub, add the system with host `host.docker.internal`, port `45876`. The hub reaches the agent via a `host-gateway` entry.

The agent reports host CPU / mem / disk / network **and sensors** — including the NUC's CPU temperature and fan RPM.

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
8. Deploy **n8n**
9. Deploy **observability** (Loki + Grafana)
10. Deploy **sugarradar-staging**
11. Deploy **sugarradar-production**
12. Deploy **sugarradar-gh-runner** (standalone `docker compose up -d` — not a Swarm stack)
13. Deploy **beszel** (hub as Swarm stack; agent as standalone `docker run` — not a Swarm stack)
