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

# Total steps in the setup flow (for progress tracking)
TOTAL_STEPS=7
CURRENT_STEP=0

# ──────────────────────────────────────────────
# Colors & styling (disabled if not a terminal)
# ──────────────────────────────────────────────

if [ -t 1 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    MAGENTA='\033[0;35m'
    BOLD='\033[1m'
    DIM='\033[2m'
    NC='\033[0m'
    # Cursor control
    HIDE_CURSOR='\033[?25l'
    SHOW_CURSOR='\033[?25h'
    CLEAR_LINE='\033[2K'
else
    RED='' GREEN='' YELLOW='' BLUE='' CYAN='' MAGENTA='' BOLD='' DIM='' NC=''
    HIDE_CURSOR='' SHOW_CURSOR='' CLEAR_LINE=''
fi

# Ensure cursor is restored on exit
trap 'printf "${SHOW_CURSOR}"' EXIT

info()  { echo -e "  ${BLUE}ℹ${NC}  $1"; }
ok()    { echo -e "  ${GREEN}✓${NC}  $1"; }
warn()  { echo -e "  ${YELLOW}⚠${NC}  $1"; }
fail()  { echo -e "  ${RED}✗${NC}  $1"; }
die()   { echo -e "\n  ${RED}✗ ERROR:${NC} $1"; printf "${SHOW_CURSOR}"; exit 1; }

# ──────────────────────────────────────────────
# Animation helpers
# ──────────────────────────────────────────────

# Braille spinner — smooth 8-frame animation
SPINNER_FRAMES=('⣾' '⣽' '⣻' '⢿' '⡿' '⣟' '⣯' '⣷')
SPINNER_PID=""

spinner_start() {
    local msg="$1"
    printf "${HIDE_CURSOR}"
    (
        local i=0
        while true; do
            printf "\r  ${CYAN}${SPINNER_FRAMES[$((i % 8))]}${NC}  ${msg}" >&2
            i=$((i + 1))
            sleep 0.1
        done
    ) &
    SPINNER_PID=$!
    disown "$SPINNER_PID" 2>/dev/null || true
}

spinner_stop() {
    if [ -n "${SPINNER_PID:-}" ] && kill -0 "$SPINNER_PID" 2>/dev/null; then
        kill "$SPINNER_PID" 2>/dev/null || true
        wait "$SPINNER_PID" 2>/dev/null || true
    fi
    SPINNER_PID=""
    printf "\r${CLEAR_LINE}" >&2
    printf "${SHOW_CURSOR}"
}

# Run a command with a spinner, show ok/fail when done
run_with_spinner() {
    local msg="$1"
    shift
    spinner_start "$msg"
    local output
    if output=$("$@" 2>&1); then
        spinner_stop
        ok "$msg"
        return 0
    else
        spinner_stop
        fail "$msg"
        if [ -n "$output" ]; then
            echo -e "     ${DIM}${output}${NC}" | head -5
        fi
        return 1
    fi
}

# Step header with progress indicator
step_header() {
    CURRENT_STEP=$((CURRENT_STEP + 1))
    local title="$1"
    local bar=""
    local filled=$((CURRENT_STEP * 30 / TOTAL_STEPS))
    local empty=$((30 - filled))

    # Build progress bar
    for ((i = 0; i < filled; i++)); do bar+="█"; done
    for ((i = 0; i < empty; i++)); do bar+="░"; done

    echo ""
    echo -e "  ${DIM}Step ${CURRENT_STEP}/${TOTAL_STEPS}${NC}  ${BOLD}${title}${NC}"
    echo -e "  ${GREEN}${bar}${NC}  ${DIM}${CURRENT_STEP}/${TOTAL_STEPS}${NC}"
    echo ""
}

# Typewriter effect for important messages
typewrite() {
    local text="$1"
    local delay="${2:-0.02}"
    for ((i = 0; i < ${#text}; i++)); do
        printf '%s' "${text:$i:1}"
        sleep "$delay"
    done
    echo ""
}

# Animated countdown
countdown() {
    local secs=$1
    local msg="${2:-Starting in}"
    for ((i = secs; i > 0; i--)); do
        printf "\r  ${DIM}${msg} ${i}s...${NC}"
        sleep 1
    done
    printf "\r${CLEAR_LINE}"
}

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
    local v1="$1" v2="$2"
    local IFS='.'
    read -ra parts1 <<< "$v1"
    read -ra parts2 <<< "$v2"

    local max=${#parts1[@]}
    [ ${#parts2[@]} -gt "$max" ] && max=${#parts2[@]}

    for ((i = 0; i < max; i++)); do
        local a=${parts1[$i]:-0}
        local b=${parts2[$i]:-0}
        a=${a%%[!0-9]*}
        b=${b%%[!0-9]*}
        a=${a:-0}
        b=${b:-0}
        if [ "$a" -gt "$b" ] 2>/dev/null; then return 0; fi
        if [ "$a" -lt "$b" ] 2>/dev/null; then return 1; fi
    done
    return 0
}

# ──────────────────────────────────────────────
# Read user input (works even when script is piped)
# ──────────────────────────────────────────────

prompt_user() {
    local prompt_text="$1"
    local var_name="$2"

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

    step_header "System Requirements"

    info "Platform: ${OS} / ${CHIP}"
    echo ""

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
        ok "git $(git --version | sed 's/git version //')"
    else
        fail "git is not installed."
        echo ""
        case "$OS" in
            macos)
                echo "    Install:  xcode-select --install"
                echo "    Or:       brew install git"
                ;;
            linux|wsl)
                echo "    Install:  sudo apt install -y git"
                ;;
            windows-gitbash)
                echo "    Install:  https://git-scm.com/download/win"
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
            ok "Docker v${docker_ver}"
        else
            fail "Docker ${docker_ver} is too old (need >= ${MIN_DOCKER_VERSION})"
            errors=$((errors + 1))
        fi
    else
        fail "Docker is not installed."
        echo ""
        case "$OS" in
            macos)
                echo "    Install Docker Desktop:"
                echo "      https://docs.docker.com/desktop/install/mac-install/"
                echo "    Or: brew install --cask docker"
                ;;
            linux)
                echo "    Install: curl -fsSL https://get.docker.com | sh"
                echo "    Then:    sudo usermod -aG docker \$USER && newgrp docker"
                ;;
            wsl)
                echo "    Install Docker Desktop for Windows (integrates with WSL2):"
                echo "      https://docs.docker.com/desktop/install/windows-install/"
                ;;
            windows-gitbash)
                echo "    Install Docker Desktop for Windows:"
                echo "      https://docs.docker.com/desktop/install/windows-install/"
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
                    echo "    Open Docker Desktop from Applications and wait for the whale icon."
                    ;;
                linux)
                    echo "    Start: sudo systemctl start docker"
                    echo "    Permission fix: sudo usermod -aG docker \$USER && newgrp docker"
                    ;;
                wsl)
                    echo "    Open Docker Desktop on Windows."
                    echo "    Enable WSL2: Settings → Resources → WSL Integration"
                    ;;
                windows-gitbash)
                    echo "    Open Docker Desktop and wait for it to start."
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
                ok "Docker Compose v${compose_ver}"
            else
                fail "Docker Compose ${compose_ver} is too old (need >= ${MIN_COMPOSE_VERSION})"
                errors=$((errors + 1))
            fi
        elif command -v docker-compose >/dev/null 2>&1; then
            fail "Found legacy docker-compose v1 — need v2+."
            echo "    Update Docker Desktop or install the Compose plugin."
            errors=$((errors + 1))
        else
            fail "Docker Compose not found."
            echo "    Update Docker Desktop — Compose v2 is included."
            errors=$((errors + 1))
        fi
    fi

    # -- Disk space --
    local available_gb=0
    if command -v df >/dev/null 2>&1; then
        if [ "$OS" = "macos" ]; then
            available_gb=$(df -g "$HOME" 2>/dev/null | awk 'NR==2 {print $4}' || echo "0")
        else
            available_gb=$(df -BG "$HOME" 2>/dev/null | awk 'NR==2 {gsub(/G/,"",$4); print $4}' || echo "0")
        fi
        if [ "$available_gb" -ge "$MIN_DISK_GB" ] 2>/dev/null; then
            ok "Disk: ${available_gb}GB free"
        elif [ "$available_gb" -gt 0 ] 2>/dev/null; then
            warn "Low disk: ${available_gb}GB free (recommend ${MIN_DISK_GB}GB)"
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
        ok "RAM: ${total_ram_gb}GB"
    elif [ "$total_ram_gb" -gt 0 ] 2>/dev/null; then
        warn "Low RAM: ${total_ram_gb}GB (recommend ${MIN_RAM_GB}GB)"
    fi

    # -- Port 8080 --
    if command -v lsof >/dev/null 2>&1; then
        if lsof -i :8080 >/dev/null 2>&1; then
            warn "Port 8080 in use — set MCP_PORT=9090 in .env after setup"
        else
            ok "Port 8080 is available"
        fi
    elif command -v ss >/dev/null 2>&1; then
        if ss -tlnp 2>/dev/null | grep -q ':8080 '; then
            warn "Port 8080 in use — set MCP_PORT=9090 in .env after setup"
        else
            ok "Port 8080 is available"
        fi
    fi

    # -- curl or wget --
    if command -v curl >/dev/null 2>&1; then
        ok "curl found"
    elif command -v wget >/dev/null 2>&1; then
        ok "wget found"
    else
        warn "Neither curl nor wget found."
    fi

    echo ""

    if [ "$errors" -gt 0 ]; then
        echo -e "  ${RED}${BOLD}✗ ${errors} issue(s) found. Fix them and re-run this script.${NC}"
        echo ""
        exit 1
    fi

    echo -e "  ${GREEN}${BOLD}✓ All checks passed!${NC}"
    sleep 0.5
}

# ──────────────────────────────────────────────
# Check if already installed
# ──────────────────────────────────────────────

check_existing() {
    if [ -d "$INSTALL_DIR" ]; then
        echo ""
        warn "Directory $INSTALL_DIR already exists."
        echo ""
        echo -e "  ${BOLD}What would you like to do?${NC}"
        echo ""
        echo -e "    ${GREEN}1${NC}  Update     — Pull latest images and restart"
        echo -e "    ${YELLOW}2${NC}  Reinstall  — Remove everything and start fresh"
        echo -e "    ${DIM}3${NC}  Quit       — Exit without changes"
        echo ""

        local choice=""
        prompt_user "  Choose [1/2/3]: " choice

        case "$choice" in
            1)
                info "Updating existing installation..."
                cd "$INSTALL_DIR"
                run_with_spinner "Pulling latest images" docker compose pull || die "Failed to pull Docker images. Check your network and ghcr.io credentials."
                run_with_spinner "Restarting services" docker compose up -d || die "Failed to start services. Run: docker compose logs"
                echo ""
                ok "Updated! MCP server is restarting."
                echo ""
                exit 0
                ;;
            2)
                spinner_start "Removing existing installation..."
                cd "$INSTALL_DIR"
                docker compose down -v 2>/dev/null || true
                cd "$HOME"
                rm -rf "$INSTALL_DIR" || { spinner_stop; die "Failed to remove $INSTALL_DIR. Check permissions."; }
                spinner_stop
                ok "Removed. Starting fresh install..."
                echo ""
                ;;
            3)
                echo ""
                info "Exiting. No changes made."
                exit 0
                ;;
            *)
                echo ""
                fail "Invalid choice '${choice}'. Please enter 1, 2, or 3."
                exit 1
                ;;
        esac
    fi
}

# ──────────────────────────────────────────────
# Clone setup repo
# ──────────────────────────────────────────────

download_files() {
    step_header "Download Setup Files"

    spinner_start "Cloning setup repository..."
    if git clone --depth 1 "$REPO" "$INSTALL_DIR" >/dev/null 2>&1; then
        rm -rf "$INSTALL_DIR/.git"
        spinner_stop
        ok "Setup files downloaded to ${DIM}${INSTALL_DIR}${NC}"
    else
        spinner_stop
        die "Failed to clone repository. Check your network connection and try again.\n  URL: $REPO"
    fi
}

# ──────────────────────────────────────────────
# Escape special characters for sed replacement
# ──────────────────────────────────────────────

sed_escape() {
    printf '%s' "$1" | sed -e 's/[\\\/&|]/\\&/g'
}

# ──────────────────────────────────────────────
# Configure environment
# ──────────────────────────────────────────────

configure_env() {
    cd "$INSTALL_DIR"
    cp .env.example .env

    step_header "Configure Environment"

    echo -e "  ${YELLOW}${BOLD}1. GitHub Personal Access Token${NC}"
    echo -e "  ${DIM}Needed to clone the Vision UI and MontyCloud repos.${NC}"
    echo -e "  ${DIM}Create one at: https://github.com/settings/tokens${NC}"
    echo -e "  ${DIM}Required scopes: repo (read access), read:packages${NC}"
    echo ""

    prompt_user "  ${BOLD}GitHub token (ghp_...):${NC} " GIT_TOKEN
    [ -z "${GIT_TOKEN:-}" ] && die "GitHub token is required. Create one at: https://github.com/settings/tokens (scopes: repo, read:packages)"
    ok "GitHub token set"

    echo ""
    echo -e "  ${YELLOW}${BOLD}2. Embedding Provider${NC}"
    echo -e "  ${DIM}Semantic search requires an embedding provider.${NC}"
    echo ""
    echo -e "    ${GREEN}1${NC}  OpenAI   — needs an API key (https://platform.openai.com/api-keys)"
    echo -e "    ${CYAN}2${NC}  Bedrock  — AWS API key ${DIM}(recommended for MontyCloud team)${NC}"
    echo ""

    prompt_user "  Enter 1 or 2 [1]: " EMBEDDING_CHOICE
    EMBEDDING_CHOICE="${EMBEDDING_CHOICE:-1}"

    local escaped_git_token
    escaped_git_token=$(sed_escape "$GIT_TOKEN")

    if [[ "$EMBEDDING_CHOICE" == "2" ]]; then
        configure_bedrock "$escaped_git_token"
    else
        configure_openai "$escaped_git_token"
    fi
}

# ──────────────────────────────────────────────
# Configure AWS Bedrock (embedding provider)
# ──────────────────────────────────────────────

configure_bedrock() {
    local escaped_git_token="$1"

    echo ""
    echo -e "  ${CYAN}${BOLD}AWS Bedrock Setup${NC}"
    echo ""
    echo -e "  ${DIM}Choose your credential type:${NC}"
    echo ""
    echo -e "    ${GREEN}a${NC}  Long-term API key ${DIM}(recommended — no expiry)${NC}"
    echo -e "       ${DIM}Generate at: AWS Console → Amazon Bedrock → API keys${NC}"
    echo ""
    echo -e "    ${YELLOW}b${NC}  Short-term session ${DIM}(from SSO or STS — expires)${NC}"
    echo -e "       ${DIM}Run: aws configure export-credentials --format env${NC}"
    echo ""

    local cred_choice=""
    prompt_user "  Credential type [a/b]: " cred_choice
    cred_choice="${cred_choice:-a}"

    echo ""
    prompt_user "  AWS region for Bedrock [us-east-1]: " BEDROCK_REGION
    BEDROCK_REGION="${BEDROCK_REGION:-us-east-1}"

    local escaped_region
    escaped_region=$(sed_escape "$BEDROCK_REGION")

    if [[ "$cred_choice" == "b" || "$cred_choice" == "B" ]]; then
        # --- Short-term session credentials ---
        echo ""
        echo -e "  ${DIM}Paste your short-term credentials (from SSO or STS):${NC}"
        echo ""
        prompt_user "  AWS_ACCESS_KEY_ID (ASIA...): " AWS_AK
        [ -z "${AWS_AK:-}" ] && die "AWS_ACCESS_KEY_ID is required."
        prompt_user "  AWS_SECRET_ACCESS_KEY: " AWS_SK
        [ -z "${AWS_SK:-}" ] && die "AWS_SECRET_ACCESS_KEY is required."
        prompt_user "  AWS_SESSION_TOKEN: " AWS_ST
        [ -z "${AWS_ST:-}" ] && die "AWS_SESSION_TOKEN is required for short-term credentials."

        local escaped_ak escaped_sk escaped_st
        escaped_ak=$(sed_escape "$AWS_AK")
        escaped_sk=$(sed_escape "$AWS_SK")
        escaped_st=$(sed_escape "$AWS_ST")

        if [ "$OS" = "macos" ]; then
            sed -i '' "s|GIT_TOKEN=ghp_your_github_token|GIT_TOKEN=${escaped_git_token}|" .env
            sed -i '' "s|EMBEDDING_PROVIDER=openai|EMBEDDING_PROVIDER=bedrock|" .env
            sed -i '' "s|OPENAI_API_KEY=sk-your_openai_api_key|# OPENAI_API_KEY= (not needed for Bedrock)|" .env
            sed -i '' "s|# AWS_ACCESS_KEY_ID=ASIA...|AWS_ACCESS_KEY_ID=${escaped_ak}|" .env
            sed -i '' "s|# AWS_SECRET_ACCESS_KEY=...|AWS_SECRET_ACCESS_KEY=${escaped_sk}|" .env
            sed -i '' "s|# AWS_SESSION_TOKEN=...|AWS_SESSION_TOKEN=${escaped_st}|" .env
            sed -i '' "s|# AWS_DEFAULT_REGION=us-east-1|AWS_DEFAULT_REGION=${escaped_region}|" .env
        else
            sed -i "s|GIT_TOKEN=ghp_your_github_token|GIT_TOKEN=${escaped_git_token}|" .env
            sed -i "s|EMBEDDING_PROVIDER=openai|EMBEDDING_PROVIDER=bedrock|" .env
            sed -i "s|OPENAI_API_KEY=sk-your_openai_api_key|# OPENAI_API_KEY= (not needed for Bedrock)|" .env
            sed -i "s|# AWS_ACCESS_KEY_ID=ASIA...|AWS_ACCESS_KEY_ID=${escaped_ak}|" .env
            sed -i "s|# AWS_SECRET_ACCESS_KEY=...|AWS_SECRET_ACCESS_KEY=${escaped_sk}|" .env
            sed -i "s|# AWS_SESSION_TOKEN=...|AWS_SESSION_TOKEN=${escaped_st}|" .env
            sed -i "s|# AWS_DEFAULT_REGION=us-east-1|AWS_DEFAULT_REGION=${escaped_region}|" .env
        fi

        echo ""
        warn "Short-term credentials expire. When they do, update .env and restart:"
        echo -e "       ${DIM}cd ~/vision-ui-mcp && docker compose restart mcp-server${NC}"
        echo ""
        ok "Configured for AWS Bedrock (session credentials, region: ${BEDROCK_REGION})"
    else
        # --- Long-term API key (default) ---
        echo ""
        echo -e "  ${DIM}To generate a long-term API key:${NC}"
        echo -e "    ${DIM}1. Log into the AWS Console (via myapps.microsoft.com → AWS)${NC}"
        echo -e "    ${DIM}2. Go to Amazon Bedrock → API keys (left sidebar)${NC}"
        echo -e "    ${DIM}3. Click 'Generate long-term API key'${NC}"
        echo -e "    ${DIM}4. Copy the key (starts with ABSK...)${NC}"
        echo ""

        prompt_user "  Bedrock API key (ABSK...): " BEDROCK_API_KEY
        [ -z "${BEDROCK_API_KEY:-}" ] && die "Bedrock API key is required. Generate one at: AWS Console → Amazon Bedrock → API keys."

        local escaped_key
        escaped_key=$(sed_escape "$BEDROCK_API_KEY")

        if [ "$OS" = "macos" ]; then
            sed -i '' "s|GIT_TOKEN=ghp_your_github_token|GIT_TOKEN=${escaped_git_token}|" .env
            sed -i '' "s|EMBEDDING_PROVIDER=openai|EMBEDDING_PROVIDER=bedrock|" .env
            sed -i '' "s|OPENAI_API_KEY=sk-your_openai_api_key|# OPENAI_API_KEY= (not needed for Bedrock)|" .env
            sed -i '' "s|# AWS_BEARER_TOKEN_BEDROCK=ABSK...|AWS_BEARER_TOKEN_BEDROCK=${escaped_key}|" .env
            sed -i '' "s|# AWS_DEFAULT_REGION=us-east-1|AWS_DEFAULT_REGION=${escaped_region}|" .env
        else
            sed -i "s|GIT_TOKEN=ghp_your_github_token|GIT_TOKEN=${escaped_git_token}|" .env
            sed -i "s|EMBEDDING_PROVIDER=openai|EMBEDDING_PROVIDER=bedrock|" .env
            sed -i "s|OPENAI_API_KEY=sk-your_openai_api_key|# OPENAI_API_KEY= (not needed for Bedrock)|" .env
            sed -i "s|# AWS_BEARER_TOKEN_BEDROCK=ABSK...|AWS_BEARER_TOKEN_BEDROCK=${escaped_key}|" .env
            sed -i "s|# AWS_DEFAULT_REGION=us-east-1|AWS_DEFAULT_REGION=${escaped_region}|" .env
        fi

        echo ""
        ok "Configured for AWS Bedrock (long-term API key, region: ${BEDROCK_REGION})"
    fi
}

# ──────────────────────────────────────────────
# Configure OpenAI (embedding provider)
# ──────────────────────────────────────────────

configure_openai() {
    local escaped_git_token="$1"

    echo ""
    echo -e "  ${GREEN}${BOLD}OpenAI API Key${NC}"
    echo -e "  ${DIM}Get one at: https://platform.openai.com/api-keys${NC}"
    echo ""

    prompt_user "  OpenAI API key (sk-...): " OPENAI_API_KEY
    [ -z "${OPENAI_API_KEY:-}" ] && die "OpenAI API key is required. Get one at: https://platform.openai.com/api-keys"

    local escaped_api_key
    escaped_api_key=$(sed_escape "$OPENAI_API_KEY")

    if [ "$OS" = "macos" ]; then
        sed -i '' "s|GIT_TOKEN=ghp_your_github_token|GIT_TOKEN=${escaped_git_token}|" .env
        sed -i '' "s|OPENAI_API_KEY=sk-your_openai_api_key|OPENAI_API_KEY=${escaped_api_key}|" .env
    else
        sed -i "s|GIT_TOKEN=ghp_your_github_token|GIT_TOKEN=${escaped_git_token}|" .env
        sed -i "s|OPENAI_API_KEY=sk-your_openai_api_key|OPENAI_API_KEY=${escaped_api_key}|" .env
    fi

    ok "Configured for OpenAI"
}

# ──────────────────────────────────────────────
# Authenticate with GitHub Container Registry
# ──────────────────────────────────────────────

login_ghcr() {
    step_header "Authenticate Registry"

    spinner_start "Logging into GitHub Container Registry..."
    if echo "$GIT_TOKEN" | docker login ghcr.io -u "token" --password-stdin >/dev/null 2>&1; then
        spinner_stop
        ok "Logged into ghcr.io"
    else
        spinner_stop
        warn "ghcr.io login failed — images may not pull if private."
        echo -e "  ${DIM}Fix: echo YOUR_TOKEN | docker login ghcr.io -u YOUR_USERNAME --password-stdin${NC}"
    fi
}

# ──────────────────────────────────────────────
# Start the stack
# ──────────────────────────────────────────────

start_stack() {
    step_header "Pull & Start Services"

    # Pull images with spinner
    spinner_start "Pulling Docker images (this may take a few minutes on first run)..."
    if docker compose pull >/dev/null 2>&1; then
        spinner_stop
        ok "Docker images pulled"
    else
        spinner_stop
        echo ""
        fail "Failed to pull Docker images."
        echo ""
        echo -e "  ${DIM}Common causes:${NC}"
        echo -e "    ${DIM}- ghcr.io auth failed${NC}"
        echo -e "    ${DIM}- Network/firewall blocking ghcr.io${NC}"
        echo -e "    ${DIM}- GitHub token missing 'read:packages' scope${NC}"
        echo ""
        echo -e "  ${DIM}Your files are saved in $INSTALL_DIR — fix the issue and run:${NC}"
        echo -e "    ${DIM}cd $INSTALL_DIR && docker compose up -d${NC}"
        exit 1
    fi

    # Start services with spinner
    spinner_start "Starting PostgreSQL, Indexer, MCP Server..."
    if docker compose up -d >/dev/null 2>&1; then
        spinner_stop
        ok "Services started"
    else
        spinner_stop
        echo ""
        fail "Failed to start services."
        echo ""
        echo -e "  ${DIM}Check logs: cd $INSTALL_DIR && docker compose logs${NC}"
        echo ""
        echo -e "  ${DIM}Common issues:${NC}"
        echo -e "    ${DIM}- Port 8080 in use → Set MCP_PORT=9090 in .env${NC}"
        echo -e "    ${DIM}- Not enough memory → Increase Docker resources${NC}"
        exit 1
    fi
}

# ──────────────────────────────────────────────
# Wait for health (with animated progress)
# ──────────────────────────────────────────────

wait_for_health() {
    step_header "Indexing & Health Check"

    echo -e "  ${DIM}First startup takes 3-5 minutes — cloning repos, extracting"
    echo -e "  components, and generating embeddings. Hang tight!${NC}"
    echo ""

    local timeout=300  # 5 minutes
    local elapsed=0
    local interval=5
    local phase="indexing"

    printf "${HIDE_CURSOR}"

    while [ "$elapsed" -lt "$timeout" ]; do
        # Check if mcp-server is healthy
        if docker compose ps 2>/dev/null | grep -q "mcp-server.*healthy"; then
            printf "\r${CLEAR_LINE}"
            printf "${SHOW_CURSOR}"
            echo ""
            ok "MCP server is healthy and ready!"
            return 0
        fi

        # Check if mcp-server exited/failed
        if docker compose ps 2>/dev/null | grep -q "mcp-server.*Exit"; then
            printf "\r${CLEAR_LINE}"
            printf "${SHOW_CURSOR}"
            echo ""
            fail "MCP server exited unexpectedly."
            echo -e "  ${DIM}Check logs: cd $INSTALL_DIR && docker compose logs mcp-server${NC}"
            return 1
        fi

        # Determine current phase from container status
        if docker compose ps 2>/dev/null | grep -q "indexer.*running\|indexer.*Up"; then
            phase="indexing"
        elif docker compose ps 2>/dev/null | grep -q "mcp-server.*starting\|mcp-server.*Up"; then
            phase="embedding"
        fi

        # Animated progress with phase info
        local pct=$((elapsed * 100 / timeout))
        local filled=$((pct * 30 / 100))
        local empty=$((30 - filled))
        local bar=""
        for ((i = 0; i < filled; i++)); do bar+="█"; done
        for ((i = 0; i < empty; i++)); do bar+="░"; done

        local frame_idx=$((elapsed / interval % 8))
        local spinner="${SPINNER_FRAMES[$frame_idx]}"

        local phase_label=""
        if [ "$phase" = "indexing" ]; then
            phase_label="${YELLOW}Cloning repos & extracting components${NC}"
        else
            phase_label="${CYAN}Generating embeddings & indexing${NC}"
        fi

        printf "\r  ${CYAN}${spinner}${NC}  ${GREEN}${bar}${NC} ${DIM}${pct}%%${NC}  ${phase_label}  ${DIM}${elapsed}s${NC}  "

        sleep "$interval"
        elapsed=$((elapsed + interval))
    done

    printf "\r${CLEAR_LINE}"
    printf "${SHOW_CURSOR}"
    echo ""
    warn "Timed out after ${timeout}s. The server may still be indexing."
    echo -e "  ${DIM}Check status: cd $INSTALL_DIR && docker compose ps${NC}"
    echo -e "  ${DIM}Watch logs:   cd $INSTALL_DIR && docker compose logs -f mcp-server${NC}"
}

# ──────────────────────────────────────────────
# Print success message
# ──────────────────────────────────────────────

print_success() {
    local port="${MCP_PORT:-8080}"

    step_header "Setup Complete"

    # Celebration banner
    echo ""
    echo -e "  ${GREEN}${BOLD}  ╔══════════════════════════════════════════════════╗${NC}"
    echo -e "  ${GREEN}${BOLD}  ║                                                  ║${NC}"
    echo -e "  ${GREEN}${BOLD}  ║    ${NC}${GREEN}${BOLD}Vision UI MCP Server is running!${NC}${GREEN}${BOLD}            ║${NC}"
    echo -e "  ${GREEN}${BOLD}  ║                                                  ║${NC}"
    echo -e "  ${GREEN}${BOLD}  ║    ${NC}${DIM}Your AI tools can now access the${NC}${GREEN}${BOLD}              ║${NC}"
    echo -e "  ${GREEN}${BOLD}  ║    ${NC}${DIM}Vision UI component library.${NC}${GREEN}${BOLD}                  ║${NC}"
    echo -e "  ${GREEN}${BOLD}  ║                                                  ║${NC}"
    echo -e "  ${GREEN}${BOLD}  ╚══════════════════════════════════════════════════╝${NC}"
    echo ""

    sleep 0.3

    echo -e "  ${BOLD}Next Steps${NC}"
    echo ""
    echo -e "  ${YELLOW}${BOLD}1.${NC} Add MCP config to your AI tool:"
    echo ""
    echo -e "     ${CYAN}VS Code / Copilot / Cursor${NC} → .vscode/mcp.json"
    echo -e "     ${DIM}┌──────────────────────────────────────────┐${NC}"
    echo -e "     ${DIM}│${NC}  {                                       ${DIM}│${NC}"
    echo -e "     ${DIM}│${NC}    \"servers\": {                           ${DIM}│${NC}"
    echo -e "     ${DIM}│${NC}      \"vision-ui\": {                      ${DIM}│${NC}"
    echo -e "     ${DIM}│${NC}        \"type\": \"http\",                    ${DIM}│${NC}"
    echo -e "     ${DIM}│${NC}        \"url\": \"http://localhost:${port}/mcp\" ${DIM}│${NC}"
    echo -e "     ${DIM}│${NC}      }                                    ${DIM}│${NC}"
    echo -e "     ${DIM}│${NC}    }                                      ${DIM}│${NC}"
    echo -e "     ${DIM}│${NC}  }                                        ${DIM}│${NC}"
    echo -e "     ${DIM}└──────────────────────────────────────────┘${NC}"
    echo ""
    echo -e "     ${MAGENTA}Claude Code${NC} → .claude/settings.json"
    echo -e "     ${DIM}┌──────────────────────────────────────────┐${NC}"
    echo -e "     ${DIM}│${NC}  {                                       ${DIM}│${NC}"
    echo -e "     ${DIM}│${NC}    \"mcpServers\": {                       ${DIM}│${NC}"
    echo -e "     ${DIM}│${NC}      \"vision-ui\": {                      ${DIM}│${NC}"
    echo -e "     ${DIM}│${NC}        \"type\": \"http\",                    ${DIM}│${NC}"
    echo -e "     ${DIM}│${NC}        \"url\": \"http://localhost:${port}/mcp\" ${DIM}│${NC}"
    echo -e "     ${DIM}│${NC}      }                                    ${DIM}│${NC}"
    echo -e "     ${DIM}│${NC}    }                                      ${DIM}│${NC}"
    echo -e "     ${DIM}│${NC}  }                                        ${DIM}│${NC}"
    echo -e "     ${DIM}└──────────────────────────────────────────┘${NC}"
    echo ""

    sleep 0.2

    echo -e "  ${YELLOW}${BOLD}2.${NC} Reload your editor"
    echo -e "     ${DIM}VS Code: Cmd+Shift+P (Mac) / Ctrl+Shift+P → 'Reload Window'${NC}"
    echo ""
    echo -e "  ${YELLOW}${BOLD}3.${NC} Try it out"
    echo -e "     ${DIM}Ask your AI: \"Search for Button component\"${NC}"
    echo ""

    echo -e "  ${DIM}────────────────────────────────────────────────────${NC}"
    echo ""
    echo -e "  ${BOLD}Day-to-day commands:${NC}"
    echo ""
    echo -e "    ${GREEN}Start${NC}      cd ~/vision-ui-mcp && docker compose up -d"
    echo -e "    ${RED}Stop${NC}       cd ~/vision-ui-mcp && docker compose down"
    echo -e "    ${BLUE}Logs${NC}       cd ~/vision-ui-mcp && docker compose logs -f"
    echo -e "    ${CYAN}Update${NC}     cd ~/vision-ui-mcp && docker compose pull && docker compose up -d"
    echo -e "    ${DIM}Uninstall${NC}  cd ~/vision-ui-mcp && docker compose down -v && rm -rf ~/vision-ui-mcp"
    echo ""
    echo -e "  ${DIM}Need help? Check the README in $INSTALL_DIR or contact your team lead.${NC}"
    echo ""
}

# ──────────────────────────────────────────────
# Main
# ──────────────────────────────────────────────

main() {
    clear 2>/dev/null || true
    echo ""
    echo ""

    # Animated banner reveal
    local banner_lines=(
        "  ${BLUE}${BOLD}  ╔══════════════════════════════════════════════════════════╗${NC}"
        "  ${BLUE}${BOLD}  ║                                                          ║${NC}"
        "  ${BLUE}${BOLD}  ║   ${NC}${BOLD}Vision UI MCP Server${NC}${BLUE}${BOLD}                                  ║${NC}"
        "  ${BLUE}${BOLD}  ║   ${NC}${DIM}One-command setup for your AI coding tools${NC}${BLUE}${BOLD}              ║${NC}"
        "  ${BLUE}${BOLD}  ║                                                          ║${NC}"
        "  ${BLUE}${BOLD}  ║   ${NC}${DIM}Connects the Vision UI component library to${NC}${BLUE}${BOLD}            ║${NC}"
        "  ${BLUE}${BOLD}  ║   ${NC}${DIM}GitHub Copilot, Claude Code, and Cursor.${NC}${BLUE}${BOLD}               ║${NC}"
        "  ${BLUE}${BOLD}  ║                                                          ║${NC}"
        "  ${BLUE}${BOLD}  ╚══════════════════════════════════════════════════════════╝${NC}"
    )
    for line in "${banner_lines[@]}"; do
        echo -e "$line"
        sleep 0.04
    done

    echo ""
    sleep 0.3

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
