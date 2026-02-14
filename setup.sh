#!/usr/bin/env bash
set -euo pipefail

# Vision UI MCP Server — One-command setup
#
# Supports: macOS (Apple Silicon + Intel), Linux (x64 + ARM), Windows (WSL2 + Git Bash)
#
# Usage (interactive — recommended):
#   bash <(curl -fsSL https://raw.githubusercontent.com/montycloud/mc-vision-ui-mcp-setup/main/setup.sh)
#
# Usage (piped — prompts for input):
#   curl -fsSL https://raw.githubusercontent.com/montycloud/mc-vision-ui-mcp-setup/main/setup.sh | bash
#
#   Or if curl is not available:
#   wget -qO- https://raw.githubusercontent.com/montycloud/mc-vision-ui-mcp-setup/main/setup.sh | bash

REPO="https://github.com/montycloud/mc-vision-ui-mcp-setup.git"
INSTALL_DIR="${HOME}/vision-ui-mcp"
MIN_DOCKER_VERSION="20.10"
MIN_COMPOSE_VERSION="2.0"
MIN_DISK_GB=10
MIN_RAM_GB=4

# ──────────────────────────────────────────────
# Colors (disabled if not a terminal)
# ──────────────────────────────────────────────

if [ -t 1 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    BOLD='\033[1m'
    NC='\033[0m'
else
    RED='' GREEN='' YELLOW='' BLUE='' BOLD='' NC=''
fi

info()  { echo -e "${BLUE}[INFO]${NC}  $1"; }
ok()    { echo -e "${GREEN}  [OK]${NC}  $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $1"; }
fail()  { echo -e "${RED}[FAIL]${NC}  $1"; }
die()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# ──────────────────────────────────────────────
# Detect platform
# ──────────────────────────────────────────────

detect_platform() {
    OS="unknown"
    ARCH="unknown"
    CHIP="unknown"

    case "$(uname -s 2>/dev/null || echo unknown)" in
        Darwin)  OS="macos" ;;
        Linux)
            if grep -qi microsoft /proc/version 2>/dev/null; then
                OS="wsl"
            else
                OS="linux"
            fi
            ;;
        MINGW*|MSYS*|CYGWIN*)
            OS="windows-gitbash"
            ;;
        *)
            OS="unknown"
            ;;
    esac

    case "$(uname -m 2>/dev/null || echo unknown)" in
        x86_64|amd64)    ARCH="x64";   CHIP="Intel/AMD x64" ;;
        arm64|aarch64)   ARCH="arm64"; CHIP="ARM64 (Apple Silicon / Graviton)" ;;
        armv7l|armhf)    ARCH="armv7"; CHIP="ARM 32-bit" ;;
        *)               ARCH="unknown"; CHIP="Unknown" ;;
    esac
}

# ──────────────────────────────────────────────
# Version comparison helper (works on macOS BSD + GNU)
# ──────────────────────────────────────────────

version_gte() {
    # Returns 0 if $1 >= $2
    # Uses numeric comparison — works on both BSD and GNU sort
    local v1="$1" v2="$2"
    local IFS='.'
    read -ra parts1 <<< "$v1"
    read -ra parts2 <<< "$v2"

    local max=${#parts1[@]}
    [ ${#parts2[@]} -gt "$max" ] && max=${#parts2[@]}

    for ((i = 0; i < max; i++)); do
        local a=${parts1[$i]:-0}
        local b=${parts2[$i]:-0}
        # Strip non-numeric suffixes (e.g., "27.5.0-rc1" → "0")
        a=${a%%[!0-9]*}
        b=${b%%[!0-9]*}
        a=${a:-0}
        b=${b:-0}
        if [ "$a" -gt "$b" ] 2>/dev/null; then return 0; fi
        if [ "$a" -lt "$b" ] 2>/dev/null; then return 1; fi
    done
    return 0  # equal
}

# ──────────────────────────────────────────────
# Read user input (works even when script is piped)
# ──────────────────────────────────────────────

prompt_user() {
    local prompt_text="$1"
    local var_name="$2"

    # When piped (curl | bash), stdin is the script itself.
    # Read from /dev/tty instead to get keyboard input.
    if [ -t 0 ]; then
        read -rp "$prompt_text" "$var_name"
    elif [ -e /dev/tty ]; then
        read -rp "$prompt_text" "$var_name" < /dev/tty
    else
        echo ""
        fail "Cannot read input — no terminal available."
        echo ""
        echo "  Run this script directly instead of piping:"
        echo "    bash <(curl -fsSL https://raw.githubusercontent.com/montycloud/mc-vision-ui-mcp-setup/main/setup.sh)"
        echo ""
        echo "  Or clone and run manually:"
        echo "    git clone $REPO ~/vision-ui-mcp && cd ~/vision-ui-mcp"
        echo "    cp .env.example .env && nano .env"
        echo "    docker compose up -d"
        echo ""
        exit 1
    fi
}

# ──────────────────────────────────────────────
# Pre-flight: Check system requirements
# ──────────────────────────────────────────────

preflight_checks() {
    local errors=0

    echo ""
    echo -e "${BOLD}Checking system requirements...${NC}"
    echo ""

    # -- Platform info --
    info "Platform: ${OS} / ${CHIP}"

    if [ "$OS" = "unknown" ]; then
        fail "Unsupported operating system. This script supports macOS, Linux, and Windows (WSL2 / Git Bash)."
        errors=$((errors + 1))
    fi

    if [ "$ARCH" = "armv7" ]; then
        fail "32-bit ARM is not supported. Docker images require 64-bit (x64 or arm64)."
        errors=$((errors + 1))
    fi

    # -- Git --
    if command -v git >/dev/null 2>&1; then
        ok "git found: $(git --version | head -1)"
    else
        fail "git is not installed."
        echo ""
        case "$OS" in
            macos)
                echo "    Install git:"
                echo "      xcode-select --install"
                echo "    Or install Homebrew first, then: brew install git"
                echo "      /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
                ;;
            linux|wsl)
                echo "    Install git:"
                echo "      sudo apt update && sudo apt install -y git      # Debian/Ubuntu"
                echo "      sudo yum install -y git                         # CentOS/RHEL"
                echo "      sudo dnf install -y git                         # Fedora"
                ;;
            windows-gitbash)
                echo "    Install Git for Windows: https://git-scm.com/download/win"
                ;;
        esac
        echo ""
        errors=$((errors + 1))
    fi

    # -- Docker --
    if command -v docker >/dev/null 2>&1; then
        local docker_ver
        docker_ver=$(docker version --format '{{.Client.Version}}' 2>/dev/null || echo "0.0")
        if version_gte "$docker_ver" "$MIN_DOCKER_VERSION"; then
            ok "Docker found: v${docker_ver}"
        else
            fail "Docker version ${docker_ver} is too old. Need >= ${MIN_DOCKER_VERSION}."
            errors=$((errors + 1))
        fi
    else
        fail "Docker is not installed."
        echo ""
        case "$OS" in
            macos)
                echo "    Install Docker Desktop for Mac:"
                echo "      https://docs.docker.com/desktop/install/mac-install/"
                echo ""
                echo "    Or via Homebrew:"
                echo "      brew install --cask docker"
                echo ""
                echo "    After installing, open Docker Desktop from Applications and wait for it to start."
                ;;
            linux)
                echo "    Install Docker Engine:"
                echo "      curl -fsSL https://get.docker.com | sh"
                echo "      sudo usermod -aG docker \$USER"
                echo "      newgrp docker"
                echo ""
                echo "    Or install Docker Desktop for Linux:"
                echo "      https://docs.docker.com/desktop/install/linux/"
                ;;
            wsl)
                echo "    Install Docker Desktop for Windows (it integrates with WSL2 automatically):"
                echo "      https://docs.docker.com/desktop/install/windows-install/"
                echo ""
                echo "    After installing, open Docker Desktop and enable WSL2 integration:"
                echo "      Settings → Resources → WSL Integration → Enable for your distro"
                ;;
            windows-gitbash)
                echo "    Install Docker Desktop for Windows:"
                echo "      https://docs.docker.com/desktop/install/windows-install/"
                echo ""
                echo "    After installing, open Docker Desktop and wait for it to start."
                echo "    Then re-run this script from Git Bash."
                ;;
        esac
        echo ""
        errors=$((errors + 1))
    fi

    # -- Docker running --
    if command -v docker >/dev/null 2>&1; then
        if docker info >/dev/null 2>&1; then
            ok "Docker daemon is running"
        else
            fail "Docker is installed but not running."
            echo ""
            case "$OS" in
                macos)
                    echo "    Open Docker Desktop from your Applications folder and wait for it to start."
                    echo "    You'll see a whale icon in your menu bar when it's ready."
                    ;;
                linux)
                    echo "    Start Docker:"
                    echo "      sudo systemctl start docker"
                    echo ""
                    echo "    If you get 'permission denied', add yourself to the docker group:"
                    echo "      sudo usermod -aG docker \$USER && newgrp docker"
                    ;;
                wsl)
                    echo "    Open Docker Desktop on Windows and wait for it to start."
                    echo "    Make sure WSL2 integration is enabled:"
                    echo "      Docker Desktop → Settings → Resources → WSL Integration"
                    ;;
                windows-gitbash)
                    echo "    Open Docker Desktop and wait for it to start."
                    echo "    You'll see a whale icon in your system tray when it's ready."
                    ;;
            esac
            echo ""
            errors=$((errors + 1))
        fi
    fi

    # -- Docker Compose --
    if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
        if docker compose version >/dev/null 2>&1; then
            local compose_ver
            compose_ver=$(docker compose version --short 2>/dev/null | sed 's/^v//')
            if version_gte "$compose_ver" "$MIN_COMPOSE_VERSION"; then
                ok "Docker Compose found: v${compose_ver}"
            else
                fail "Docker Compose version ${compose_ver} is too old. Need >= ${MIN_COMPOSE_VERSION}."
                errors=$((errors + 1))
            fi
        elif command -v docker-compose >/dev/null 2>&1; then
            fail "Found legacy 'docker-compose' (v1). Need Docker Compose v2+."
            echo ""
            echo "    Update Docker Desktop to the latest version — Compose v2 is included."
            echo "    Or install the plugin: https://docs.docker.com/compose/install/"
            echo ""
            errors=$((errors + 1))
        else
            fail "Docker Compose not found."
            echo ""
            echo "    Update Docker Desktop to the latest version — Compose v2 is included."
            echo ""
            errors=$((errors + 1))
        fi
    fi

    # -- Disk space --
    local available_gb=0
    if command -v df >/dev/null 2>&1; then
        if [ "$OS" = "macos" ]; then
            # macOS BSD df: use -g for 1GB blocks
            available_gb=$(df -g "$HOME" 2>/dev/null | awk 'NR==2 {print $4}' || echo "0")
        else
            # Linux GNU df: use -BG for GB units
            available_gb=$(df -BG "$HOME" 2>/dev/null | awk 'NR==2 {gsub(/G/,"",$4); print $4}' || echo "0")
        fi
        if [ "$available_gb" -ge "$MIN_DISK_GB" ] 2>/dev/null; then
            ok "Disk space: ${available_gb}GB available (need ${MIN_DISK_GB}GB)"
        elif [ "$available_gb" -gt 0 ] 2>/dev/null; then
            warn "Low disk space: ${available_gb}GB available (recommend ${MIN_DISK_GB}GB). Docker images + repos need ~5-8GB."
        fi
    fi

    # -- RAM --
    local total_ram_gb=0
    if [ "$OS" = "macos" ]; then
        total_ram_gb=$(( $(sysctl -n hw.memsize 2>/dev/null || echo 0) / 1073741824 ))
    elif [ -f /proc/meminfo ]; then
        total_ram_gb=$(awk '/MemTotal/ {printf "%d", $2/1048576}' /proc/meminfo 2>/dev/null || echo "0")
    fi
    if [ "$total_ram_gb" -ge "$MIN_RAM_GB" ] 2>/dev/null; then
        ok "RAM: ${total_ram_gb}GB (need ${MIN_RAM_GB}GB)"
    elif [ "$total_ram_gb" -gt 0 ] 2>/dev/null; then
        warn "Low RAM: ${total_ram_gb}GB (recommend ${MIN_RAM_GB}GB). MCP server + PostgreSQL + indexing needs ~3GB."
    fi

    # -- Port 8080 --
    if command -v lsof >/dev/null 2>&1; then
        if lsof -i :8080 >/dev/null 2>&1; then
            warn "Port 8080 is already in use. The MCP server won't start on the default port."
            echo "      Fix: Set MCP_PORT=9090 (or another free port) in .env after setup."
        else
            ok "Port 8080 is available"
        fi
    elif command -v ss >/dev/null 2>&1; then
        if ss -tlnp 2>/dev/null | grep -q ':8080 '; then
            warn "Port 8080 is already in use. Set MCP_PORT=9090 in .env after setup."
        else
            ok "Port 8080 is available"
        fi
    fi

    # -- curl or wget (for future updates) --
    if command -v curl >/dev/null 2>&1; then
        ok "curl found"
    elif command -v wget >/dev/null 2>&1; then
        ok "wget found"
    else
        warn "Neither curl nor wget found. You won't be able to re-run this script via URL."
    fi

    echo ""

    if [ "$errors" -gt 0 ]; then
        echo -e "${RED}${BOLD}$errors issue(s) found. Please fix them and re-run this script.${NC}"
        echo ""
        exit 1
    fi

    echo -e "${GREEN}${BOLD}All checks passed!${NC}"
    echo ""
}

# ──────────────────────────────────────────────
# Check if already installed
# ──────────────────────────────────────────────

check_existing() {
    if [ -d "$INSTALL_DIR" ]; then
        warn "Directory $INSTALL_DIR already exists."
        echo ""
        echo "  What would you like to do?"
        echo ""
        echo "    1. Update     — Pull latest images and restart"
        echo "    2. Reinstall  — Remove everything and start fresh"
        echo "    3. Quit       — Exit without changes"
        echo ""

        local choice=""
        prompt_user "  Choose [1/2/3]: " choice

        case "$choice" in
            1)
                info "Updating existing installation..."
                cd "$INSTALL_DIR"
                docker compose pull 2>&1
                docker compose up -d 2>&1
                ok "Updated! MCP server is restarting."
                echo ""
                exit 0
                ;;
            2)
                info "Removing existing installation..."
                cd "$INSTALL_DIR"
                docker compose down -v 2>/dev/null || true
                cd "$HOME"
                rm -rf "$INSTALL_DIR"
                ok "Removed. Proceeding with fresh install..."
                echo ""
                ;;
            *)
                echo ""
                info "Exiting. No changes made."
                exit 0
                ;;
        esac
    fi
}

# ──────────────────────────────────────────────
# Clone setup repo
# ──────────────────────────────────────────────

download_files() {
    info "Downloading setup files to $INSTALL_DIR..."
    git clone --depth 1 "$REPO" "$INSTALL_DIR" 2>&1 | tail -1
    rm -rf "$INSTALL_DIR/.git"
    ok "Files downloaded"
}

# ──────────────────────────────────────────────
# Escape special characters for sed replacement
# ──────────────────────────────────────────────

sed_escape() {
    # Escape characters that are special in sed replacement strings: \ / & |
    printf '%s' "$1" | sed -e 's/[\\\/&|]/\\&/g'
}

# ──────────────────────────────────────────────
# Configure environment
# ──────────────────────────────────────────────

configure_env() {
    cd "$INSTALL_DIR"
    cp .env.example .env

    echo ""
    echo -e "${BOLD}Configure your environment${NC}"
    echo ""
    echo "  You need two keys. If you don't have them, ask Nitheish."
    echo ""
    echo -e "  ${YELLOW}1. GitHub Personal Access Token${NC}"
    echo "     Needed to clone the Vision UI and MontyCloud repos."
    echo "     Create one at: https://github.com/settings/tokens"
    echo "     Required scopes: repo (read access), read:packages"
    echo ""

    prompt_user "  GitHub token (ghp_...): " GIT_TOKEN
    [ -z "${GIT_TOKEN:-}" ] && die "GitHub token is required. Ask Nitheish if you don't have one."

    echo ""
    echo -e "  ${YELLOW}2. OpenAI API Key${NC}"
    echo "     Needed to generate embeddings for semantic search."
    echo "     Get one at: https://platform.openai.com/api-keys"
    echo ""

    prompt_user "  OpenAI API key (sk-...): " OPENAI_API_KEY
    [ -z "${OPENAI_API_KEY:-}" ] && die "OpenAI API key is required. Ask Nitheish if you don't have one."

    # Escape special characters for safe sed substitution
    local escaped_git_token escaped_api_key
    escaped_git_token=$(sed_escape "$GIT_TOKEN")
    escaped_api_key=$(sed_escape "$OPENAI_API_KEY")

    # Write values to .env (macOS sed requires '' after -i, Linux doesn't)
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "s|ghp_your_github_token|${escaped_git_token}|" .env
        sed -i '' "s|sk-your_openai_api_key|${escaped_api_key}|" .env
    else
        sed -i "s|ghp_your_github_token|${escaped_git_token}|" .env
        sed -i "s|sk-your_openai_api_key|${escaped_api_key}|" .env
    fi

    ok "Environment configured"
}

# ──────────────────────────────────────────────
# Authenticate with GitHub Container Registry
# ──────────────────────────────────────────────

login_ghcr() {
    echo ""
    info "Authenticating with GitHub Container Registry..."
    if echo "$GIT_TOKEN" | docker login ghcr.io -u "token" --password-stdin 2>/dev/null; then
        ok "Logged into ghcr.io"
    else
        warn "ghcr.io login failed. If the images are private, docker pull will fail."
        echo "      To fix manually: echo YOUR_TOKEN | docker login ghcr.io -u YOUR_USERNAME --password-stdin"
    fi
}

# ──────────────────────────────────────────────
# Start the stack
# ──────────────────────────────────────────────

start_stack() {
    echo ""
    info "Pulling Docker images (this may take a few minutes on first run)..."
    echo ""
    docker compose pull 2>&1 || {
        echo ""
        fail "Failed to pull Docker images."
        echo ""
        echo "  Common causes:"
        echo "    - ghcr.io auth failed (re-run: echo YOUR_TOKEN | docker login ghcr.io -u YOUR_USERNAME --password-stdin)"
        echo "    - Network/firewall blocking ghcr.io"
        echo "    - Your GitHub token doesn't have 'read:packages' scope"
        echo ""
        echo "  Your files are saved in $INSTALL_DIR — fix the issue and run:"
        echo "    cd $INSTALL_DIR && docker compose up -d"
        exit 1
    }

    info "Starting services..."
    docker compose up -d 2>&1 || {
        echo ""
        fail "Failed to start services."
        echo ""
        echo "  Check the logs:  cd $INSTALL_DIR && docker compose logs"
        echo ""
        echo "  Common issues:"
        echo "    - Port 8080 in use → Set MCP_PORT=9090 in .env"
        echo "    - Port 5432 in use → Remove postgres 'ports' section from docker-compose.yml"
        echo "    - Not enough memory → Increase Docker memory (Docker Desktop → Settings → Resources)"
        exit 1
    }

    ok "Services started"
}

# ──────────────────────────────────────────────
# Wait for health (with timeout)
# ──────────────────────────────────────────────

wait_for_health() {
    echo ""
    info "Waiting for MCP server to be ready (first startup takes 3-5 minutes)..."
    echo "     This is a one-time wait — indexing repos and generating embeddings."
    echo ""

    local timeout=300  # 5 minutes
    local elapsed=0
    local interval=10

    while [ "$elapsed" -lt "$timeout" ]; do
        # Check if mcp-server is healthy
        if docker compose ps 2>/dev/null | grep -q "mcp-server.*healthy"; then
            echo ""
            ok "MCP server is healthy and ready!"
            return 0
        fi

        # Check if mcp-server exited/failed
        if docker compose ps 2>/dev/null | grep -q "mcp-server.*Exit"; then
            echo ""
            fail "MCP server exited unexpectedly."
            echo "     Check logs: cd $INSTALL_DIR && docker compose logs mcp-server"
            return 1
        fi

        printf "\r     Waiting... %ds / %ds" "$elapsed" "$timeout"
        sleep "$interval"
        elapsed=$((elapsed + interval))
    done

    echo ""
    warn "Timed out after ${timeout}s. The server may still be indexing."
    echo "     Check status: cd $INSTALL_DIR && docker compose ps"
    echo "     Watch logs:   cd $INSTALL_DIR && docker compose logs -f mcp-server"
}

# ──────────────────────────────────────────────
# Print success message
# ──────────────────────────────────────────────

print_success() {
    local port="${MCP_PORT:-8080}"

    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                                                        ║${NC}"
    echo -e "${GREEN}║   Vision UI MCP Server is running!                     ║${NC}"
    echo -e "${GREEN}║                                                        ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${BOLD}Step 1: Add MCP config to your AI tool${NC}"
    echo ""
    echo -e "  ${YELLOW}For VS Code / GitHub Copilot / Cursor:${NC}"
    echo "  Create .vscode/mcp.json in your project:"
    echo ""
    echo '    {'
    echo '      "servers": {'
    echo '        "vision-ui": {'
    echo '          "type": "http",'
    echo "          \"url\": \"http://localhost:${port}/mcp\""
    echo '        }'
    echo '      }'
    echo '    }'
    echo ""
    echo -e "  ${YELLOW}For Claude Code:${NC}"
    echo "  Add to .claude/settings.json:"
    echo ""
    echo '    {'
    echo '      "mcpServers": {'
    echo '        "vision-ui": {'
    echo '          "type": "http",'
    echo "          \"url\": \"http://localhost:${port}/mcp\""
    echo '        }'
    echo '      }'
    echo '    }'
    echo ""
    echo -e "  ${BOLD}Step 2: Reload your editor${NC}"
    echo "  VS Code: Cmd+Shift+P (Mac) / Ctrl+Shift+P (Windows/Linux) → 'Reload Window'"
    echo ""
    echo -e "  ${BOLD}Step 3: Try it out${NC}"
    echo "  In Copilot Chat or Claude Code, ask: \"Search for Button component\""
    echo ""
    echo "  ─────────────────────────────────────────────"
    echo ""
    echo "  Day-to-day commands:"
    echo "    Start:     cd ~/vision-ui-mcp && docker compose up -d"
    echo "    Stop:      cd ~/vision-ui-mcp && docker compose down"
    echo "    Logs:      cd ~/vision-ui-mcp && docker compose logs -f"
    echo "    Update:    cd ~/vision-ui-mcp && docker compose pull && docker compose up -d"
    echo "    Uninstall: cd ~/vision-ui-mcp && docker compose down -v && rm -rf ~/vision-ui-mcp"
    echo ""
    echo "  Need help? Ask Nitheish or check the README in $INSTALL_DIR"
    echo ""
}

# ──────────────────────────────────────────────
# Main
# ──────────────────────────────────────────────

main() {
    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║                                                        ║${NC}"
    echo -e "${BLUE}║   Vision UI MCP Server — Setup                         ║${NC}"
    echo -e "${BLUE}║                                                        ║${NC}"
    echo -e "${BLUE}║   Connects the Vision UI component library to your     ║${NC}"
    echo -e "${BLUE}║   AI coding tools (GitHub Copilot, Claude, Cursor).    ║${NC}"
    echo -e "${BLUE}║                                                        ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════╝${NC}"

    detect_platform
    preflight_checks
    check_existing
    download_files
    configure_env
    login_ghcr
    start_stack
    wait_for_health
    print_success
}

main "$@"
