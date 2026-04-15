#!/usr/bin/env bash
# vpn-switch — change the active VPN server from inside the desktop
#
# Requires the Docker socket mounted at /var/run/docker.sock (set in docker-compose.yml).
# Switching causes a ~15-second desktop session interruption while gluetun restarts.
#
# Usage:
#   vpn-switch status              show current VPN IP and tunnel status
#   vpn-switch list                list common country names
#   vpn-switch <country>           switch to a server in that country

set -euo pipefail

COMPOSE_FILE="/opt/vpn-browser/docker-compose.yml"
BIN="/config/bin"
COMPOSE_BIN=""   # set by ensure_compose

usage() {
  echo "Usage: vpn-switch <country>   e.g. vpn-switch Germany"
  echo "       vpn-switch status       show current VPN IP and status"
  echo "       vpn-switch list         show accepted country names"
}

# ── Ensure docker-compose is available ────────────────────────────────────────
# Sets COMPOSE_BIN to the absolute path so sudo can find it regardless of PATH.
ensure_compose() {
    # Already in PATH?
    if command -v docker-compose &>/dev/null; then
        COMPOSE_BIN="$(command -v docker-compose)"
        return 0
    fi

    # Already downloaded to persistent bin?
    if [[ -x "$BIN/docker-compose" ]]; then
        COMPOSE_BIN="$BIN/docker-compose"
        return 0
    fi

    echo "  docker-compose not found — downloading (one-time setup)..."
    mkdir -p "$BIN"

    local ver
    ver=$(curl -sfL --max-time 10 \
        https://api.github.com/repos/docker/compose/releases/latest \
        | python3 -c "import json,sys; print(json.load(sys.stdin)['tag_name'])" 2>/dev/null \
        || echo "v2.36.0")

    if curl -sfL --max-time 120 \
        "https://github.com/docker/compose/releases/download/${ver}/docker-compose-linux-x86_64" \
        -o "$BIN/docker-compose" \
        && chmod +x "$BIN/docker-compose"; then
        COMPOSE_BIN="$BIN/docker-compose"
        echo "  docker-compose ${ver} installed to /config/bin."
    else
        echo "  ERROR: Failed to download docker-compose."
        echo "  Check your internet connection and try again."
        exit 1
    fi
}

cmd="${1:-}"

case "$cmd" in

  status)
    # Use gluetun's local HTTP API — instant, no external dependency.
    # Port 8000 is accessible from within the shared network namespace.
    GLUETUN="http://localhost:8000"
    STATE=$(curl -sf --max-time 3 "$GLUETUN/v1/vpn/status" 2>/dev/null \
        | python3 -c "import sys,json; print(json.load(sys.stdin).get('status','unknown'))" 2>/dev/null \
        || echo "unreachable")
    VPN_IP=$(curl -sf --max-time 3 "$GLUETUN/v1/publicip/ip" 2>/dev/null \
        | python3 -c "import sys,json; print(json.load(sys.stdin).get('public_ip','unknown'))" 2>/dev/null \
        || echo "unknown")
    echo "  State    : $STATE"
    echo "  VPN IP   : $VPN_IP"
    ;;

  list)
    echo "  Accepted country names (gluetun / ProtonVPN):"
    echo ""
    echo "    United States    United Kingdom    Germany"
    echo "    Netherlands      Switzerland       Sweden"
    echo "    Norway           Canada            France"
    echo "    Japan            Singapore         Australia"
    echo ""
    echo "  Use the full name in quotes if it contains a space:"
    echo "    vpn-switch \"United Kingdom\""
    ;;

  "")
    usage
    exit 1
    ;;

  *)
    COUNTRY="$*"
    echo ""
    echo "  Switching VPN to: $COUNTRY"
    echo ""
    echo "  WARNING: Your desktop session will disconnect for ~15 seconds"
    echo "           while gluetun restarts. Refresh the browser tab to reconnect."
    echo ""
    read -r -p "  Continue? [y/N] " REPLY
    echo ""
    [[ "${REPLY,,}" == "y" ]] || { echo "  Cancelled."; exit 0; }

    # Resolve docker-compose absolute path (sudo resets PATH)
    ensure_compose

    # Verify Docker socket is accessible
    if ! sudo curl -sf --unix-socket /var/run/docker.sock http://localhost/_ping &>/dev/null; then
      echo "  ERROR: Cannot reach Docker daemon."
      echo "  Check that /var/run/docker.sock is mounted and accessible."
      exit 1
    fi

    echo "  Switching — your session will disconnect now."
    echo "  Refresh the browser in ~30 seconds to reconnect."

    # Remove both containers via Docker API so docker-compose can bring them back
    # in the correct dependency order (VPN healthy → then desktop starts).
    # --force-recreate won't work here because compose project labels may not match;
    # direct API removal bypasses that check entirely.
    #
    # We remove the desktop first so it doesn't hang with a dead network namespace,
    # then remove the VPN container.
    sudo curl -sf --unix-socket /var/run/docker.sock \
        -X DELETE "http://localhost/containers/jumpbox-desktop?force=true" >/dev/null || true
    sudo curl -sf --unix-socket /var/run/docker.sock \
        -X DELETE "http://localhost/containers/jumpbox-vpn?force=true" >/dev/null || true

    # Bring both back up. docker-compose respects depends_on: it starts VPN first,
    # waits for it to be healthy, then starts the desktop.
    # nohup + background ensures this survives the current shell session dying.
    nohup sudo env "VPN_COUNTRY=$COUNTRY" "$COMPOSE_BIN" \
        --project-directory /opt/vpn-browser \
        -f "$COMPOSE_FILE" \
        up -d >/tmp/vpn-switch.log 2>&1 &

    sleep 1
    echo "  Done."
    ;;

esac
