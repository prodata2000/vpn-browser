#!/usr/bin/env bash
set -euo pipefail

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

docker compose down

echo "Stopped. Run ./deploy.sh to start again."
echo "To also delete saved desktop data: docker compose down -v"
