#!/usr/bin/env bash
set -euo pipefail

# Vision UI MCP Server — One-command setup
# Usage: curl -fsSL https://raw.githubusercontent.com/montycloud/mc-vision-ui-mcp-setup/main/setup.sh | bash

REPO="https://github.com/montycloud/mc-vision-ui-mcp-setup.git"
INSTALL_DIR="${HOME}/vision-ui-mcp"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()  { echo -e "${BLUE}[INFO]${NC}  $1"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $1"; }
err()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

echo ""
echo -e "${BLUE}╔══════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Vision UI MCP Server — Setup               ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════╝${NC}"
echo ""

# --- Pre-flight checks ---

command -v docker >/dev/null 2>&1 || err "Docker not found. Install Docker Desktop first."
docker info >/dev/null 2>&1 || err "Docker is not running. Start Docker Desktop first."
command -v git >/dev/null 2>&1 || err "git not found."

ok "Docker is running"

# --- Check if already installed ---

if [ -d "$INSTALL_DIR" ]; then
    warn "Directory $INSTALL_DIR already exists."
    echo ""
    echo "  To update:  cd $INSTALL_DIR && git pull && docker compose pull && docker compose up -d"
    echo "  To reinstall: rm -rf $INSTALL_DIR && re-run this script"
    echo ""
    exit 0
fi

# --- Clone setup repo ---

info "Cloning setup files to $INSTALL_DIR..."
git clone --depth 1 "$REPO" "$INSTALL_DIR"
rm -rf "$INSTALL_DIR/.git"
ok "Files downloaded"

# --- Prompt for required values ---

cd "$INSTALL_DIR"
cp .env.example .env

echo ""
echo -e "${YELLOW}Configure your environment:${NC}"
echo ""

read -rp "  GitHub token (ghp_...): " GIT_TOKEN
[ -z "$GIT_TOKEN" ] && err "GitHub token is required"

read -rp "  OpenAI API key (sk-...): " OPENAI_API_KEY
[ -z "$OPENAI_API_KEY" ] && err "OpenAI API key is required"

# Write values to .env
if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' "s|ghp_your_github_token|${GIT_TOKEN}|" .env
    sed -i '' "s|sk-your_openai_api_key|${OPENAI_API_KEY}|" .env
else
    sed -i "s|ghp_your_github_token|${GIT_TOKEN}|" .env
    sed -i "s|sk-your_openai_api_key|${OPENAI_API_KEY}|" .env
fi

ok "Environment configured"

# --- Login to ghcr.io ---

echo ""
info "Authenticating with GitHub Container Registry..."
echo "$GIT_TOKEN" | docker login ghcr.io -u "token" --password-stdin 2>/dev/null && ok "Logged into ghcr.io" || warn "ghcr.io login failed — images may not pull if repo is private"

# --- Start the stack ---

echo ""
info "Starting Vision UI MCP Server..."
docker compose up -d

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   Setup complete!                             ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════╝${NC}"
echo ""
echo "  The server is starting up (first run takes 3-5 minutes)."
echo ""
echo "  Watch progress:   cd $INSTALL_DIR && docker compose logs -f"
echo "  Check status:     cd $INSTALL_DIR && docker compose ps"
echo ""
echo -e "  ${YELLOW}Add this to your AI tool's MCP config:${NC}"
echo ""
echo '  {'
echo '    "servers": {'
echo '      "vision-ui": {'
echo '        "type": "http",'
echo '        "url": "http://localhost:8080/mcp"'
echo '      }'
echo '    }'
echo '  }'
echo ""
echo "  Day-to-day commands:"
echo "    Start:   cd $INSTALL_DIR && docker compose up -d"
echo "    Stop:    cd $INSTALL_DIR && docker compose down"
echo "    Update:  cd $INSTALL_DIR && docker compose pull && docker compose up -d"
echo "    Logs:    cd $INSTALL_DIR && docker compose logs -f"
echo ""
