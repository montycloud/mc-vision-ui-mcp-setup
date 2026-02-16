#!/usr/bin/env bash
set -euo pipefail

# Vision UI MCP Server -One-command setup
#
# Supports: macOS (Apple Silicon + Intel), Linux (x64 + ARM), Windows (WSL2 + Git Bash)
#
# Usage (interactive -recommended):
#   bash <(curl -fsSL https://raw.githubusercontent.com/montycloud/mc-vision-ui-mcp-setup/main/setup.sh)
#
# Usage (piped -prompts for input):
#   curl -fsSL https://raw.githubusercontent.com/montycloud/mc-vision-ui-mcp-setup/main/setup.sh | bash
#
#   Or if curl is not available:
#   wget -qO- https://raw.githubusercontent.com/montycloud/mc-vision-ui-mcp-setup/main/setup.sh | bash

# ──────────────────────────────────────────────
# Shell compatibility guard
# ──────────────────────────────────────────────
# Requires bash 3.2+ (ships with every macOS and modern Linux).
# No bash 4+ features are used (no namerefs, no associative arrays,
# no case-modification expansions, no readarray/mapfile).
if [ -z "${BASH_VERSION:-}" ]; then
    echo "Error: This script requires bash. Run with: bash setup.sh" >&2
    exit 1
fi

REPO="https://github.com/montycloud/mc-vision-ui-mcp-setup.git"
INSTALL_DIR="${HOME}/vision-ui-mcp"
MIN_DOCKER_VERSION="20.10"
MIN_COMPOSE_VERSION="2.0"
MIN_DISK_GB=10
MIN_RAM_GB=4

# Total steps in the setup flow (for progress tracking)
TOTAL_STEPS=7
CURRENT_STEP=0
SETUP_START_TIME=$(date +%s)
STEP_NAMES=("" "System Requirements" "Download Setup Files" "Configure Environment" "Authenticate Registry" "Pull & Start Services" "Indexing & Health Check" "Setup Complete")
PREV_STEP_NAME=""

# Config state (populated during configure_env, used in summary)
CFG_PROVIDER=""
CFG_REGION=""
CFG_KEY_TYPE=""

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
    WHITE='\033[1;37m'
    BOLD='\033[1m'
    DIM='\033[2m'
    ITALIC='\033[3m'
    NC='\033[0m'
    # Cursor control
    HIDE_CURSOR='\033[?25l'
    SHOW_CURSOR='\033[?25h'
    CLEAR_LINE='\033[2K'
    MOVE_UP='\033[1A'
else
    RED='' GREEN='' YELLOW='' BLUE='' CYAN='' MAGENTA='' WHITE='' BOLD='' DIM='' ITALIC='' NC=''
    HIDE_CURSOR='' SHOW_CURSOR='' CLEAR_LINE='' MOVE_UP=''
fi

# Terminal capabilities
TERM_WIDTH=$(tput cols 2>/dev/null || echo 80)
[ "$TERM_WIDTH" -lt 60 ] && TERM_WIDTH=80
[ "$TERM_WIDTH" -gt 120 ] && TERM_WIDTH=120
TERM_COLORS=$(tput colors 2>/dev/null || echo 8)

# Extended palette for 256-color terminals
if [ -t 1 ] && [ "$TERM_COLORS" -ge 256 ]; then
    ACCENT='\033[38;5;75m'       # Soft blue
    SOFT_GREEN='\033[38;5;114m'  # Muted green
    SOFT_YELLOW='\033[38;5;222m' # Muted yellow
    SOFT_RED='\033[38;5;210m'    # Muted red
    SHADOW='\033[38;5;242m'      # Mid gray
    LIGHT='\033[38;5;252m'       # Light gray
    BRIGHT_GREEN='\033[38;5;82m' # Vivid green
    BRIGHT_CYAN='\033[38;5;87m'  # Vivid cyan
else
    ACCENT="$CYAN"
    SOFT_GREEN="$GREEN"
    SOFT_YELLOW="$YELLOW"
    SOFT_RED="$RED"
    SHADOW="$DIM"
    LIGHT=""
    BRIGHT_GREEN="$GREEN"
    BRIGHT_CYAN="$CYAN"
fi

# Detect UTF-8 support for safe glyph rendering
HAS_UTF8=false
if printf '%s' "${LANG:-}${LC_ALL:-}${LC_CTYPE:-}" | grep -qi 'utf'; then
    HAS_UTF8=true
fi

# Status glyphs (ASCII fallback for non-UTF-8 terminals)
if $HAS_UTF8; then
    CHECK_PASS="●"
    CHECK_FAIL="✗"
    CHECK_WARN="◑"
    ARROW_RIGHT="›"
    BULLET="▸"
    # Box-drawing characters
    BOX_TL="┌" BOX_TR="┐" BOX_BL="└" BOX_BR="┘" BOX_H="─" BOX_V="│"
else
    CHECK_PASS="*"
    CHECK_FAIL="x"
    CHECK_WARN="!"
    ARROW_RIGHT=">"
    BULLET="-"
    # ASCII box-drawing fallback
    BOX_TL="+" BOX_TR="+" BOX_BL="+" BOX_BR="+" BOX_H="-" BOX_V="|"
fi

# Double-line box chars (for banners)
if $HAS_UTF8; then
    DBOX_TL="╔" DBOX_TR="╗" DBOX_BL="╚" DBOX_BR="╝" DBOX_H="═" DBOX_V="║"
    HALF_CIRCLE="◐"
    EMPTY_CIRCLE="○"
    STAR="✦"
else
    DBOX_TL="+" DBOX_TR="+" DBOX_BL="+" DBOX_BR="+" DBOX_H="=" DBOX_V="|"
    HALF_CIRCLE="~"
    EMPTY_CIRCLE="o"
    STAR="*"
fi

# ──────────────────────────────────────────────
# Cleanup & error handling
# ──────────────────────────────────────────────

cleanup() {
    local exit_code=$?
    printf "${SHOW_CURSOR}"
    if [ -n "${SPINNER_PID:-}" ] && kill -0 "$SPINNER_PID" 2>/dev/null; then
        kill "$SPINNER_PID" 2>/dev/null || true
        wait "$SPINNER_PID" 2>/dev/null || true
    fi
    if [ "$exit_code" -ne 0 ]; then
        echo ""
        echo -e "  ${RED}${BOLD}${CHECK_FAIL} Setup failed${NC} ${DIM}(exit code ${exit_code})${NC}"
        echo -e "  ${SHADOW}  Re-run with:  bash -x setup.sh${NC}"
        echo ""
    fi
}
trap cleanup EXIT
trap 'echo -e "\n  ${RED}${CHECK_FAIL} Error on line ${LINENO}:${NC} command exited with code $?"' ERR

# ──────────────────────────────────────────────
# Logging helpers
# ──────────────────────────────────────────────

INFO_ICON="i"; $HAS_UTF8 && INFO_ICON="ℹ"
info()  { echo -e "  ${ACCENT}${INFO_ICON}${NC}  $1"; }
ok()    { echo -e "  ${GREEN}${CHECK_PASS}${NC}  $1"; }
warn()  { echo -e "  ${YELLOW}${CHECK_WARN}${NC}  $1"; }
fail()  { echo -e "  ${RED}${CHECK_FAIL}${NC}  $1"; }
die()   { echo -e "\n  ${RED}${BOLD}${CHECK_FAIL} ERROR:${NC} $1"; printf "${SHOW_CURSOR}"; exit 1; }

# ──────────────────────────────────────────────
# Formatting helpers
# ──────────────────────────────────────────────

format_time() {
    local secs=$1
    printf "%d:%02d" $((secs / 60)) $((secs % 60))
}

mask_secret() {
    local value="$1"
    local prefix_len="${2:-8}"
    local len=${#value}
    if [ "$len" -le "$prefix_len" ]; then
        echo "$value"
    else
        echo "${value:0:$prefix_len}********"
    fi
}

# Repeat a character N times
repeat_char() {
    local char="$1" count="$2"
    local result=""
    for ((i = 0; i < count; i++)); do result+="$char"; done
    echo "$result"
}

# Draw a horizontal rule
hr() {
    local width=$((TERM_WIDTH - 4))
    echo -e "  ${SHADOW}$(repeat_char "$BOX_H" "$width")${NC}"
}

# ──────────────────────────────────────────────
# Box drawing helpers
# ──────────────────────────────────────────────

box_top() {
    local title="${1:-}"
    local width=$((TERM_WIDTH - 6))
    if [ -n "$title" ]; then
        local title_len=${#title}
        local pad=$((width - title_len - 3))
        [ "$pad" -lt 2 ] && pad=2
        echo -e "  ${SHADOW}${BOX_TL}${BOX_H}${NC} ${BOLD}${title}${NC} ${SHADOW}$(repeat_char "$BOX_H" "$pad")${BOX_TR}${NC}"
    else
        echo -e "  ${SHADOW}${BOX_TL}$(repeat_char "$BOX_H" "$((width))")${BOX_TR}${NC}"
    fi
}

box_line() {
    local content="$1"
    local width=$((TERM_WIDTH - 6))
    echo -e "  ${SHADOW}${BOX_V}${NC}  ${content}"
}

box_empty() {
    echo -e "  ${SHADOW}${BOX_V}${NC}"
}

box_bottom() {
    local width=$((TERM_WIDTH - 6))
    echo -e "  ${SHADOW}${BOX_BL}$(repeat_char "$BOX_H" "$width")${BOX_BR}${NC}"
}

# ──────────────────────────────────────────────
# Animation helpers
# ──────────────────────────────────────────────

# Dots spinner -modern 10-frame animation (ASCII fallback for non-UTF-8)
if $HAS_UTF8; then
    SPINNER_FRAMES=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
else
    SPINNER_FRAMES=('-' '\' '|' '/' '-' '\' '|' '/' '-' '/')
fi
SPINNER_PID=""

spinner_start() {
    local msg="$1"
    printf "${HIDE_CURSOR}"
    (
        local i=0
        while true; do
            printf "\r  ${ACCENT}${SPINNER_FRAMES[$((i % 10))]}${NC}  ${msg}" >&2
            i=$((i + 1))
            sleep 0.08
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
            echo -e "     ${SHADOW}${output}${NC}" | head -5
        fi
        return 1
    fi
}

# Step header with progress indicator and section dividers
step_header() {
    CURRENT_STEP=$((CURRENT_STEP + 1))
    local title="$1"

    # Section completion divider (for steps after the first)
    if [ "$CURRENT_STEP" -gt 1 ] && [ -n "$PREV_STEP_NAME" ]; then
        echo ""
        local elapsed=$(( $(date +%s) - SETUP_START_TIME ))
        echo -e "  ${SHADOW}${BOX_H}${BOX_H}${NC} ${GREEN}${CHECK_PASS}${NC} ${SHADOW}${PREV_STEP_NAME}${NC} ${SHADOW}$(repeat_char "$BOX_H" $((TERM_WIDTH - ${#PREV_STEP_NAME} - 12)))${NC}"
    fi
    PREV_STEP_NAME="$title"

    # Progress bar
    local bar_width=30
    local filled=$((CURRENT_STEP * bar_width / TOTAL_STEPS))
    local empty=$((bar_width - filled))
    local bar=""
    local bar_fill bar_empty
    if $HAS_UTF8; then bar_fill="━"; bar_empty="╌"; else bar_fill="="; bar_empty="."; fi
    for ((i = 0; i < filled; i++)); do bar+="$bar_fill"; done
    for ((i = 0; i < empty; i++)); do bar+="$bar_empty"; done

    echo ""
    echo -e "  ${ACCENT}${bar}${NC}  ${SHADOW}${CURRENT_STEP}/${TOTAL_STEPS}${NC}"
    echo -e "  ${BOLD}${title}${NC}"
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

# Run a command with a timeout (portable -works on macOS without coreutils)
# Usage: with_timeout 30 docker login ...
# Returns 124 on timeout, otherwise the command's exit code.
with_timeout() {
    local secs="$1"
    shift
    "$@" &
    local cmd_pid=$!
    (
        sleep "$secs"
        kill "$cmd_pid" 2>/dev/null || true
    ) &
    local timer_pid=$!
    if wait "$cmd_pid" 2>/dev/null; then
        kill "$timer_pid" 2>/dev/null || true
        wait "$timer_pid" 2>/dev/null || true
        return 0
    else
        local rc=$?
        kill "$timer_pid" 2>/dev/null || true
        wait "$timer_pid" 2>/dev/null || true
        # 143 = killed by our timer (128 + 15 SIGTERM)
        [ "$rc" -eq 143 ] && return 124
        return "$rc"
    fi
}

# Animated countdown
countdown() {
    local secs=$1
    local msg="${2:-Starting in}"
    for ((i = secs; i > 0; i--)); do
        printf "\r  ${SHADOW}${msg} ${i}s...${NC}"
        sleep 1
    done
    printf "\r${CLEAR_LINE}"
}

# Time-aware color (for health check progress)
get_time_color() {
    local elapsed=$1
    if   [ "$elapsed" -lt 60  ]; then echo -ne "$GREEN"
    elif [ "$elapsed" -lt 180 ]; then echo -ne "$CYAN"
    elif [ "$elapsed" -lt 270 ]; then echo -ne "$YELLOW"
    else echo -ne "$RED"
    fi
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
        arm64|aarch64)   ARCH="arm64"; CHIP="Apple Silicon / ARM64" ;;
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

    # Use printf (not read -p) so ANSI escape sequences render correctly
    if [ -t 0 ]; then
        printf "%b" "$prompt_text"
        read -r "$var_name"
    elif [ -e /dev/tty ]; then
        printf "%b" "$prompt_text" > /dev/tty
        read -r "$var_name" < /dev/tty
    else
        echo ""
        fail "Cannot read input -no terminal available."
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

    # Strip trailing carriage returns (clipboard paste artefact)
    local raw="${!var_name}"
    raw="${raw%$'\r'}"
    printf -v "$var_name" '%s' "$raw"
}

# Silent input for secrets (API keys, tokens) -hides typed/pasted text,
# shows a masked preview after entry.
#
# KEY FIX: macOS has a MAX_CANON kernel limit (~1024 bytes) for terminal
# line input in canonical mode. Bedrock short-term API keys are ~1044 chars
# which EXCEEDS this limit, causing `read -rs` to hang indefinitely.
# Solution: disable canonical mode with `stty -icanon` before reading,
# then restore afterwards. This lets the kernel pass chars through without
# a line-buffer limit while bash's `read` still collects until newline.
prompt_secret() {
    local prompt_text="$1"
    local var_name="$2"
    local hint="${3:-}"   # e.g. "ABSK..." or "ghp_..."
    local tty_fd saved_stty

    if [ -t 0 ]; then
        tty_fd="/dev/stdin"
    elif [ -e /dev/tty ]; then
        tty_fd="/dev/tty"
    else
        echo ""
        fail "Cannot read input -no terminal available."
        exit 1
    fi

    # Save terminal state and switch to non-canonical, no-echo mode
    # This bypasses the macOS MAX_CANON 1024-byte line buffer limit
    saved_stty=$(stty -g < "$tty_fd" 2>/dev/null) || true
    stty -echo -icanon < "$tty_fd" 2>/dev/null || true

    printf "%b" "$prompt_text" > "$tty_fd"
    IFS= read -r "$var_name" < "$tty_fd"

    # Restore terminal state
    if [ -n "$saved_stty" ]; then
        stty "$saved_stty" < "$tty_fd" 2>/dev/null || true
    else
        stty echo icanon < "$tty_fd" 2>/dev/null || true
    fi
    echo "" > "$tty_fd"  # newline after silent read

    # Strip trailing carriage returns (clipboard paste from Windows/web can include \r)
    local raw_value="${!var_name}"
    raw_value="${raw_value%$'\r'}"
    printf -v "$var_name" '%s' "$raw_value"

    # Show masked preview so the user knows something was captured
    local value="${!var_name}"
    if [ -n "$value" ]; then
        local len=${#value}
        local preview=$(mask_secret "$value" 8)
        echo -e "    ${SHADOW}${ARROW_RIGHT} ${preview}${NC} ${SHADOW}(${len} chars)${NC}"
    fi
}

# ──────────────────────────────────────────────
# Pre-flight: Check system requirements
# ──────────────────────────────────────────────

preflight_checks() {
    local errors=0

    step_header "System Requirements"

    # Platform info in a compact line
    echo -e "  ${SHADOW}${OS} ${BULLET} ${CHIP}${NC}"
    echo ""

    if [ "$OS" = "unknown" ]; then
        fail "Unsupported OS. Supports macOS, Linux, Windows (WSL2 / Git Bash)."
        errors=$((errors + 1))
    fi

    if [ "$ARCH" = "armv7" ]; then
        fail "32-bit ARM not supported. Docker images require 64-bit."
        errors=$((errors + 1))
    fi

    # Animated checklist -each item reveals with a brief pause
    local col_width=36
    local col=0  # 0 = left column, 1 = right column

    # Helper: print a check result in 2-column grid
    print_check() {
        local icon="$1" label="$2" color="$3"
        if [ "$col" -eq 0 ]; then
            # Left column -print without newline, pad to col_width
            printf "  ${color}${icon}${NC}  %-${col_width}s" "$label"
            col=1
        else
            # Right column -print with newline
            printf "${color}${icon}${NC}  %s\n" "$label"
            col=0
        fi
        sleep 0.06
    }

    # -- Git --
    if command -v git >/dev/null 2>&1; then
        local git_ver=$(git --version | sed 's/git version //')
        print_check "$CHECK_PASS" "git ${git_ver}" "$GREEN"
    else
        print_check "$CHECK_FAIL" "git (missing)" "$RED"
        errors=$((errors + 1))
    fi

    # -- Docker --
    if command -v docker >/dev/null 2>&1; then
        local docker_ver
        docker_ver=$(docker version --format '{{.Client.Version}}' 2>/dev/null || echo "0.0")
        if version_gte "$docker_ver" "$MIN_DOCKER_VERSION"; then
            print_check "$CHECK_PASS" "Docker v${docker_ver}" "$GREEN"
        else
            print_check "$CHECK_FAIL" "Docker ${docker_ver} (need >=${MIN_DOCKER_VERSION})" "$RED"
            errors=$((errors + 1))
        fi
    else
        print_check "$CHECK_FAIL" "Docker (missing)" "$RED"
        errors=$((errors + 1))
    fi

    # -- Docker running --
    if command -v docker >/dev/null 2>&1; then
        if docker info >/dev/null 2>&1; then
            print_check "$CHECK_PASS" "Docker daemon running" "$GREEN"
        else
            print_check "$CHECK_FAIL" "Docker daemon stopped" "$RED"
            errors=$((errors + 1))
        fi
    fi

    # -- Docker Compose --
    if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
        if docker compose version >/dev/null 2>&1; then
            local compose_ver
            compose_ver=$(docker compose version --short 2>/dev/null | sed 's/^v//')
            if version_gte "$compose_ver" "$MIN_COMPOSE_VERSION"; then
                print_check "$CHECK_PASS" "Compose v${compose_ver}" "$GREEN"
            else
                print_check "$CHECK_FAIL" "Compose ${compose_ver} (need >=${MIN_COMPOSE_VERSION})" "$RED"
                errors=$((errors + 1))
            fi
        elif command -v docker-compose >/dev/null 2>&1; then
            print_check "$CHECK_FAIL" "Compose v1 (need v2+)" "$RED"
            errors=$((errors + 1))
        else
            print_check "$CHECK_FAIL" "Compose (missing)" "$RED"
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
            print_check "$CHECK_PASS" "Disk: ${available_gb}GB free" "$GREEN"
        elif [ "$available_gb" -gt 0 ] 2>/dev/null; then
            print_check "$CHECK_WARN" "Disk: ${available_gb}GB (rec ${MIN_DISK_GB}GB)" "$YELLOW"
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
        print_check "$CHECK_PASS" "RAM: ${total_ram_gb}GB" "$GREEN"
    elif [ "$total_ram_gb" -gt 0 ] 2>/dev/null; then
        print_check "$CHECK_WARN" "RAM: ${total_ram_gb}GB (rec ${MIN_RAM_GB}GB)" "$YELLOW"
    fi

    # -- Port 8080 --
    if command -v lsof >/dev/null 2>&1; then
        if lsof -i :8080 >/dev/null 2>&1; then
            print_check "$CHECK_WARN" "Port 8080 in use" "$YELLOW"
        else
            print_check "$CHECK_PASS" "Port 8080 available" "$GREEN"
        fi
    elif command -v ss >/dev/null 2>&1; then
        if ss -tlnp 2>/dev/null | grep -q ':8080 '; then
            print_check "$CHECK_WARN" "Port 8080 in use" "$YELLOW"
        else
            print_check "$CHECK_PASS" "Port 8080 available" "$GREEN"
        fi
    fi

    # -- curl or wget --
    if command -v curl >/dev/null 2>&1; then
        print_check "$CHECK_PASS" "curl" "$GREEN"
    elif command -v wget >/dev/null 2>&1; then
        print_check "$CHECK_PASS" "wget" "$GREEN"
    else
        print_check "$CHECK_WARN" "curl/wget (missing)" "$YELLOW"
    fi

    # Flush incomplete row
    [ "$col" -eq 1 ] && echo ""

    echo ""

    if [ "$errors" -gt 0 ]; then
        echo -e "  ${RED}${BOLD}${CHECK_FAIL} ${errors} issue(s) found. Fix them and re-run this script.${NC}"
        echo ""

        # Show install hints for failures
        if ! command -v git >/dev/null 2>&1; then
            echo -e "  ${SHADOW}  git:    ${NC}"
            case "$OS" in
                macos) echo -e "  ${SHADOW}    xcode-select --install  or  brew install git${NC}" ;;
                linux|wsl) echo -e "  ${SHADOW}    sudo apt install -y git${NC}" ;;
                *) echo -e "  ${SHADOW}    https://git-scm.com${NC}" ;;
            esac
        fi
        if ! command -v docker >/dev/null 2>&1; then
            echo -e "  ${SHADOW}  Docker: https://docs.docker.com/get-docker/${NC}"
        fi
        echo ""
        exit 1
    fi

    echo -e "  ${GREEN}${BOLD}All checks passed${NC}"
    sleep 0.3
}

# ──────────────────────────────────────────────
# Check if already installed
# ──────────────────────────────────────────────

check_existing() {
    if [ -d "$INSTALL_DIR" ]; then
        echo ""
        warn "Directory ${DIM}$INSTALL_DIR${NC} ${YELLOW}already exists.${NC}"
        echo ""

        box_top "Choose Action"
        box_line "${GREEN}1${NC}  Update     ${SHADOW}-- Pull latest images and restart${NC}"
        box_line "${YELLOW}2${NC}  Reinstall  ${SHADOW}-- Remove everything and start fresh${NC}"
        box_line "${SHADOW}3${NC}  Quit       ${SHADOW}-- Exit without changes${NC}"
        box_bottom
        echo ""

        local choice=""
        prompt_user "  ${BOLD}Choose [1/2/3]:${NC} " choice

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
        ok "Setup files downloaded to ${SHADOW}${INSTALL_DIR}${NC}"
    else
        spinner_stop
        die "Failed to clone repository. Check your network connection and try again.\n  URL: $REPO"
    fi
}

# Safely set KEY=VALUE in a .env file. Works for any value length (including
# 1000+ char Bedrock short-term tokens) without sed line-length limits.
# IMPORTANT: Uses ENVIRON[] instead of awk -v to avoid C-style backslash
# escape interpretation that can hang/corrupt base64-encoded tokens.
# Usage: env_set .env KEY VALUE
env_set() {
    local file="$1" key="$2" value="$3"
    local tmp="${file}.tmp.$$"
    if grep -q "^${key}=" "$file" 2>/dev/null; then
        # Key exists (uncommented) -replace the line
        _ENVSET_K="$key" _ENVSET_V="$value" \
            awk 'BEGIN{k=ENVIRON["_ENVSET_K"]; v=ENVIRON["_ENVSET_V"]}
                 {split($0,a,"="); if(a[1]==k){print k"="v}else{print}}' "$file" > "$tmp"
        mv "$tmp" "$file"
    elif grep -q "^# *${key}=" "$file" 2>/dev/null; then
        # Key exists (commented out) -uncomment and set
        _ENVSET_K="$key" _ENVSET_V="$value" \
            awk 'BEGIN{k=ENVIRON["_ENVSET_K"]; v=ENVIRON["_ENVSET_V"]}
                 {if($0 ~ "^# *"k"="){print k"="v}else{print}}' "$file" > "$tmp"
        mv "$tmp" "$file"
    else
        # Key doesn't exist -append
        printf '%s=%s\n' "$key" "$value" >> "$file"
    fi
}

# ──────────────────────────────────────────────
# Configure environment
# ──────────────────────────────────────────────

configure_env() {
    cd "$INSTALL_DIR"
    cp .env.example .env

    step_header "Configure Environment"

    # ── GitHub Token ──
    box_top "GitHub Personal Access Token"
    box_line "${SHADOW}Create at: https://github.com/settings/tokens${NC}"
    box_line "${SHADOW}Scopes:   repo (read), read:packages${NC}"
    box_bottom
    echo ""

    prompt_secret "  ${BOLD}Token:${NC} " GIT_TOKEN "ghp_"
    [ -z "${GIT_TOKEN:-}" ] && die "GitHub token is required. Create one at: https://github.com/settings/tokens (scopes: repo, read:packages)"
    ok "GitHub token saved"

    echo ""

    # ── Embedding Provider ──
    box_top "Embedding Provider"
    box_line "Semantic search requires an embedding provider."
    box_empty
    box_line "  ${GREEN}1${NC}  OpenAI   ${SHADOW}-- API key from platform.openai.com${NC}"
    box_line "  ${CYAN}2${NC}  Bedrock  ${SHADOW}-- AWS API key (recommended for MontyCloud)${NC}"
    box_bottom
    echo ""

    prompt_user "  ${BOLD}Enter 1 or 2 [1]:${NC} " EMBEDDING_CHOICE
    EMBEDDING_CHOICE="${EMBEDDING_CHOICE:-1}"

    if [ "$EMBEDDING_CHOICE" = "2" ]; then
        configure_bedrock
    else
        configure_openai
    fi

    # Show configuration summary
    show_config_summary
}

# ──────────────────────────────────────────────
# Configure AWS Bedrock (embedding provider)
# ──────────────────────────────────────────────

configure_bedrock() {
    CFG_PROVIDER="bedrock"
    echo ""

    box_top "AWS Bedrock Setup"
    box_line "Choose your API key type:"
    box_empty
    box_line "  ${GREEN}a${NC}  Long-term   ${SHADOW}-- custom expiry, starts with ABSK...${NC}"
    box_line "  ${YELLOW}b${NC}  Short-term  ${SHADOW}-- up to 12 hours, starts with bedrock-api-key-...${NC}"
    box_empty
    box_line "${SHADOW}Both are single bearer tokens -just different expiration.${NC}"
    box_bottom
    echo ""

    local key_type=""
    prompt_user "  ${BOLD}API key type [a/b]:${NC} " key_type
    key_type="${key_type:-a}"

    echo ""
    prompt_user "  ${BOLD}AWS region [us-east-1]:${NC} " BEDROCK_REGION
    BEDROCK_REGION="${BEDROCK_REGION:-us-east-1}"
    CFG_REGION="$BEDROCK_REGION"

    if [ "$key_type" = "b" ] || [ "$key_type" = "B" ]; then
        CFG_KEY_TYPE="short-term"
        echo ""
        echo -e "  ${SHADOW}Generate at: AWS Console ${ARROW_RIGHT} Amazon Bedrock ${ARROW_RIGHT} API keys ${ARROW_RIGHT} Short-term${NC}"
        echo ""

        prompt_secret "  ${BOLD}Bedrock short-term API key:${NC} " BEDROCK_API_KEY
        [ -z "${BEDROCK_API_KEY:-}" ] && die "Bedrock API key is required. Generate one at: AWS Console >Amazon Bedrock >API keys."

        # Write .env -use env_set (not sed) so 1000+ char keys work reliably
        env_set .env GIT_TOKEN "$GIT_TOKEN"
        env_set .env EMBEDDING_PROVIDER "bedrock"
        env_set .env AWS_BEARER_TOKEN_BEDROCK "$BEDROCK_API_KEY"
        env_set .env AWS_DEFAULT_REGION "$BEDROCK_REGION"

        echo ""
        echo -e "  ${YELLOW}${CHECK_WARN}${NC}  ${SHADOW}Short-term keys expire within 12 hours. When expired:${NC}"
        echo -e "     ${SHADOW}1. Generate a new key in AWS Console${NC}"
        echo -e "     ${SHADOW}2. Update AWS_BEARER_TOKEN_BEDROCK in ~/vision-ui-mcp/.env${NC}"
        echo -e "     ${SHADOW}3. Run: cd ~/vision-ui-mcp && docker compose restart mcp-server${NC}"
        echo ""
        ok "Configured for AWS Bedrock ${SHADOW}(short-term, ${BEDROCK_REGION})${NC}"
    else
        CFG_KEY_TYPE="long-term"
        echo ""
        echo -e "  ${SHADOW}Generate at: AWS Console ${ARROW_RIGHT} Amazon Bedrock ${ARROW_RIGHT} API keys ${ARROW_RIGHT} Long-term${NC}"
        echo ""

        prompt_secret "  ${BOLD}Bedrock API key (ABSK...):${NC} " BEDROCK_API_KEY
        [ -z "${BEDROCK_API_KEY:-}" ] && die "Bedrock API key is required. Generate one at: AWS Console >Amazon Bedrock >API keys."

        # Write .env
        env_set .env GIT_TOKEN "$GIT_TOKEN"
        env_set .env EMBEDDING_PROVIDER "bedrock"
        env_set .env AWS_BEARER_TOKEN_BEDROCK "$BEDROCK_API_KEY"
        env_set .env AWS_DEFAULT_REGION "$BEDROCK_REGION"

        echo ""
        ok "Configured for AWS Bedrock ${SHADOW}(long-term, ${BEDROCK_REGION})${NC}"
    fi
}

# ──────────────────────────────────────────────
# Configure OpenAI (embedding provider)
# ──────────────────────────────────────────────

configure_openai() {
    CFG_PROVIDER="openai"
    CFG_KEY_TYPE=""
    CFG_REGION=""
    echo ""

    box_top "OpenAI API Key"
    box_line "${SHADOW}Get one at: https://platform.openai.com/api-keys${NC}"
    box_bottom
    echo ""

    prompt_secret "  ${BOLD}API key (sk-...):${NC} " OPENAI_API_KEY
    [ -z "${OPENAI_API_KEY:-}" ] && die "OpenAI API key is required. Get one at: https://platform.openai.com/api-keys"

    # Write .env
    env_set .env GIT_TOKEN "$GIT_TOKEN"
    env_set .env OPENAI_API_KEY "$OPENAI_API_KEY"

    ok "Configured for OpenAI"
}

# ──────────────────────────────────────────────
# Configuration summary
# ──────────────────────────────────────────────

show_config_summary() {
    echo ""

    local git_preview=$(mask_secret "$GIT_TOKEN" 8)
    local git_len=${#GIT_TOKEN}

    box_top "Configuration Summary"
    box_empty

    if [ "$CFG_PROVIDER" = "bedrock" ]; then
        local key_preview=$(mask_secret "$BEDROCK_API_KEY" 12)
        local key_len=${#BEDROCK_API_KEY}
        box_line "Provider   ${CYAN}AWS Bedrock${NC} ${SHADOW}(${CFG_KEY_TYPE} key)${NC}"
        box_line "Region     ${CYAN}${CFG_REGION}${NC}"
        box_line "API Key    ${SHADOW}${key_preview}  (${key_len} chars)${NC}"
    else
        local key_preview=$(mask_secret "$OPENAI_API_KEY" 8)
        local key_len=${#OPENAI_API_KEY}
        box_line "Provider   ${GREEN}OpenAI${NC}"
        box_line "API Key    ${SHADOW}${key_preview}  (${key_len} chars)${NC}"
    fi

    box_line "GitHub     ${SHADOW}${git_preview}  (${git_len} chars)${NC}"
    box_empty
    box_bottom
    echo ""

    sleep 0.5
}

# ──────────────────────────────────────────────
# Authenticate with GitHub Container Registry
# ──────────────────────────────────────────────

login_ghcr() {
    step_header "Authenticate Registry"

    spinner_start "Logging into GitHub Container Registry..."
    # Use timeout to prevent hanging on credential helpers or network issues
    if with_timeout 30 bash -c 'echo "$1" | docker login ghcr.io -u "token" --password-stdin >/dev/null 2>&1' _ "$GIT_TOKEN"; then
        spinner_stop
        ok "Logged into ghcr.io"
    else
        local rc=$?
        spinner_stop
        if [ "$rc" -eq 124 ]; then
            warn "ghcr.io login timed out (30s) -continuing anyway."
            echo -e "    ${SHADOW}Docker credential helper may be slow. Images will still pull if public.${NC}"
        else
            warn "ghcr.io login failed -images may not pull if private."
            echo -e "    ${SHADOW}Fix: echo YOUR_TOKEN | docker login ghcr.io -u YOUR_USERNAME --password-stdin${NC}"
        fi
    fi
}

# ──────────────────────────────────────────────
# Start the stack
# ──────────────────────────────────────────────

start_stack() {
    step_header "Pull & Start Services"

    # Pull images with spinner (5 min timeout -large images on slow networks)
    spinner_start "Pulling Docker images ${SHADOW}(this may take a few minutes on first run)${NC}"
    if with_timeout 300 docker compose pull >/dev/null 2>&1; then
        spinner_stop
        ok "Docker images pulled"
    else
        spinner_stop
        echo ""
        fail "Failed to pull Docker images."
        echo ""
        box_top "Troubleshooting"
        box_line "${SHADOW}${BULLET} ghcr.io authentication failed${NC}"
        box_line "${SHADOW}${BULLET} Network/firewall blocking ghcr.io${NC}"
        box_line "${SHADOW}${BULLET} GitHub token missing 'read:packages' scope${NC}"
        box_empty
        box_line "${SHADOW}Files saved in $INSTALL_DIR -fix the issue and run:${NC}"
        box_line "cd $INSTALL_DIR && docker compose up -d"
        box_bottom
        exit 1
    fi

    # Start services with spinner (2 min timeout)
    spinner_start "Starting PostgreSQL, Indexer, MCP Server..."
    if with_timeout 120 docker compose up -d >/dev/null 2>&1; then
        spinner_stop
        ok "Services started"
    else
        spinner_stop
        echo ""
        fail "Failed to start services."
        echo ""
        box_top "Troubleshooting"
        box_line "${SHADOW}${BULLET} Port 8080 in use >Set MCP_PORT=9090 in .env${NC}"
        box_line "${SHADOW}${BULLET} Not enough memory >Increase Docker resources${NC}"
        box_line "${SHADOW}Check logs: cd $INSTALL_DIR && docker compose logs${NC}"
        box_bottom
        exit 1
    fi
}

# ──────────────────────────────────────────────
# Wait for health -Live container dashboard
# ──────────────────────────────────────────────

wait_for_health() {
    step_header "Indexing & Health Check"

    echo -e "  ${SHADOW}First startup takes 3-5 minutes - cloning repos, extracting${NC}"
    echo -e "  ${SHADOW}components, and generating embeddings.${NC}"
    echo ""

    local timeout=300  # 5 minutes
    local elapsed=0
    local interval=3
    local dashboard_lines=10  # Number of lines the dashboard occupies

    printf "${HIDE_CURSOR}"

    # Draw initial dashboard
    render_dashboard 0 "$timeout"

    while [ "$elapsed" -lt "$timeout" ]; do
        sleep "$interval"
        elapsed=$((elapsed + interval))

        # Check if mcp-server is healthy
        if docker compose ps 2>/dev/null | grep -q "mcp-server.*healthy"; then
            # Erase dashboard
            for ((i = 0; i < dashboard_lines; i++)); do
                printf "${MOVE_UP}${CLEAR_LINE}"
            done
            printf "${SHOW_CURSOR}"

            ok "MCP server is healthy and ready!"
            return 0
        fi

        # Check if mcp-server exited/failed
        if docker compose ps 2>/dev/null | grep -q "mcp-server.*Exit"; then
            for ((i = 0; i < dashboard_lines; i++)); do
                printf "${MOVE_UP}${CLEAR_LINE}"
            done
            printf "${SHOW_CURSOR}"

            fail "MCP server exited unexpectedly."
            echo -e "  ${SHADOW}Check logs: cd $INSTALL_DIR && docker compose logs mcp-server${NC}"
            return 1
        fi

        # Erase and redraw dashboard
        for ((i = 0; i < dashboard_lines; i++)); do
            printf "${MOVE_UP}${CLEAR_LINE}"
        done

        render_dashboard "$elapsed" "$timeout"
    done

    # Erase dashboard
    for ((i = 0; i < dashboard_lines; i++)); do
        printf "${MOVE_UP}${CLEAR_LINE}"
    done
    printf "${SHOW_CURSOR}"

    warn "Timed out after ${timeout}s. The server may still be indexing."
    echo -e "  ${SHADOW}Check: cd $INSTALL_DIR && docker compose ps${NC}"
    echo -e "  ${SHADOW}Logs:  cd $INSTALL_DIR && docker compose logs -f mcp-server${NC}"
}

render_dashboard() {
    local elapsed=$1
    local timeout=$2
    local pct=$((elapsed * 100 / timeout))
    [ "$pct" -gt 100 ] && pct=100

    # Get container states
    local compose_out
    compose_out=$(docker compose ps 2>/dev/null || echo "")

    # Parse each container's status
    local pg_icon pg_status idx_icon idx_status mcp_icon mcp_status watch_icon watch_status
    parse_service_status "$compose_out" "postgres"         pg_icon    pg_status
    parse_service_status "$compose_out" "indexer"          idx_icon   idx_status
    parse_service_status "$compose_out" "mcp-server"       mcp_icon   mcp_status
    parse_service_status "$compose_out" "reindex-watcher"  watch_icon watch_status

    # Progress bar
    local bar_width=30
    local filled=$((pct * bar_width / 100))
    local empty=$((bar_width - filled))
    local bar=""
    local db_fill db_empty
    if $HAS_UTF8; then db_fill="═"; db_empty="░"; else db_fill="="; db_empty="."; fi
    for ((i = 0; i < filled; i++)); do bar+="$db_fill"; done
    for ((i = 0; i < empty; i++)); do bar+="$db_empty"; done

    local time_color
    time_color=$(get_time_color "$elapsed")
    local time_str=$(format_time "$elapsed")
    local total_str=$(format_time "$timeout")

    # Spinner frame
    local frame_idx=$((elapsed / interval % 10))
    local spinner="${SPINNER_FRAMES[$frame_idx]}"

    # Render
    echo -e "  ${SHADOW}${BOX_TL}${BOX_H}${NC} ${BOLD}Services${NC} ${SHADOW}$(repeat_char "$BOX_H" $((TERM_WIDTH - 18)))${BOX_TR}${NC}"
    echo -e "  ${SHADOW}${BOX_V}${NC}"
    printf "  ${SHADOW}${BOX_V}${NC}  %s  %-20s %s\n" "$pg_icon"    "PostgreSQL"       "$pg_status"
    printf "  ${SHADOW}${BOX_V}${NC}  %s  %-20s %s\n" "$idx_icon"   "Indexer"           "$idx_status"
    printf "  ${SHADOW}${BOX_V}${NC}  %s  %-20s %s\n" "$mcp_icon"   "MCP Server"        "$mcp_status"
    printf "  ${SHADOW}${BOX_V}${NC}  %s  %-20s %s\n" "$watch_icon" "Reindex Watcher"   "$watch_status"
    echo -e "  ${SHADOW}${BOX_V}${NC}"
    echo -e "  ${SHADOW}${BOX_V}${NC}  ${ACCENT}${spinner}${NC}  ${time_color}${bar}${NC}  ${SHADOW}${pct}%%${NC}  ${time_color}${time_str}${NC} ${SHADOW}/ ${total_str}${NC}"
    echo -e "  ${SHADOW}${BOX_V}${NC}"
    echo -e "  ${SHADOW}${BOX_BL}$(repeat_char "$BOX_H" $((TERM_WIDTH - 6)))${BOX_BR}${NC}"
}

parse_service_status() {
    local compose_out="$1"
    local service="$2"
    local icon_var=$3
    local status_var=$4

    local line
    line=$(echo "$compose_out" | grep -i "$service" | head -1)

    local _icon _status

    if [ -z "$line" ]; then
        _icon="${SHADOW}${EMPTY_CIRCLE}${NC}"
        _status="${SHADOW}Waiting${NC}"
    elif echo "$line" | grep -qi "healthy"; then
        _icon="${GREEN}${CHECK_PASS}${NC}"
        _status="${GREEN}Healthy${NC}"
    elif echo "$line" | grep -qi "running\|Up"; then
        _icon="${CYAN}${HALF_CIRCLE}${NC}"
        _status="${CYAN}Running${NC}"
    elif echo "$line" | grep -qi "exit\|exited"; then
        local code
        code=$(echo "$line" | grep -oE 'Exit[ed]* [0-9]+' | grep -oE '[0-9]+' || echo "?")
        if [ "$code" = "0" ]; then
            _icon="${GREEN}${CHECK_PASS}${NC}"
            _status="${GREEN}Completed${NC}"
        else
            _icon="${RED}${CHECK_FAIL}${NC}"
            _status="${RED}Failed (exit $code)${NC}"
        fi
    elif echo "$line" | grep -qi "starting\|created"; then
        _icon="${YELLOW}${HALF_CIRCLE}${NC}"
        _status="${YELLOW}Starting${NC}"
    else
        _icon="${SHADOW}${EMPTY_CIRCLE}${NC}"
        _status="${SHADOW}Pending${NC}"
    fi

    eval "$icon_var=\$_icon"
    eval "$status_var=\$_status"
}

# ──────────────────────────────────────────────
# Print success message
# ──────────────────────────────────────────────

print_success() {
    local port="${MCP_PORT:-8080}"

    step_header "Setup Complete"

    # Celebration banner with pulse effect
    local banner_text="Vision UI MCP Server is running!"
    local banner_sub="Your AI tools can now access the Vision UI component library."
    local banner_width=$((${#banner_text} + 8))
    local pad=$(repeat_char ' ' $(( (banner_width - ${#banner_text}) / 2 )) )
    local pad2=$(repeat_char ' ' $(( (banner_width - ${#banner_sub}) / 2 )) )

    # Pulse animation (3 cycles)
    if [ -t 1 ] && [ "$TERM_COLORS" -ge 256 ]; then
        local pulse_colors=(
            '\033[38;5;28m'   # Dark green
            '\033[38;5;34m'   # Medium green
            '\033[38;5;40m'   # Bright green
            '\033[38;5;82m'   # Vivid green
            '\033[38;5;40m'   # Back down
            '\033[38;5;34m'   # Medium
        )
        printf "${HIDE_CURSOR}"
        for color in "${pulse_colors[@]}"; do
            printf "\r  ${color}${BOLD}  ${STAR}  ${banner_text}  ${STAR}${NC}"
            sleep 0.1
        done
        printf "\r${CLEAR_LINE}"
        printf "${SHOW_CURSOR}"
    fi

    echo ""
    echo -e "  ${GREEN}${BOLD}${DBOX_TL}$(repeat_char "$DBOX_H" $((banner_width + 2)))${DBOX_TR}${NC}"
    echo -e "  ${GREEN}${BOLD}${DBOX_V}${NC}  ${pad}${NC}                                        ${GREEN}${BOLD}${DBOX_V}${NC}"
    echo -e "  ${GREEN}${BOLD}${DBOX_V}${NC}  ${BOLD}  ${STAR}  ${banner_text}  ${STAR}${NC}              ${GREEN}${BOLD}${DBOX_V}${NC}"
    echo -e "  ${GREEN}${BOLD}${DBOX_V}${NC}  ${pad}${NC}                                        ${GREEN}${BOLD}${DBOX_V}${NC}"
    echo -e "  ${GREEN}${BOLD}${DBOX_V}${NC}  ${SHADOW}${banner_sub}${NC}   ${GREEN}${BOLD}${DBOX_V}${NC}"
    echo -e "  ${GREEN}${BOLD}${DBOX_V}${NC}  ${pad}${NC}                                        ${GREEN}${BOLD}${DBOX_V}${NC}"
    echo -e "  ${GREEN}${BOLD}${DBOX_BL}$(repeat_char "$DBOX_H" $((banner_width + 2)))${DBOX_BR}${NC}"
    echo ""

    sleep 0.3

    # ── Next Steps ──
    echo -e "  ${BOLD}Next Steps${NC}"
    echo ""

    echo -e "  ${ACCENT}${BOLD}1.${NC} Add MCP config to your AI tool:"
    echo ""

    echo -e "     ${CYAN}VS Code / Copilot / Cursor${NC} ${SHADOW}${ARROW_RIGHT} .vscode/mcp.json${NC}"
    echo -e "     ${SHADOW}${BOX_TL}$(repeat_char "$BOX_H" 42)${BOX_TR}${NC}"
    echo -e "     ${SHADOW}${BOX_V}${NC}  {                                       ${SHADOW}${BOX_V}${NC}"
    echo -e "     ${SHADOW}${BOX_V}${NC}    \"servers\": {                           ${SHADOW}${BOX_V}${NC}"
    echo -e "     ${SHADOW}${BOX_V}${NC}      \"vision-ui\": {                      ${SHADOW}${BOX_V}${NC}"
    echo -e "     ${SHADOW}${BOX_V}${NC}        \"type\": \"http\",                    ${SHADOW}${BOX_V}${NC}"
    echo -e "     ${SHADOW}${BOX_V}${NC}        \"url\": \"http://localhost:${port}/mcp\" ${SHADOW}${BOX_V}${NC}"
    echo -e "     ${SHADOW}${BOX_V}${NC}      }                                    ${SHADOW}${BOX_V}${NC}"
    echo -e "     ${SHADOW}${BOX_V}${NC}    }                                      ${SHADOW}${BOX_V}${NC}"
    echo -e "     ${SHADOW}${BOX_V}${NC}  }                                        ${SHADOW}${BOX_V}${NC}"
    echo -e "     ${SHADOW}${BOX_BL}$(repeat_char "$BOX_H" 42)${BOX_BR}${NC}"
    echo ""

    echo -e "     ${MAGENTA}Claude Code${NC} ${SHADOW}${ARROW_RIGHT} .claude/settings.json${NC}"
    echo -e "     ${SHADOW}${BOX_TL}$(repeat_char "$BOX_H" 42)${BOX_TR}${NC}"
    echo -e "     ${SHADOW}${BOX_V}${NC}  {                                       ${SHADOW}${BOX_V}${NC}"
    echo -e "     ${SHADOW}${BOX_V}${NC}    \"mcpServers\": {                       ${SHADOW}${BOX_V}${NC}"
    echo -e "     ${SHADOW}${BOX_V}${NC}      \"vision-ui\": {                      ${SHADOW}${BOX_V}${NC}"
    echo -e "     ${SHADOW}${BOX_V}${NC}        \"type\": \"http\",                    ${SHADOW}${BOX_V}${NC}"
    echo -e "     ${SHADOW}${BOX_V}${NC}        \"url\": \"http://localhost:${port}/mcp\" ${SHADOW}${BOX_V}${NC}"
    echo -e "     ${SHADOW}${BOX_V}${NC}      }                                    ${SHADOW}${BOX_V}${NC}"
    echo -e "     ${SHADOW}${BOX_V}${NC}    }                                      ${SHADOW}${BOX_V}${NC}"
    echo -e "     ${SHADOW}${BOX_V}${NC}  }                                        ${SHADOW}${BOX_V}${NC}"
    echo -e "     ${SHADOW}${BOX_BL}$(repeat_char "$BOX_H" 42)${BOX_BR}${NC}"
    echo ""

    sleep 0.2

    echo -e "  ${ACCENT}${BOLD}2.${NC} Reload your editor"
    echo -e "     ${SHADOW}VS Code: Cmd+Shift+P (Mac) / Ctrl+Shift+P >'Reload Window'${NC}"
    echo ""
    echo -e "  ${ACCENT}${BOLD}3.${NC} Try it out"
    echo -e "     ${SHADOW}Ask your AI: \"Search for Button component\"${NC}"
    echo ""

    hr
    echo ""
    echo -e "  ${BOLD}Day-to-day commands${NC}"
    echo ""
    echo -e "    ${GREEN}Start${NC}      cd ~/vision-ui-mcp && docker compose up -d"
    echo -e "    ${RED}Stop${NC}       cd ~/vision-ui-mcp && docker compose down"
    echo -e "    ${ACCENT}Logs${NC}       cd ~/vision-ui-mcp && docker compose logs -f"
    echo -e "    ${CYAN}Update${NC}     cd ~/vision-ui-mcp && docker compose pull && docker compose up -d"
    echo -e "    ${SHADOW}Uninstall${NC}  cd ~/vision-ui-mcp && docker compose down -v && rm -rf ~/vision-ui-mcp"
    echo ""
    echo -e "  ${SHADOW}Need help? Check the README in $INSTALL_DIR or contact your team lead.${NC}"
    echo ""
}

# ──────────────────────────────────────────────
# Main
# ──────────────────────────────────────────────

main() {
    clear 2>/dev/null || true
    echo ""

    # Animated banner reveal
    local dbox_line
    dbox_line=$(repeat_char "$DBOX_H" 58)
    local banner_lines=(
        "  ${ACCENT}${BOLD}${DBOX_TL}${dbox_line}${DBOX_TR}${NC}"
        "  ${ACCENT}${BOLD}${DBOX_V}${NC}                                                          ${ACCENT}${BOLD}${DBOX_V}${NC}"
        "  ${ACCENT}${BOLD}${DBOX_V}${NC}   ${WHITE}${BOLD}Vision UI MCP Server${NC}                                  ${ACCENT}${BOLD}${DBOX_V}${NC}"
        "  ${ACCENT}${BOLD}${DBOX_V}${NC}   ${SHADOW}One-command setup for your AI coding tools${NC}              ${ACCENT}${BOLD}${DBOX_V}${NC}"
        "  ${ACCENT}${BOLD}${DBOX_V}${NC}                                                          ${ACCENT}${BOLD}${DBOX_V}${NC}"
        "  ${ACCENT}${BOLD}${DBOX_V}${NC}   ${SHADOW}Connects the Vision UI component library to${NC}            ${ACCENT}${BOLD}${DBOX_V}${NC}"
        "  ${ACCENT}${BOLD}${DBOX_V}${NC}   ${SHADOW}GitHub Copilot, Claude Code, and Cursor.${NC}               ${ACCENT}${BOLD}${DBOX_V}${NC}"
        "  ${ACCENT}${BOLD}${DBOX_V}${NC}                                                          ${ACCENT}${BOLD}${DBOX_V}${NC}"
        "  ${ACCENT}${BOLD}${DBOX_BL}${dbox_line}${DBOX_BR}${NC}"
    )
    for line in "${banner_lines[@]}"; do
        echo -e "$line"
        sleep 0.03
    done

    echo ""
    sleep 0.2

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
