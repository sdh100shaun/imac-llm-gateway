#!/usr/bin/env bash
# stop.sh — Stop the LiteLLM Docker gateway (Ollama keeps running)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cd "$SCRIPT_DIR"
docker compose down

echo "LiteLLM gateway stopped."
echo "Ollama is still running. To stop it: brew services stop ollama"
