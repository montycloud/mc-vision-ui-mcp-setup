# Vision UI MCP Server — Quick Setup

Connect the Vision UI component library to your AI coding tools (GitHub Copilot, Claude Code, Cursor).

## One-Command Setup

```bash
curl -fsSL https://raw.githubusercontent.com/montycloud/mc-vision-ui-mcp-setup/main/setup.sh | bash
```

This will:
1. Download all required files to `~/vision-ui-mcp/`
2. Prompt you for your GitHub token and OpenAI API key
3. Start the MCP server via Docker Compose

**Prerequisites:** Docker Desktop running, GitHub PAT with repo read access, OpenAI API key.

## Manual Setup

```bash
git clone https://github.com/montycloud/mc-vision-ui-mcp-setup.git ~/vision-ui-mcp
cd ~/vision-ui-mcp
cp .env.example .env
# Edit .env — fill in GIT_TOKEN and OPENAI_API_KEY
docker compose up -d
```

## Connect Your AI Tool

Add to your MCP configuration (`.vscode/mcp.json` or `.claude/settings.json`):

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

## Day-to-Day Commands

```bash
cd ~/vision-ui-mcp
docker compose up -d          # Start
docker compose down            # Stop
docker compose logs -f         # Watch logs
docker compose pull && docker compose up -d   # Update to latest
```

## What You Get

| Tool | Description |
|------|-------------|
| `search` | Semantic search across component metadata and source code |
| `get_component` | Full component details — props, variants, examples, usage, source |
| `get_source` | Complete file source from either repo |
| `list_components` | All components grouped by category |

## Upgrading

**Minor update** (bug fixes, no schema change):
```bash
cd ~/vision-ui-mcp && docker compose pull && docker compose restart mcp-server
```

**Major update** (schema change — check release notes):
```bash
cd ~/vision-ui-mcp && docker compose pull && docker compose down -v && docker compose up -d
```

## Troubleshooting

**First startup takes 3-5 minutes** — it clones repos and generates embeddings. Watch with `docker compose logs -f`.

**Port 5432 in use?** Remove the postgres `ports` section from `docker-compose.yml` — containers talk internally.

**Port 8080 in use?** Change `MCP_PORT` in `.env` and update your MCP client config.

**Can't pull images?** Run `echo $GIT_TOKEN | docker login ghcr.io -u token --password-stdin`
