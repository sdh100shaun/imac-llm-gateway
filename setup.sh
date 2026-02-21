#!/usr/bin/env bash
# setup.sh — One-shot setup for LiteLLM gateway on iMac
# Installs Ollama (native), pulls qwen2.5-coder:14b, and starts LiteLLM via Docker Compose.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
QWEN_MODEL="qwen2.5-coder:14b"
LITELLM_PORT=4000

###############################################################################
# Helpers
###############################################################################
info()    { echo "[INFO]  $*"; }
success() { echo "[OK]    $*"; }
warn()    { echo "[WARN]  $*"; }
error()   { echo "[ERROR] $*" >&2; exit 1; }

require_cmd() {
  command -v "$1" &>/dev/null || error "'$1' is required but not found. $2"
}

###############################################################################
# 1. Preflight checks
###############################################################################
info "Checking prerequisites..."

[[ "$(uname)" == "Darwin" ]] || error "This script is designed for macOS."

require_cmd brew  "Install Homebrew from https://brew.sh first."
require_cmd docker "Install Docker Desktop from https://www.docker.com/products/docker-desktop/ first."

docker info &>/dev/null || error "Docker Desktop is not running. Please start it and re-run this script."
success "Prerequisites OK."

###############################################################################
# 2. Install Ollama
###############################################################################
if command -v ollama &>/dev/null; then
  success "Ollama already installed ($(ollama --version 2>/dev/null | head -1))."
else
  info "Installing Ollama via Homebrew..."
  brew install ollama
  success "Ollama installed."
fi

###############################################################################
# 3. Start Ollama
###############################################################################
if pgrep -x ollama &>/dev/null; then
  success "Ollama is already running."
else
  info "Starting Ollama..."
  brew services start ollama 2>/dev/null || (ollama serve &>/dev/null & sleep 3)
  # Give it a moment to bind to port 11434
  sleep 3
  if ! curl -sf http://localhost:11434 &>/dev/null; then
    warn "Ollama may not have started yet — continuing anyway."
  else
    success "Ollama is running at http://localhost:11434."
  fi
fi

###############################################################################
# 4. Pull Qwen coding model (~8 GB, may take a while)
###############################################################################
if ollama list 2>/dev/null | grep -q "qwen2.5-coder:14b"; then
  success "Model '$QWEN_MODEL' already present."
else
  info "Pulling '$QWEN_MODEL' — this may take several minutes (~8 GB)..."
  ollama pull "$QWEN_MODEL"
  success "Model '$QWEN_MODEL' downloaded."
fi

###############################################################################
# 5. Set up .env
###############################################################################
ENV_FILE="$SCRIPT_DIR/.env"
ENV_EXAMPLE="$SCRIPT_DIR/.env.example"

if [[ -f "$ENV_FILE" ]]; then
  info ".env already exists — skipping creation."
else
  info "Creating .env from .env.example..."
  cp "$ENV_EXAMPLE" "$ENV_FILE"
fi

# Prompt for ANTHROPIC_API_KEY if placeholder is still present
if grep -q "^ANTHROPIC_API_KEY=sk-ant-\.\.\." "$ENV_FILE" || grep -q "^ANTHROPIC_API_KEY=$" "$ENV_FILE"; then
  read -rp "Enter your Anthropic API key (or press Enter to skip): " ANTHROPIC_KEY
  if [[ -n "$ANTHROPIC_KEY" ]]; then
    # macOS-compatible sed (in-place with empty backup extension)
    sed -i '' "s|^ANTHROPIC_API_KEY=.*|ANTHROPIC_API_KEY=${ANTHROPIC_KEY}|" "$ENV_FILE"
    success "ANTHROPIC_API_KEY set."
  else
    warn "ANTHROPIC_API_KEY not set — Claude fallback will not work."
  fi
else
  success "ANTHROPIC_API_KEY already configured."
fi

# Auto-generate LITELLM_MASTER_KEY if still using the default placeholder
if grep -q "^LITELLM_MASTER_KEY=sk-dvsa-local-master-key" "$ENV_FILE"; then
  GENERATED_KEY="sk-$(openssl rand -hex 16)"
  sed -i '' "s|^LITELLM_MASTER_KEY=.*|LITELLM_MASTER_KEY=${GENERATED_KEY}|" "$ENV_FILE"
  info "Generated LITELLM_MASTER_KEY: $GENERATED_KEY"
  success "LITELLM_MASTER_KEY updated in .env."
fi

###############################################################################
# 6. Write config.yaml (if not already present)
###############################################################################
CONFIG_FILE="$SCRIPT_DIR/config.yaml"
if [[ -f "$CONFIG_FILE" ]]; then
  success "config.yaml already present."
else
  info "Writing config.yaml..."
  cat > "$CONFIG_FILE" <<'YAML'
model_list:
  - model_name: "qwen-coder"
    litellm_params:
      model: "ollama_chat/qwen2.5-coder:14b"
      api_base: "http://host.docker.internal:11434"
      keep_alive: "10m"

  - model_name: "claude-fallback"
    litellm_params:
      model: "claude-sonnet-4-6"
      api_key: "os.environ/ANTHROPIC_API_KEY"

litellm_settings:
  fallbacks:
    - {"qwen-coder": ["claude-fallback"]}
  num_retries: 2
  request_timeout: 60
  drop_params: true

general_settings:
  master_key: "os.environ/LITELLM_MASTER_KEY"
  port: 4000
  host: "0.0.0.0"
YAML
  success "config.yaml written."
fi

###############################################################################
# 7. Write docker-compose.yml (if not already present)
###############################################################################
COMPOSE_FILE="$SCRIPT_DIR/docker-compose.yml"
if [[ -f "$COMPOSE_FILE" ]]; then
  success "docker-compose.yml already present."
else
  info "Writing docker-compose.yml..."
  cat > "$COMPOSE_FILE" <<'YAML'
services:
  litellm:
    image: ghcr.io/berriai/litellm:main-latest
    container_name: litellm-gateway
    ports:
      - "4000:4000"
    volumes:
      - ./config.yaml:/app/config.yaml:ro
    env_file:
      - .env
    command: ["--config", "/app/config.yaml", "--port", "4000", "--detailed_debug"]
    extra_hosts:
      - "host.docker.internal:host-gateway"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:4000/health"]
      interval: 15s
      timeout: 5s
      retries: 5
      start_period: 30s
    restart: unless-stopped
YAML
  success "docker-compose.yml written."
fi

###############################################################################
# 8. Start LiteLLM via Docker Compose
###############################################################################
info "Starting LiteLLM container..."
cd "$SCRIPT_DIR"
docker compose pull --quiet
docker compose up -d
success "LiteLLM container started."

###############################################################################
# 9. Health check — wait for LiteLLM to be ready
###############################################################################
info "Waiting for LiteLLM to be healthy (up to 60s)..."
for i in $(seq 1 20); do
  if curl -sf "http://localhost:${LITELLM_PORT}/health" &>/dev/null; then
    success "LiteLLM is healthy!"
    break
  fi
  sleep 3
  if [[ "$i" -eq 20 ]]; then
    warn "LiteLLM did not respond in time. Check logs with: docker compose logs -f"
  fi
done

###############################################################################
# 10. Print summary
###############################################################################
MASTER_KEY=$(grep "^LITELLM_MASTER_KEY=" "$ENV_FILE" | cut -d= -f2-)

echo ""
echo "======================================================"
echo "  LLM Gateway Setup Complete"
echo "======================================================"
echo "  Gateway URL  : http://localhost:${LITELLM_PORT}"
echo "  Primary model: qwen2.5-coder:14b (via Ollama)"
echo "  Fallback     : claude-sonnet-4-6 (Anthropic)"
echo "  Master key   : ${MASTER_KEY}"
echo ""
echo "  Test commands:"
echo ""
echo "  # List models"
echo "  curl http://localhost:${LITELLM_PORT}/models \\"
echo "    -H \"Authorization: Bearer ${MASTER_KEY}\""
echo ""
echo "  # Chat completion (Qwen primary)"
echo "  curl -X POST http://localhost:${LITELLM_PORT}/chat/completions \\"
echo "    -H \"Content-Type: application/json\" \\"
echo "    -H \"Authorization: Bearer ${MASTER_KEY}\" \\"
echo "    -d '{\"model\": \"qwen-coder\", \"messages\": [{\"role\": \"user\", \"content\": \"Write a Python hello world\"}]}'"
echo ""
echo "  # Manage:"
echo "  ./start.sh   — start gateway"
echo "  ./stop.sh    — stop gateway"
echo "  docker compose logs -f — view logs"
echo "======================================================"
