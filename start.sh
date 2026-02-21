#!/usr/bin/env bash
# start.sh — Start Ollama and LiteLLM via Docker Compose
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cd "$SCRIPT_DIR"
docker compose up -d

echo "Gateway ready at http://localhost:4000"
echo "Ollama ready at http://localhost:11434"
echo "View logs: docker compose logs -f"
