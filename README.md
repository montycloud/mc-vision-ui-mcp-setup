# Vision UI MCP Server — Setup Guide

Connect the **Vision UI component library** to your AI coding tools (GitHub Copilot, Claude Code, Cursor) so they can search components, read source code, and understand your design system.

---

## Before You Start

You'll need **two things** ready (ask your team lead if you don't have them):

1. **GitHub Personal Access Token** — so Docker can pull our private container images and the server can clone component repos.
   Create one at [github.com/settings/tokens](https://github.com/settings/tokens) with `repo` and `read:packages` scopes.

2. **OpenAI API Key** — the server uses this to generate embeddings for semantic search.
   Get one at [platform.openai.com/api-keys](https://platform.openai.com/api-keys).

---

## Quick Setup (All Platforms)

Open your terminal and run:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/montycloud/mc-vision-ui-mcp-setup/main/setup.sh)
```

Alternative forms (also work):

```bash
# Piped form — also supports interactive prompts via /dev/tty
curl -fsSL https://raw.githubusercontent.com/montycloud/mc-vision-ui-mcp-setup/main/setup.sh | bash

# If curl isn't available
wget -qO- https://raw.githubusercontent.com/montycloud/mc-vision-ui-mcp-setup/main/setup.sh | bash
```

The script will automatically check your system, guide you through configuration, and start the server. It supports macOS (Apple Silicon and Intel), Linux (x64 and ARM64), and Windows (WSL2 and Git Bash).

**What happens when you run it:**

1. Checks your system — Docker, disk space, RAM, available ports
2. Downloads setup files to `~/vision-ui-mcp/`
3. Asks for your GitHub token and OpenAI API key
4. Authenticates with GitHub Container Registry
5. Pulls and starts the Docker containers
6. Waits for the MCP server to be healthy (3–5 minutes on first run)
7. Prints the MCP config to paste into your editor

---

## Platform-Specific Prerequisites

### macOS (Apple Silicon M1/M2/M3/M4 or Intel)

1. **Install Docker Desktop for Mac**

   Download from [docker.com/desktop/install/mac-install](https://docs.docker.com/desktop/install/mac-install/) or install via Homebrew:

   ```bash
   brew install --cask docker
   ```

2. **Open Docker Desktop** from your Applications folder and wait until the whale icon appears in your menu bar. The setup script won't work until Docker is running.

3. **Install git** (if not already installed):

   ```bash
   xcode-select --install
   ```

4. Run the setup command above.

### Windows

Docker on Windows requires **WSL2** (Windows Subsystem for Linux). Here's the full path:

1. **Install WSL2** — open PowerShell as Administrator and run:

   ```powershell
   wsl --install
   ```

   Restart your computer when prompted. This installs Ubuntu by default.

2. **Install Docker Desktop for Windows** from [docker.com/desktop/install/windows-install](https://docs.docker.com/desktop/install/windows-install/).

3. **Enable WSL2 integration** — open Docker Desktop → Settings → Resources → WSL Integration → toggle on your Ubuntu distro.

4. **Open Ubuntu** from the Start menu (this is your WSL2 terminal) and run the setup command:

   ```bash
   curl -fsSL https://raw.githubusercontent.com/montycloud/mc-vision-ui-mcp-setup/main/setup.sh | bash
   ```

   *Alternative:* If you prefer Git Bash, install [Git for Windows](https://git-scm.com/download/win), open Git Bash, and run the same command.

### Linux (Ubuntu, Debian, Fedora, CentOS, etc.)

1. **Install Docker Engine:**

   ```bash
   curl -fsSL https://get.docker.com | sh
   sudo usermod -aG docker $USER
   newgrp docker
   ```

   Or install [Docker Desktop for Linux](https://docs.docker.com/desktop/install/linux/).

2. **Install git** (if not already installed):

   ```bash
   sudo apt update && sudo apt install -y git    # Debian/Ubuntu
   sudo dnf install -y git                       # Fedora
   sudo yum install -y git                       # CentOS/RHEL
   ```

3. Run the setup command above.

---

## Manual Setup

If you prefer to do everything step by step (installing Docker, cloning, configuring, verifying), follow the full guide:

**[Manual Setup Guide →](MANUAL_SETUP.md)**

It covers every step from scratch — installing git, Docker, configuring environment variables, pulling images, starting services, connecting your editor, and verifying everything works. Written for people who've never used Docker before.

**Quick version** (if you already have Docker running):

```bash
git clone https://github.com/montycloud/mc-vision-ui-mcp-setup.git ~/vision-ui-mcp
cd ~/vision-ui-mcp
cp .env.example .env
# Edit .env — fill in GIT_TOKEN and OPENAI_API_KEY
echo YOUR_TOKEN | docker login ghcr.io -u YOUR_USERNAME --password-stdin
docker compose up -d
# Wait 3-5 minutes, then verify:
docker compose ps
```

---

## Connect Your AI Tool

Once the server is running, add the MCP config to your editor.

### VS Code / GitHub Copilot / Cursor

Create `.vscode/mcp.json` in your project root:

```json
{
  "servers": {
    "vision-ui": {
      "type": "http",
      "url": "http://localhost:8080/mcp"
    }
  }
}
```

Then reload: `Cmd+Shift+P` (Mac) or `Ctrl+Shift+P` (Windows/Linux) → "Reload Window".

### Claude Code

Add to `.claude/settings.json`:

```json
{
  "mcpServers": {
    "vision-ui": {
      "type": "http",
      "url": "http://localhost:8080/mcp"
    }
  }
}
```

### Verify It Works

In Copilot Chat or Claude Code, try: **"Search for Button component"** — you should get results from the Vision UI library.

---

## What You Get

| Tool | What It Does |
|------|-------------|
| `get_conventions` | Coding standards, naming rules, known inconsistencies — call first before generating code |
| `search` | Semantic search across component metadata and source code |
| `get_component` | Full component details — props, variants, examples, usage, source (includes conventions) |
| `get_source` | Complete source code of any file from either repo |
| `list_components` | All components grouped by category |

---

## Day-to-Day Commands

```bash
cd ~/vision-ui-mcp

docker compose up -d        # Start the server
docker compose down          # Stop the server
docker compose logs -f       # Watch logs in real time
docker compose ps            # Check service status
```

---

## Updating

When the team pushes new MCP server images:

```bash
cd ~/vision-ui-mcp
docker compose pull
docker compose up -d
```

If the team announces a **schema change** (check release notes):

```bash
cd ~/vision-ui-mcp
docker compose pull
docker compose down -v       # ⚠ Removes database — re-indexing will happen on next start
docker compose up -d
```

---

## Uninstalling

```bash
cd ~/vision-ui-mcp
docker compose down -v
cd ~ && rm -rf ~/vision-ui-mcp
```

---

## Troubleshooting

### First startup is slow (3–5 minutes)

This is normal. On the first run, the server clones the component repos and generates vector embeddings for semantic search. Watch progress with `docker compose logs -f`. Subsequent starts take seconds.

### "Cannot connect to the Docker daemon"

Docker Desktop isn't running. Open it from your Applications (Mac), Start menu (Windows), or start the service on Linux:

```bash
sudo systemctl start docker
```

### Port 8080 already in use

Another service is using port 8080. Change the port in your `.env` file:

```
MCP_PORT=9090
```

Then restart: `docker compose down && docker compose up -d`. Update the port in your MCP config too.

### Port 5432 already in use

You have a local PostgreSQL running. This usually doesn't matter — the containers communicate internally and don't need the host port. If you see errors, check that the `docker-compose.yml` does NOT expose postgres ports (it shouldn't by default).

### "denied: installation not allowed" or image pull fails

Your GitHub token may not have `read:packages` scope, or you're not logged into ghcr.io:

```bash
echo YOUR_GITHUB_TOKEN | docker login ghcr.io -u YOUR_GITHUB_USERNAME --password-stdin
```

Then retry: `docker compose pull`

### OpenAI rate limiting on first startup

The initial embedding generation sends many requests to OpenAI. If you see rate limit errors in the logs, wait a minute — the server retries automatically. This only happens once during initial indexing.

### "no configuration file provided: not found"

You're running `docker compose` from the wrong directory. Make sure you're in `~/vision-ui-mcp/`:

```bash
cd ~/vision-ui-mcp
docker compose up -d
```

### MCP server shows as "unhealthy"

Check the logs for details:

```bash
docker compose logs mcp-server
```

Common causes: the indexer hasn't finished yet (wait for it), OpenAI API key is invalid, or the database connection failed. If the indexer is still running, wait for it to complete — the MCP server depends on it.

### Windows: "command not found" when running curl

You're likely in PowerShell instead of WSL2 or Git Bash. Open Ubuntu (from Start menu) or Git Bash and run the command there.

### Docker is very slow or containers keep restarting

Increase Docker's memory allocation: Docker Desktop → Settings → Resources → set Memory to at least 4GB. On M1/M2 Macs, the default is usually fine.

---

## System Requirements

| Requirement | Minimum |
|------------|---------|
| Docker | v20.10+ |
| Docker Compose | v2.0+ |
| Disk space | 10 GB free |
| RAM | 4 GB |
| Ports | 8080 (configurable) |

Supported platforms: macOS (Apple Silicon + Intel), Linux (x64 + ARM64), Windows (WSL2 + Git Bash).
