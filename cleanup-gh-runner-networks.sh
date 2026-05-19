#!/usr/bin/env bash
#
# Detach the sugarradar-gh-runner from orphaned `github_network_*` bridges
# left behind by GitHub Actions jobs, then remove the networks.
#
# `docker restart` preserves network attachments, so prune alone cannot
# reclaim these networks — the runner remains the lone endpoint. We must
# explicitly `docker network disconnect` the runner from each idle network
# before removing it.
#
# A network with more than one container attached belongs to a running job
# and is skipped (use --force to override).
#
# Usage:
#   ./cleanup-gh-runner-networks.sh          # skip networks with a live job
#   ./cleanup-gh-runner-networks.sh --force  # detach even mid-job networks

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

LIVE=()
IDLE=()
for net in "${NETWORKS[@]}"; do
  count=$(docker network inspect "$net" --format '{{len .Containers}}')
  if [ "$count" -gt 1 ]; then
    LIVE+=("$net")
  else
    IDLE+=("$net")
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
    echo "Skipping live networks. Re-run with --force to clean them too."
  else
    echo
    echo "--force given; will also clean live networks."
    IDLE+=("${LIVE[@]}")
  fi
fi

if [ "${#IDLE[@]}" -eq 0 ]; then
  echo
  echo "Nothing to clean."
  exit 0
fi

echo
echo "Disconnecting $RUNNER from ${#IDLE[@]} network(s) and removing them ..."
REMOVED=0
FAILED=0
for net in "${IDLE[@]}"; do
  docker network disconnect -f "$net" "$RUNNER" >/dev/null 2>&1 || true
  if docker network rm "$net" >/dev/null 2>&1; then
    REMOVED=$((REMOVED + 1))
  else
    FAILED=$((FAILED + 1))
  fi
done

REMAINING=$(docker network ls --filter name=github_network --format '{{.Name}}' | wc -l)
echo
echo "Done. Removed $REMOVED network(s); $FAILED failed; $REMAINING github_network_* network(s) remain."
