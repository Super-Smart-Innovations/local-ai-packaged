# local-ai-packaged Primer

This primer summarizes the **local-ai-packaged** repository and the reference deployment environment so that future workflows (including `/primer` and `/create-plan`) can plan changes across Docker, networking, and infrastructure consistently.

## Project Overview

- Compose-driven stack bundling:
  - n8n (workflow automation)
  - Supabase (database/auth/vector store)
  - Ollama (LLM runtime)
  - Open WebUI (chat UI)
  - Flowise (low-code AI agent builder)
  - Qdrant (vector database)
  - Neo4j (graph database)
  - SearXNG (metasearch engine)
  - Langfuse (LLM observability)
  - Caddy (reverse proxy + TLS)
- `start_services.py` orchestrates Supabase + AI services, handles env propagation, SearXNG secret, and profile/environment overrides.
- Root `.env` defines secrets and hostname configuration for Caddy.
- Supabase lives under `supabase/` and is pulled in via `include` from `docker-compose.yml`.

## Reference Deployment Environment & Topology

The current "hardened" production-like environment is:

```text
Internet
  → UniFi UDM Pro SE (public IP, WAN firewall)
    → Port forwards: 80/tcp, 443/tcp → Windows 11 host (LAN IP)
      → Windows 11 + WSL2
        → Docker Desktop
          → local-ai-packaged Docker network
            → Caddy container (ports 80/443)
              → Internal services (n8n, Supabase, Ollama, Open WebUI, Flowise, Qdrant, Neo4j, SearXNG, Langfuse, etc.)
```

Key points:

- **Router layer (UDM Pro SE)**
  - Owns the public IP on WAN.
  - Forwards **port 80 and 443** to the **Windows 11 host** that runs Docker Desktop.
  - Each WAN port (e.g. 443) can be forwarded to **only one LAN IP** at a time; ensure no competing port-forward rules.

- **Host OS layer (Windows 11)**
  - Runs **WSL2 + Docker Desktop**.
  - Docker publishes Caddy on host ports **80 and 443**, which are the same ports forwarded from the UDM.
  - Windows Firewall must allow inbound 80/443 so the forwarded traffic can reach Docker.

- **Container layer (Docker / WSL2)**
  - `docker-compose.yml` exposes most services only on the **internal Docker network** (using `expose:`) and **does not publish** their ports directly.
  - **Only the `caddy` service publishes ports to the host**:
    - `80:80/tcp`
    - `443:443/tcp`
  - Ollama containers (`ollama-cpu`, `ollama-gpu`, `ollama-gpu-amd`) are reachable as `http://ollama:11434` **only from within the Docker network**.

- **Entry point (Caddy)**
  - Caddy terminates TLS for all external services and reverse-proxies to internal containers.
  - Hostnames are controlled via environment variables (in `.env` and `supabase/docker/.env`), for example:
    - `N8N_HOSTNAME=n8n.yourdomain.com`
    - `WEBUI_HOSTNAME=openwebui.yourdomain.com`
    - `FLOWISE_HOSTNAME=flowise.yourdomain.com`
    - `SUPABASE_HOSTNAME=supabase.yourdomain.com`
    - `OLLAMA_HOSTNAME=ollama.yourdomain.com`
    - `SEARXNG_HOSTNAME=searxng.yourdomain.com`
    - `NEO4J_HOSTNAME=neo4j.yourdomain.com`
  - The `Caddyfile` uses these placeholders, e.g. for Ollama:

    ```caddy
    {$OLLAMA_HOSTNAME} {
        tls /etc/letsencrypt/live/supersmartinnovations.cloud/fullchain.pem \
            /etc/letsencrypt/live/supersmartinnovations.cloud/privkey.pem

        header {
            Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
            X-Content-Type-Options "nosniff"
            Referrer-Policy "strict-origin-when-cross-origin"
        }

        reverse_proxy ollama:11434
    }
    ```

  - TLS certificates are expected under `./letsencrypt` (mounted into `/etc/letsencrypt` in the Caddy container). If those files are missing, Caddy will fail to start and the container will restart.

## Access Patterns

### External clients (internet)

- All external traffic should go through Caddy on **HTTPS/443** using the configured hostnames.
- Examples:
  - Ollama API: `https://ollama.yourdomain.com`
  - n8n: `https://n8n.yourdomain.com`
  - Open WebUI: `https://openwebui.yourdomain.com`
- For Ollama clients and remote tools (including Archon or other services):
  - Use `https://ollama.yourdomain.com` as the base URL instead of `http://host.docker.internal:11434`.

### Internal clients (inside Docker network)

- Service-to-service communication remains on the Docker network using service names:
  - Ollama: `http://ollama:11434`
  - Qdrant: `http://qdrant:6333`
  - Supabase (database): `postgres://postgres:<password>@postgres:5432/postgres`
- This pattern is important for n8n workflows, Archon containers (if added to the network), and any internal debugging tools.

## Environment Modes (`start_services.py`)

- `--environment private` (default):
  - Designed for safe local environments; more ports may be exposed directly.

- `--environment public` (hardened / router-facing):
  - Used when the stack is reachable from the internet.
  - Closes all ports **except 80 and 443**, relying entirely on Caddy for ingress.
  - Assumes that:
    - UDM Pro SE forwards only 80/443 to the Windows host.
    - DNS A records for the configured hostnames point to the UDM’s public IP.
    - TLS certificates exist (or will be provisioned) under `./letsencrypt` for those hostnames.

## Planning Implications for `/create-plan`

When generating implementation or deployment plans:

- **Treat the reference deployment as multi-layered**:
  - Network (UDM Pro SE + WAN firewall + port forwards)
  - Host OS (Windows 11 + firewall rules)
  - Virtualization (WSL2 / Docker Desktop)
  - Orchestration (docker compose + `start_services.py` profiles/environments)
  - Ingress (Caddy + TLS + DNS)

- **Never plan to expose Docker services directly** on arbitrary host ports in the "public" profile. All external access should be described in terms of:
  - DNS hostnames configured in `.env` / `supabase/docker/.env`.
  - Caddy virtual hosts and reverse proxies.

- **For Ollama specifically**:
  - External: `https://ollama.yourdomain.com` via Caddy.
  - Internal: `http://ollama:11434` on the Docker network.
  - If adding new tools (e.g., Archon or other microservices) as containers, plan to attach them to the same Docker network and use the internal URL.

This environment description should be treated as canonical for future planning unless the user explicitly changes the network or hosting topology.
