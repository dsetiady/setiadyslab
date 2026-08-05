# setiadyslab

Docker Swarm homelab running on a single Intel NUC, managed via Portainer. All external access goes through Cloudflare Tunnel — no open inbound ports on the router.

## Docs

- [`INFRASTRUCTURE.md`](INFRASTRUCTURE.md) — Full stack reference: services, ports, networks, Cloudflare routes

## Stacks

| Stack                                                                       | Description                        |
|-----------------------------------------------------------------------------|------------------------------------|
| [`portainer-agent-stack.yml`](portainer-agent-stack.yml)                            | Container management UI              |
| [`docker-compose.gitea.yaml`](docker-compose.gitea.yaml)                            | Self-hosted Git + container registry |
| [`docker-compose.mailpit.yaml`](docker-compose.mailpit.yaml)                        | Shared SMTP mail catcher             |
| [`docker-compose.lajuladotapp.yaml`](docker-compose.lajuladotapp.yaml)              | lajula.app web service               |
| [`docker-compose.n8n.yaml`](docker-compose.n8n.yaml)                                | n8n workflow automation               |
| [`docker-compose.sugarradar-staging.yaml`](docker-compose.sugarradar-staging.yaml)  | SugarRadar staging environment       |
| [`docker-compose.sugarradar-production.yaml`](docker-compose.sugarradar-production.yaml) | SugarRadar production environment |
| [`docker-compose.sugarradar-gh-runner.yaml`](docker-compose.sugarradar-gh-runner.yaml) | Self-hosted GitHub Actions runner for sugarradar |
| [`docker-compose.observability.yaml`](docker-compose.observability.yaml)            | Loki + Grafana log aggregation       |
| [`docker-compose.beszel.yaml`](docker-compose.beszel.yaml)                          | Beszel host + Docker monitoring      |

## Quick Reference

- **Portainer:** `https://portainer.setiady.com`
- **Gitea:** `https://gitea.setiady.com`
- **SSH:** `ssh ssh.setiady.com`

## Remote Access

cloudflared runs as a native systemd service on the host. SSH access goes through Cloudflare Zero Trust.

```
Host ssh.setiady.com
  ProxyCommand cloudflared access ssh --hostname ssh.setiady.com
  User dennysetiady
```
