#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# ── Pre-flight ──────────────────────────────────────────────────────────────
command -v docker >/dev/null 2>&1 || { echo "ERROR: Docker not found."; exit 1; }
docker compose version >/dev/null 2>&1 || { echo "ERROR: Docker Compose v2 not found."; exit 1; }
docker info >/dev/null 2>&1 || { echo "ERROR: Docker daemon is not running."; exit 1; }

# ── .env setup ─────────────────────────────────────────────────────────────
if [[ ! -f .env ]]; then
  [[ ! -f .env.example ]] && { echo "ERROR: No .env or .env.example found."; exit 1; }
  cp .env.example .env
  echo "Created .env from template — fill in VPN_PRIVATE_KEY and DESKTOP_PASSWORD, then re-run."
  exit 1
fi

set -a; source .env; set +a

# ── Auto-extract private key from wg0.conf if not set ──────────────────────
if [[ "${VPN_PRIVATE_KEY:-}" == "your_private_key_here" || -z "${VPN_PRIVATE_KEY:-}" ]]; then
  WG_CONF="$SCRIPT_DIR/wireguard/wg0.conf"
  if [[ -f "$WG_CONF" ]]; then
    EXTRACTED=$(grep -m1 '^\s*PrivateKey\s*=' "$WG_CONF" | sed 's/.*=\s*//' | tr -d '[:space:]')
    if [[ -n "$EXTRACTED" ]]; then
      sed -i.bak "s|VPN_PRIVATE_KEY=.*|VPN_PRIVATE_KEY=$EXTRACTED|" .env && rm -f .env.bak
      VPN_PRIVATE_KEY="$EXTRACTED"
      echo "Extracted PrivateKey from wireguard/wg0.conf and saved to .env."
    fi
  fi
fi

# ── Validate ────────────────────────────────────────────────────────────────
if [[ "${VPN_PRIVATE_KEY:-}" == "your_private_key_here" || -z "${VPN_PRIVATE_KEY:-}" ]]; then
  echo "ERROR: VPN_PRIVATE_KEY is not set in .env"
  exit 1
fi

if [[ "${DESKTOP_PASSWORD:-}" == "changeme_to_something_strong" || -z "${DESKTOP_PASSWORD:-}" ]]; then
  echo "ERROR: DESKTOP_PASSWORD is still the placeholder — edit .env first."
  exit 1
fi

PROVIDER="${VPN_PROVIDER:-protonvpn}"
if [[ "$PROVIDER" != "protonvpn" && "$PROVIDER" != "mullvad" ]]; then
  echo "ERROR: VPN_PROVIDER must be 'protonvpn' or 'mullvad'. Got: $PROVIDER"
  exit 1
fi

if [[ "$PROVIDER" == "mullvad" && -z "${VPN_ADDRESSES:-}" ]]; then
  echo "ERROR: Mullvad requires VPN_ADDRESSES (your internal WireGuard IP, e.g. 10.64.x.x/32)."
  exit 1
fi

DE="${DESKTOP_ENV:-xfce}"
if [[ "$DE" != "xfce" && "$DE" != "mate" && "$DE" != "kde" ]]; then
  echo "ERROR: DESKTOP_ENV must be xfce, mate, or kde. Got: $DE"
  exit 1
fi

# ── Deploy ──────────────────────────────────────────────────────────────────
echo ""
echo "  Provider : $PROVIDER"
echo "  Desktop  : $DE"
echo "  Country  : ${VPN_COUNTRY:-United States}"
echo ""

echo "  Pulling images..."
docker compose pull --quiet

echo "  Starting..."
docker compose up -d --force-recreate --remove-orphans

echo ""
echo "  Waiting for VPN tunnel (~30s)..."
sleep 15

# ── Verify VPN ─────────────────────────────────────────────────────────────
VPN_IP=$(docker exec jumpbox-vpn wget -qO- --timeout=5 https://ipinfo.io/ip 2>/dev/null || echo "unknown")
HOST_IP=$(curl -s --max-time 5 https://ipinfo.io/ip 2>/dev/null || echo "unknown")
TAILSCALE_IP=$(tailscale ip --4 2>/dev/null || echo "")

echo "  ┌─────────────────────────────────────┐"
echo "  │  Host IP  : $HOST_IP"
echo "  │  VPN  IP  : $VPN_IP"
echo "  └─────────────────────────────────────┘"

if [[ "$VPN_IP" != "unknown" && "$VPN_IP" != "$HOST_IP" ]]; then
  echo "  VPN active — traffic is tunneled through $PROVIDER."
else
  echo "  WARNING: VPN may not be connected yet. Check: docker logs jumpbox-vpn"
fi

echo ""
echo "  Desktop URL : https://localhost:4001"
[[ -n "$TAILSCALE_IP" ]] && echo "  Tailscale   : https://$TAILSCALE_IP:4001"
echo "  Password    : ${DESKTOP_PASSWORD}"
echo ""
echo "  To stop: ./stop.sh"
echo "  To wipe saved desktop data: docker compose down -v"
echo ""
