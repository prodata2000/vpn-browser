#!/bin/bash
# install-tools.sh — minimal system prerequisites only
# Mounted at /custom-cont-init.d/01-install-tools.sh
# Runs before the desktop on every fresh container start.
#
# Only touches the Ubuntu apt cache — no network downloads beyond package mirrors.
#
#   python3-yaml  — pre-compiled PyYAML so pip never tries to build it from source
#                   (Python 3.14 has no PyYAML wheels yet; source builds fail)
#   curl          — needed by vpn-switch and the OSINT/comms setup scripts
#
# docker-compose is downloaded on first use by vpn-switch (saved to /config/bin).
# OSINT/comms tools are installed on demand: run  osint-setup  or  comms-setup.

set -e

export DEBIAN_FRONTEND=noninteractive
sudo rm -f /etc/apt/apt.conf.d/20packagekit 2>/dev/null || true

echo "[init] Installing system prerequisites..."
apt-get install -y -q --no-install-recommends python3-pip python3-yaml curl >/dev/null 2>&1
echo "[init] Done."
