#!/usr/bin/env bash
#
# Weekly upkeep for the sugarradar-gh-runner. Run by
# sugarradar-gh-runner-maintenance.timer (Sun 04:00).
#
#   1. Re-pull the image. The runner self-updates its own binaries, but the
#      image can still drift far enough behind to matter; this is the backstop.
#      Only recreates when the pull actually produced a new image.
#   2. Clean up orphaned github_network_* bridges left by Actions jobs.
#
# Skips everything while a job is in flight.

set -uo pipefail

RUNNER="sugarradar-gh-runner"
COMPOSE_DIR="/home/dennysetiady/setiadyslab"
COMPOSE_FILE="docker-compose.sugarradar-gh-runner.yaml"
IMAGE="myoung34/github-runner:latest"

log() { echo "$*"; }

cd "$COMPOSE_DIR" || { log "FAILED: cannot cd to ${COMPOSE_DIR}"; exit 1; }

job_running() {
  local out start end
  out="$(docker logs --tail 300 "$RUNNER" 2>&1)" || return 1
  start="$(grep -n 'Running job:' <<<"$out" | tail -1 | cut -d: -f1)"
  [ -z "$start" ] && return 1
  end="$(grep -n 'completed with result' <<<"$out" | tail -1 | cut -d: -f1)"
  [ -z "$end" ] && return 0
  [ "$start" -gt "$end" ]
}

if job_running; then
  log "A job is in flight; skipping this run. The timer is Persistent, it will retry."
  exit 0
fi

# --- 1. image refresh -------------------------------------------------------
before="$(docker image inspect "$IMAGE" --format '{{.Id}}' 2>/dev/null || echo none)"
log "Pulling ${IMAGE} ..."
docker pull -q "$IMAGE" 2>&1 | sed 's/^/  /'
after="$(docker image inspect "$IMAGE" --format '{{.Id}}' 2>/dev/null || echo none)"

if [ "$before" != "$after" ]; then
  log "New image (${before:0:19} -> ${after:0:19}); recreating runner."
  docker compose -f "$COMPOSE_FILE" up -d --force-recreate 2>&1 | sed 's/^/  /'
else
  log "Image unchanged; not recreating."
fi

# --- 2. orphan network cleanup ---------------------------------------------
if [ -x "${COMPOSE_DIR}/cleanup-gh-runner-networks.sh" ]; then
  log "Cleaning orphaned github_network_* bridges ..."
  "${COMPOSE_DIR}/cleanup-gh-runner-networks.sh" 2>&1 | sed 's/^/  /'
else
  log "cleanup-gh-runner-networks.sh not executable; skipping network cleanup."
fi

log "Maintenance complete."
