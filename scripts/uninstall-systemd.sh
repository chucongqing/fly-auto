#!/bin/bash

set -e

SERVICES="nginx xray hy2 sing-box"

echo "[systemd] Stopping and disabling services ..."

for svc in $SERVICES; do
    if systemctl is-active --quiet "${svc}.service" 2>/dev/null; then
        systemctl stop "${svc}.service" || true
        echo "[systemd] Stopped ${svc}.service"
    fi
    if systemctl is-enabled --quiet "${svc}.service" 2>/dev/null; then
        systemctl disable "${svc}.service" || true
        echo "[systemd] Disabled ${svc}.service"
    fi
    if [ -f "/etc/systemd/system/${svc}.service" ]; then
        rm -f "/etc/systemd/system/${svc}.service"
        echo "[systemd] Removed ${svc}.service"
    fi
done

systemctl daemon-reload

echo "[DONE] All systemd services uninstalled."
