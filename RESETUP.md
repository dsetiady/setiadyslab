# Homelab Resetup Guide

## Background
During a Docker network migration attempt, `cloudflared` was disconnected from `shared-network`,
cutting off all remote access to the homelab. This guide covers the full resetup procedure
including bulletproof remote access, Docker Swarm migration, and stack redeployment.

---

## Phase 1 — Physical Access (on arrival)

1. Power on the NUC
2. Connect monitor + keyboard temporarily
3. Log in

---

## Phase 2 — Bulletproof Remote Access

> ⚠️ **Do this FIRST before anything else. Test remote access before disconnecting the monitor.**

### Install cloudflared as native binary (replaces Docker container)

```bash
curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -o cloudflared
sudo mv cloudflared /usr/local/bin/
sudo chmod +x /usr/local/bin/cloudflared
sudo cloudflared service install <your-tunnel-token>
sudo systemctl enable cloudflared
sudo systemctl start cloudflared
```

### Install SSH

```bash
sudo apt install openssh-server
sudo systemctl enable ssh
sudo systemctl start ssh
```

### Configure Cloudflare Zero Trust for SSH

In Cloudflare Zero Trust → **Networks → Tunnels → your tunnel → Edit → Public Hostname → Add:**

| Field | Value |
|---|---|
| Subdomain | `ssh` |
| Domain | `setiady.com` |
| Service Type | `SSH` |
| URL | `localhost:22` |

### Configure SSH on your laptop

Install cloudflared locally:
```bash
brew install cloudflared
```

Add to `~/.ssh/config`:
```
Host ssh.setiady.com
  ProxyCommand cloudflared access ssh --hostname ssh.setiady.com
  User dennysetiady
```

### Test remote access (while monitor is still connected)

```bash
ssh ssh.setiady.com
```

> ✅ Only proceed to the next phase after confirming SSH works.

### Set BIOS → Power On after AC loss

While the monitor is still connected, enter BIOS and set **After State / AC Power Recovery → Power On**.
This ensures the NUC boots automatically after a power cycle.

---

## Phase 3 — Remove old cloudflared Docker container

```bash
docker stop cloudflared
docker rm cloudflared
```

---

## Phase 4 — Initialize Docker Swarm

```bash
docker swarm init
```

If the server has multiple network interfaces:
```bash
docker swarm init --advertise-addr <your-server-ip>
```

---

## Phase 5 — Recreate shared-network as overlay

```bash
docker network rm shared-network
docker network create --driver overlay --attachable shared-network
```

---

## Phase 6 — Reconnect Portainer to shared-network

```bash
docker network connect shared-network portainer
```

---

## Phase 7 — Redeploy stacks in Portainer

Deploy in this order:

### 1. sshwifty
Deploy via Portainer stack using `docker-compose.sshwifty.yaml`.

### 2. glances
> ⚠️ `privileged: true` and `pid: host` are **not supported in Docker Swarm**.
> Run as a standalone container outside Portainer:

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

### 3. registry
Deploy via Portainer stack using `docker-compose.registry.yaml`.

### 4. gitea
Deploy via Portainer stack using `docker-compose.gitea.yaml`.

Set env var in Portainer:
- `GITEA_DB_PASSWORD` — your Gitea database password

### 5. lajula.app
Deploy via Portainer stack using `docker-compose.lajula.app.yaml`.

### 6. sugarradar-staging
Deploy via Portainer stack using `docker-compose.sugarradar-staging.yaml`.

Set env vars in Portainer:
```
POSTGRES_HOST=sugarradar-staging-postgres
POSTGRES_PORT=5432
POSTGRES_USER=
POSTGRES_PASSWORD=
POSTGRES_DB=sugarradar

REDIS_ADDR=sugarradar-redis:6379

AI_PROVIDER=gemini
OPENAI_API_KEY=
GEMINI_API_KEY=

JWT_SECRET=
FREE_DAILY_SCAN_LIMIT=2
MAX_BONUS_SCANS_PER_DAY=4

SPACES_ACCESS_KEY=
SPACES_SECRET_KEY=
SPACES_REGION=sgp1
SPACES_BUCKET=sugarradar
SPACES_ENDPOINT=https://sgp1.digitaloceanspaces.com
SPACES_CDN_URL=

LOG_LEVEL=debug
LOG_FORMAT=json

GOOGLE_CLIENT_IDS=

REVENUECAT_SECRET_KEY=
REVENUECAT_PROJECT_ID=
REVENUECAT_ENTITLEMENT_ID=Sugar Radar Pro
REVENUECAT_SYNC_COOLDOWN_SECONDS=300

SMTP_HOST=sugarradar-staging-mailpit
SMTP_PORT=1025
SMTP_FROM_EMAIL=SugarRadar <noreply@sugarradar.local>
SMTP_USERNAME=
SMTP_PASSWORD=
```

---

## Phase 8 — Verify

```bash
docker node ls       # Should show 1 node, Ready, Leader
docker service ls    # Should show all services running
docker network ls    # shared-network should show overlay driver
```

---

## Lessons Learned

- **Never disconnect `cloudflared` from any network without SSH access as fallback**
- `cloudflared` should always run as a native systemd service, not a Docker container
- SSH + Cloudflare Tunnel should always be configured before doing infrastructure changes
- Set BIOS power recovery so the server auto-boots after power loss
