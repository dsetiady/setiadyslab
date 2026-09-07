#!/usr/bin/env bash
#
# Install the runner's systemd units and helper scripts. Idempotent -- safe to
# re-run after editing anything in this directory.
#
#   sudo ./systemd/install.sh
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

[ "$(id -u)" -eq 0 ] || { echo "Run with sudo." >&2; exit 1; }

echo "Installing helper scripts to /usr/local/bin ..."
install -m 0755 "$HERE/gh-runner-watchdog.sh"    /usr/local/bin/gh-runner-watchdog.sh
install -m 0755 "$HERE/gh-runner-maintenance.sh" /usr/local/bin/gh-runner-maintenance.sh

echo "Installing units to /etc/systemd/system ..."
install -m 0644 "$HERE"/sugarradar-gh-runner*.service /etc/systemd/system/
install -m 0644 "$HERE"/sugarradar-gh-runner*.timer   /etc/systemd/system/

systemctl daemon-reload

echo "Enabling ..."
systemctl enable sugarradar-gh-runner.service
systemctl enable --now sugarradar-gh-runner-watchdog.timer
systemctl enable --now sugarradar-gh-runner-maintenance.timer

echo
echo "Done. The runner container is NOT restarted by this script."
echo "To hand the running container over to systemd (recreates it):"
echo "    sudo systemctl start sugarradar-gh-runner"
echo
systemctl list-timers 'sugarradar-*' --no-pager || true
