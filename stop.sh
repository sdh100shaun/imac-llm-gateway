#!/usr/bin/env bash
# stop.sh — Stop Ollama and the LiteLLM Docker gateway
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cd "$SCRIPT_DIR"
docker compose down

echo "Gateway stopped."
echo "Model data is preserved in the 'ollama_data' Docker volume."
echo "To remove model data: docker volume rm llm-gateway_ollama_data"
