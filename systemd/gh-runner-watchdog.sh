#!/usr/bin/env bash
#
# Detect and repair a broken sugarradar-gh-runner.
#
# Run every 2 minutes by sugarradar-gh-runner-watchdog.timer. Output goes to the
# journal:  journalctl -u sugarradar-gh-runner-watchdog -f
#
# Conditions handled (each has actually happened on this host):
#   1. container missing                  -> recreate
#   2. crash-looping / restarting         -> recreate from a clean layer
#   3. "already configured" in logs       -> stale registration state, recreate
#   4. "cannot receive messages"          -> runner version deprecated, pull + recreate
#   5. healthcheck unhealthy              -> recreate
#
# A recreate is skipped while a job is running, so CI is never killed mid-job.
# A cooldown prevents a recreate storm when the fault is not self-healable; in
# that case it logs loudly and leaves the container alone for a human.

set -uo pipefail

RUNNER="sugarradar-gh-runner"
COMPOSE_DIR="/home/dennysetiady/setiadyslab"
COMPOSE_FILE="docker-compose.sugarradar-gh-runner.yaml"
STATE_DIR="/var/lib/gh-runner-watchdog"
COOLDOWN=900          # 15 min minimum between automatic recreates
RESTART_THRESHOLD=3   # restarts between checks that count as a crash loop

mkdir -p "$STATE_DIR"

log() { echo "$*"; }

# --- is a CI job in flight? -------------------------------------------------
job_running() {
  local out start end
  out="$(docker logs --tail 300 "$RUNNER" 2>&1)" || return 1
  start="$(grep -n 'Running job:' <<<"$out" | tail -1 | cut -d: -f1)"
  [ -z "$start" ] && return 1
  end="$(grep -n 'completed with result' <<<"$out" | tail -1 | cut -d: -f1)"
  [ -z "$end" ] && return 0
  [ "$start" -gt "$end" ]
}

# --- repair -----------------------------------------------------------------
heal() {
  local reason="$1" pull="${2:-no}" now last age
  now="$(date +%s)"
  last="$(cat "$STATE_DIR/last_heal" 2>/dev/null || echo 0)"
  age=$(( now - last ))

  if [ "$age" -lt "$COOLDOWN" ]; then
    log "PROBLEM: ${reason}"
    log "  Last automatic repair was ${age}s ago (cooldown ${COOLDOWN}s)."
    log "  Not recreating again -- this is not self-healing. NEEDS A HUMAN."
    log "  Inspect with: docker logs --tail 50 ${RUNNER}"
    return 1
  fi

  if job_running; then
    log "PROBLEM: ${reason} -- but a job is in flight; deferring repair to the next check."
    return 0
  fi

  log "PROBLEM: ${reason}"
  log "  Repairing: force-recreating ${RUNNER} from a clean image layer."

  cd "$COMPOSE_DIR" || { log "  FAILED: cannot cd to ${COMPOSE_DIR}"; return 1; }
  if [ "$pull" = "pull" ]; then
    log "  Pulling a fresh image first."
    docker compose -f "$COMPOSE_FILE" pull -q 2>&1 | sed 's/^/    /'
  fi

  if docker compose -f "$COMPOSE_FILE" up -d --force-recreate 2>&1 | sed 's/^/    /'; then
    echo "$now" > "$STATE_DIR/last_heal"
    log "  Repair complete."
  else
    log "  FAILED: docker compose up returned non-zero. NEEDS A HUMAN."
    return 1
  fi
}

# --- checks -----------------------------------------------------------------

# 1. missing
if ! docker inspect "$RUNNER" >/dev/null 2>&1; then
  heal "container ${RUNNER} does not exist"
  exit $?
fi

status="$(docker inspect "$RUNNER" --format '{{.State.Status}}')"
restarts="$(docker inspect "$RUNNER" --format '{{.RestartCount}}')"
health="$(docker inspect "$RUNNER" --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}')"

prev="$(cat "$STATE_DIR/restart_count" 2>/dev/null || echo "$restarts")"
echo "$restarts" > "$STATE_DIR/restart_count"
delta=$(( restarts - prev ))
[ "$delta" -lt 0 ] && delta=0   # container was recreated; counter reset

# 2. crash loop
if [ "$status" = "restarting" ] || [ "$delta" -ge "$RESTART_THRESHOLD" ]; then
  heal "crash loop -- status=${status}, ${delta} restart(s) since last check (total ${restarts})"
  exit $?
fi

if [ "$status" != "running" ]; then
  heal "container is ${status}, expected running"
  exit $?
fi

# 3/4. failure strings the container reports while nominally "running"
recent="$(docker logs --since 5m "$RUNNER" 2>&1)"

if grep -q 'cannot receive messages' <<<"$recent"; then
  heal "runner version is deprecated and cannot receive jobs" pull
  exit $?
fi

if grep -q 'already configured' <<<"$recent"; then
  heal "stale registration state -- 'already configured' in the last 5m" 
  exit $?
fi

# 5. healthcheck
if [ "$health" = "unhealthy" ]; then
  heal "healthcheck reports unhealthy"
  exit $?
fi

log "OK: ${RUNNER} running (health=${health}, total restarts=${restarts}, +${delta} since last check)"
