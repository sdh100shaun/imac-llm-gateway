#!/usr/bin/env bash
# start.sh — Start Ollama (if not running) and the LiteLLM Docker gateway
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Start Ollama natively if not already running (uses Apple Metal GPU)
if ! pgrep -x ollama &>/dev/null; then
  echo "Starting Ollama..."
  brew services start ollama 2>/dev/null || (ollama serve &>/dev/null &)
  sleep 3
fi

# Start LiteLLM via Docker Compose
cd "$SCRIPT_DIR"
docker compose up -d

echo "Gateway ready at http://localhost:4000"
echo "View logs: docker compose logs -f"
