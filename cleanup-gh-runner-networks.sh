#!/usr/bin/env bash
#
# Restart the sugarradar-gh-runner container and prune orphaned
# `github_network_*` bridges left behind by GitHub Actions jobs.
#
# The runner stays attached to every per-job network it ever orchestrated,
# so `docker network prune` cannot remove them on its own. Restarting the
# runner detaches it from all of them; prune then sweeps them.
#
# Usage:
#   ./cleanup-gh-runner-networks.sh          # abort if a job is running
#   ./cleanup-gh-runner-networks.sh --force  # restart even if a job is running

set -euo pipefail

RUNNER="sugarradar-gh-runner"
FORCE="${1:-}"

if ! docker inspect "$RUNNER" >/dev/null 2>&1; then
  echo "Runner container '$RUNNER' not found. Nothing to do." >&2
  exit 1
fi

mapfile -t NETWORKS < <(docker network ls --filter name=github_network --format '{{.Name}}')

if [ "${#NETWORKS[@]}" -eq 0 ]; then
  echo "No github_network_* networks present. Nothing to clean."
  exit 0
fi

echo "Found ${#NETWORKS[@]} github_network_* network(s)."

# A network with more than just the runner attached means an Actions job is
# currently using it (service containers like postgres/redis are still up).
LIVE=()
for net in "${NETWORKS[@]}"; do
  count=$(docker network inspect "$net" --format '{{len .Containers}}')
  if [ "$count" -gt 1 ]; then
    LIVE+=("$net")
  fi
done

if [ "${#LIVE[@]}" -gt 0 ]; then
  echo
  echo "WARNING: ${#LIVE[@]} network(s) have non-runner containers attached"
  echo "  (a GitHub Actions job is likely in progress):"
  for net in "${LIVE[@]}"; do
    echo "  - $net"
    docker network inspect "$net" --format '      {{range .Containers}}{{.Name}} {{end}}'
  done
  if [ "$FORCE" != "--force" ]; then
    echo
    echo "Refusing to restart the runner mid-job. Re-run with --force to override."
    exit 2
  fi
  echo
  echo "--force given; proceeding anyway."
fi

echo
echo "Restarting $RUNNER ..."
docker restart "$RUNNER" >/dev/null
echo "Runner restarted."

echo
echo "Pruning unused networks ..."
docker network prune -f

REMAINING=$(docker network ls --filter name=github_network --format '{{.Name}}' | wc -l)
echo
echo "Done. Remaining github_network_* networks: $REMAINING"
