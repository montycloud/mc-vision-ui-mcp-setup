# Manual Setup Guide

Step-by-step instructions for setting up the Vision UI MCP Server without the automated script. Follow every step in order — don't skip ahead.

---

## Step 1: Install Git

Check if you already have it:

```bash
git --version
```

If you see a version number, skip to Step 2.

**macOS:**
```bash
xcode-select --install
```
A popup will appear — click Install and wait for it to finish.

**Windows:**
Download and install [Git for Windows](https://git-scm.com/download/win). Use all default settings in the installer. After installing, open **Git Bash** (not PowerShell or CMD) for all remaining steps.

**Linux (Ubuntu/Debian):**
```bash
sudo apt update && sudo apt install -y git
```

**Linux (Fedora):**
```bash
sudo dnf install -y git
```

**Linux (CentOS/RHEL):**
```bash
sudo yum install -y git
```

**Verify:** Run `git --version` — you should see something like `git version 2.x.x`.

---

## Step 2: Install Docker

Check if you already have it:

```bash
docker --version
```

If you see version 20.10 or higher, skip to Step 3.

### macOS

1. Download [Docker Desktop for Mac](https://docs.docker.com/desktop/install/mac-install/).
   - Choose **Apple Silicon** if you have an M1/M2/M3/M4 Mac.
   - Choose **Intel** if you have an older Mac.
   - Not sure? Click the Apple logo (top-left) → About This Mac. If it says "Apple M1" (or M2/M3/M4), pick Apple Silicon.

2. Open the `.dmg` file, drag Docker to Applications.

3. Open **Docker Desktop** from Applications. A whale icon will appear in your menu bar — wait until it stops animating. This means Docker is ready.

Or install via Homebrew (if you have it):
```bash
brew install --cask docker
```
Then open Docker Desktop from Applications.

### Windows

1. **Install WSL2 first** — open PowerShell as Administrator:
   ```powershell
   wsl --install
   ```
   Restart your computer when prompted. This installs Ubuntu.

2. Download and install [Docker Desktop for Windows](https://docs.docker.com/desktop/install/windows-install/). Use default settings.

3. Open Docker Desktop. Go to **Settings → Resources → WSL Integration** → toggle on your Ubuntu distro.

4. Open **Ubuntu** from the Start menu (this is your terminal for all remaining steps).

### Linux (Ubuntu/Debian)

```bash
# Install Docker Engine
curl -fsSL https://get.docker.com | sh

# Allow your user to run Docker without sudo
sudo usermod -aG docker $USER

# Apply the group change (or log out and back in)
newgrp docker
```

### Linux (Fedora)

```bash
sudo dnf install -y dnf-plugins-core
sudo dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
sudo systemctl start docker
sudo systemctl enable docker
sudo usermod -aG docker $USER
newgrp docker
```

**Verify:** Run both:
```bash
docker --version         # Should show 20.10 or higher
docker compose version   # Should show v2.x.x
```

**Verify Docker is running:**
```bash
docker info
```
If this gives an error like "Cannot connect to the Docker daemon", open Docker Desktop (Mac/Windows) or run `sudo systemctl start docker` (Linux).

---

## Step 3: Check System Requirements

Before continuing, make sure your machine meets these minimums:

```bash
# Check disk space (need at least 10GB free)
df -h ~

# Check RAM (need at least 4GB)
# macOS:
sysctl -n hw.memsize | awk '{printf "%.0f GB\n", $1/1073741824}'
# Linux:
free -h
```

---

## Step 4: Clone the Setup Repo

```bash
git clone https://github.com/montycloud/mc-vision-ui-mcp-setup.git ~/vision-ui-mcp
cd ~/vision-ui-mcp
```

**What this does:** Downloads the Docker Compose configuration and helper files to `~/vision-ui-mcp/` in your home directory.

**Verify:**
```bash
ls ~/vision-ui-mcp/
```
You should see: `docker-compose.yml`, `.env.example`, `init.sql`, `setup.sh`, `docs/`, `README.md`, `MANUAL_SETUP.md`.

---

## Step 5: Create Your Environment File

```bash
cp .env.example .env
```

Now open the `.env` file in a text editor:

```bash
# macOS:
open -e .env

# Linux:
nano .env

# Windows (WSL):
nano .env
# Or if you have VS Code: code .env
```

Fill in these **required** values:

```
GIT_TOKEN=ghp_xxxxxxxxxxxxxx

# Choose ONE embedding provider:
# Option A: AWS Bedrock (recommended for MontyCloud team)
EMBEDDING_PROVIDER=bedrock
AWS_BEARER_TOKEN_BEDROCK=ABSK...
AWS_DEFAULT_REGION=us-east-1

# Option B: OpenAI
# EMBEDDING_PROVIDER=openai
# OPENAI_API_KEY=sk-xxxxxxxxxxxxxx
```

**Where to get these:**

1. **GitHub Personal Access Token (GIT_TOKEN)**
   - Go to [github.com/settings/tokens](https://github.com/settings/tokens)
   - Click "Generate new token (classic)"
   - Give it a name like "Vision UI MCP"
   - Select scopes: `repo` and `read:packages`
   - Click "Generate token" and copy it
   - If you don't have access to the montycloud org repos, ask Nitheish

2. **Embedding Provider Key** — choose one:
   - **AWS Bedrock API Key** (recommended)
     - Log into the AWS Console (via myapps.microsoft.com → AWS)
     - Go to Amazon Bedrock → API keys (left sidebar)
     - Click "Generate long-term API key"
     - Copy the key (starts with `ABSK...`)
     - Set `EMBEDDING_PROVIDER=bedrock` and `AWS_BEARER_TOKEN_BEDROCK=your_key` in `.env`
   - **OpenAI API Key**
     - Go to [platform.openai.com/api-keys](https://platform.openai.com/api-keys)
     - Click "Create new secret key" and copy it
     - Set `EMBEDDING_PROVIDER=openai` and `OPENAI_API_KEY=your_key` in `.env`

Save the file and close the editor. If using `nano`, press `Ctrl+O` to save, then `Ctrl+X` to exit.

**Do not change** the other values unless Nitheish tells you to. The defaults are correct.

**Verify:**
```bash
# Check that your token is filled in (not the placeholder value)
grep "GIT_TOKEN=" .env
grep "EMBEDDING_PROVIDER=" .env
```
You should see your actual token and chosen embedding provider.

---

## Step 6: Log Into GitHub Container Registry

The Docker images are hosted on GitHub's container registry (ghcr.io). You need to authenticate:

```bash
echo YOUR_GITHUB_TOKEN | docker login ghcr.io -u YOUR_GITHUB_USERNAME --password-stdin
```

Replace `YOUR_GITHUB_TOKEN` with your actual token and `YOUR_GITHUB_USERNAME` with your GitHub username.

**Example:**
```bash
echo ghp_abc123def456 | docker login ghcr.io -u johndoe --password-stdin
```

**Verify:** You should see `Login Succeeded`.

If it fails:
- Make sure your token has `read:packages` scope
- Make sure you're a member of the [montycloud](https://github.com/montycloud) GitHub org
- Ask Nitheish for help

---

## Step 7: Pull Docker Images

```bash
cd ~/vision-ui-mcp
docker compose pull
```

This downloads the container images. First time takes 2-5 minutes depending on your internet speed.

**Verify:** You should see all images pulled successfully, no errors.

**If it fails with "denied" or "unauthorized":**
- Go back to Step 6 and verify your ghcr.io login
- Make sure your GitHub token has `read:packages` scope
- Make sure you're in the montycloud org

---

## Step 8: Start the Stack

```bash
docker compose up -d
```

This starts 4 services in the background:
- **postgres** — stores component metadata and vector embeddings
- **indexer** — clones repos and extracts component information (runs once, then exits)
- **mcp-server** — the MCP endpoint your AI tools connect to
- **reindex-watcher** — polls for repo changes and re-indexes automatically

**Verify:**
```bash
docker compose ps
```

You should see:
- `postgres` → Running (healthy)
- `indexer` → Exited (0) — this is normal, it runs once and exits
- `mcp-server` → Running (starting or healthy)
- `reindex-watcher` → Running

---

## Step 9: Wait for Initial Indexing

The first startup takes **3-5 minutes**. During this time, the server is:
1. Cloning the Vision UI and MontyCloud repos
2. Extracting component metadata
3. Generating vector embeddings (via your configured provider)

Watch the progress:
```bash
docker compose logs -f
```

Press `Ctrl+C` to stop watching logs (this doesn't stop the services).

**When it's ready**, the MCP server healthcheck will pass:
```bash
docker compose ps
```

The `mcp-server` should show **healthy**.

**If you see rate limit errors** in the logs — don't worry. This happens during the initial embedding burst. The server retries automatically. Just wait a couple of minutes.

---

## Step 10: Configure Your AI Tool

Now connect your editor's AI assistant to the MCP server.

### VS Code / GitHub Copilot / Cursor

Create a file `.vscode/mcp.json` in your project root:

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

Then reload VS Code: `Cmd+Shift+P` (Mac) or `Ctrl+Shift+P` (Windows/Linux) → type "Reload Window" → press Enter.

### Claude Code

Add to your `.claude/settings.json`:

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

### Custom Port

If you changed `MCP_PORT` in your `.env` file (e.g., to 9090), update the URL accordingly: `http://localhost:9090/mcp`.

---

## Step 11: Verify Everything Works

In your AI tool (Copilot Chat, Claude Code, or Cursor), try this prompt:

> Search for Button component

You should get results from the Vision UI component library including component metadata, props, variants, and source code.

If you get no results or an error:
1. Check that the MCP server is healthy: `cd ~/vision-ui-mcp && docker compose ps`
2. Check the logs: `cd ~/vision-ui-mcp && docker compose logs mcp-server`
3. Make sure your editor is pointing to the right port

---

## Day-to-Day Usage

```bash
cd ~/vision-ui-mcp

# Start the server (e.g., beginning of your workday)
docker compose up -d

# Stop the server (e.g., end of your workday)
docker compose down

# Check service status
docker compose ps

# Watch logs in real time
docker compose logs -f

# Watch just the MCP server logs
docker compose logs -f mcp-server
```

You don't need to start Docker manually on Mac/Windows — Docker Desktop auto-starts when you log in (unless you disabled this).

---

## Updating

When Nitheish announces a new version:

**Standard update (most of the time):**
```bash
cd ~/vision-ui-mcp
docker compose pull
docker compose up -d
```

**Schema change update (Nitheish will tell you if this is needed):**
```bash
cd ~/vision-ui-mcp
docker compose pull
docker compose down -v    # Removes database — re-indexing happens on next start
docker compose up -d
```

---

## Uninstalling

```bash
cd ~/vision-ui-mcp
docker compose down -v
cd ~
rm -rf ~/vision-ui-mcp
```

This removes all containers, volumes (database), and local files. To also remove the Docker images:
```bash
docker rmi $(docker images "ghcr.io/montycloud/mc-vision-ui-mcp-server/*" -q) 2>/dev/null
```

---

## Troubleshooting

### "Cannot connect to the Docker daemon"

Docker Desktop isn't running. Open it from Applications (Mac), Start menu (Windows), or:
```bash
sudo systemctl start docker    # Linux only
```

### Port 8080 already in use

Another app is using port 8080. Change it in `.env`:
```
MCP_PORT=9090
```
Then restart and update your MCP config:
```bash
docker compose down && docker compose up -d
```

### "denied: installation not allowed" when pulling images

Your GitHub token doesn't have `read:packages` scope, or you're not logged into ghcr.io:
```bash
echo YOUR_GITHUB_TOKEN | docker login ghcr.io -u YOUR_GITHUB_USERNAME --password-stdin
```

### Containers keep restarting

Check memory — Docker Desktop defaults to 2GB which isn't enough:
- Docker Desktop → Settings → Resources → set Memory to **4GB or more**
- Restart Docker Desktop

### "no configuration file provided: not found"

You're in the wrong directory. Always `cd ~/vision-ui-mcp` before running `docker compose` commands.

### MCP server shows "unhealthy"

```bash
docker compose logs mcp-server
```
Check for:
- Invalid API key → check `OPENAI_API_KEY` or `AWS_BEARER_TOKEN_BEDROCK` in `.env`, then `docker compose down && docker compose up -d`
- Indexer still running → wait for it to finish
- Database connection error → check that postgres is healthy with `docker compose ps`

### Everything is stuck / nothing works

Nuclear option — start completely fresh:
```bash
cd ~/vision-ui-mcp
docker compose down -v
docker compose pull
docker compose up -d
```

Still stuck? Send Nitheish the output of:
```bash
docker compose ps
docker compose logs --tail=50
```
