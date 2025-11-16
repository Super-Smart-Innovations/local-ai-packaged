# AGENTS.md

This file provides guidance to agents when working with code in this repository.

## Project Stack

- **Language**: Python (startup scripts), YAML (configuration), Docker (containerization)
- **Frameworks**: n8n (workflow automation), Supabase (database/auth), Open WebUI (chat interface)
- **Services**: Docker Compose with multiple containers (n8n, Supabase, Ollama, Qdrant, Neo4j, Langfuse, etc.)
- **Build Tools**: Docker Compose, Python scripts for orchestration

## Commands

### Startup

```bash
# Start services with specific GPU profile
python start_services.py --profile gpu-nvidia  # Nvidia GPU
python start_services.py --profile gpu-amd     # AMD GPU
python start_services.py --profile cpu         # CPU only
python start_services.py --profile none        # Ollama only

# Start with environment override
python start_services.py --profile cpu --environment private  # Default
python start_services.py --profile cpu --environment public   # Production with closed ports
```

### Service Management

```bash
# Stop all services
docker compose -p localai -f docker-compose.yml --profile <profile> down

# Update and restart
docker compose -p localai -f docker-compose.yml --profile <profile> pull
python start_services.py --profile <profile>
```

### Service Access

- n8n: `http://localhost:5678/`
- Open WebUI: `http://localhost:3000/`
- Flowise: `http://localhost:3001/`
- Supabase Dashboard: `http://localhost:3000/` (after starting Supabase)
- Langfuse: `http://localhost:3000/`
- Neo4j Browser: `http://localhost:7474/`

## Critical Patterns

### Environment Setup

- **PostgreSQL Password Restrictions**: Cannot contain "@" character - will cause Supabase connection failures
- **Secret Generation**: Use `openssl rand -hex 32` for encryption keys and tokens
- **POOLED_DB_POOL_SIZE**: Must be set to "5" for current Supabase version compatibility

### Docker Configuration

- **SearXNG First Run**: `cap_drop: - ALL` directive must be temporarily commented out during initial startup to allow uwsgi.ini creation
- **Host Gateway Access**: All services use `extra_hosts: - "host.docker.internal:host-gateway"` for cross-container communication
- **Volume Permissions**: SearXNG requires `chmod 755` on its directory for proper file access

### Service Dependencies

- **Supabase First**: Must start and initialize before other services
- **Ollama Models**: `qwen2.5:7b-instruct-q4_K_M` and `nomic-embed-text` are pre-configured for download
- **N8N Workflows**: Pre-loaded workflows in `n8n/backup/workflows/` are automatically imported

### Code Patterns

- **Error Handling**: Use try/catch blocks with proper exception handling (discovered in n8n_pipe.py)
- **Pydantic Models**: Use BaseModel with Field definitions for configuration (discovered in n8n_pipe.py)
- **Type Hints**: Use Optional, Callable, Awaitable from typing module
- **Async/Await**: Use async functions for event-driven operations

## Architecture Flow

```text
User Request → Open WebUI → n8n_pipe.py → N8N Workflow → Ollama (LLM) → Supabase/Qdrant (RAG) → Response
```

## Security Notes

- **Default Credentials**: All example credentials in `.env.example` must be changed for production
- **Port Exposure**: Private environment exposes all ports locally, public environment closes ports except 80/443
- **HTTPS**: Caddy handles SSL termination for custom domains (requires LETSENCRYPT_EMAIL)

## Common Issues

- **Supabase Pooler Restarting**: Follow GitHub issue #30210 for resolution
- **SearXNG Permissions**: Run `chmod 755 searxng` if container keeps restarting
- **GPU Support**: Requires specific Docker setup for Nvidia/AMD GPU passthrough
