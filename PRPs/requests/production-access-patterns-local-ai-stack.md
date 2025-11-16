# Implementation Plan: Production Access Patterns for local-ai-packaged Stack

## Overview

This plan defines **production-ready internet access patterns** for the full `local-ai-packaged` stack running in the following environment:

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

Only **Caddy** is exposed on host ports 80/443. All other services are reachable **only on the Docker network** via service names (e.g., `ollama:11434`, `qdrant:6333`).

The goal of this plan is to:

- Provide secure, HTTPS-based access to selected services (Ollama, Supabase, Open WebUI, n8n, etc.) over the internet.
- Keep low-level data services (Postgres, Qdrant, Redis/Valkey, Neo4j) **internal-only** or strongly restricted.
- Use **DNS hostnames + Caddy reverse proxy + TLS** as the only ingress path.
- Align with Supabase self-hosting guidance and Caddy/Docker best practices.

---

## Requirements Summary

- **R1: Single ingress layer**
  - All external traffic must enter through **Caddy** on ports 80/443; no direct exposure of container ports.

- **R2: Hostname-based routing**
  - Use the following environment variables and DNS hostnames:
    - `N8N_HOSTNAME=n8n.yourdomain.com`
    - `WEBUI_HOSTNAME=openwebui.yourdomain.com`
    - `FLOWISE_HOSTNAME=flowise.yourdomain.com`
    - `SUPABASE_HOSTNAME=supabase.yourdomain.com`
    - `OLLAMA_HOSTNAME=ollama.yourdomain.com`
    - `SEARXNG_HOSTNAME=searxng.yourdomain.com`
    - `NEO4J_HOSTNAME=neo4j.yourdomain.com`

- **R3: TLS / certificates**
  - Use **Lets Encrypt** for all public hostnames.
  - Certificates must be stored under `./letsencrypt` so that the Caddy container can load them from `/etc/letsencrypt`.

- **R4: Service-specific access policies**
  - **Public-ish UIs with auth** (internet accessible, but require login):
    - Open WebUI (`openwebui.yourdomain.com`)
    - n8n (`n8n.yourdomain.com`)
    - Supabase Studio / auth endpoints (`supabase.yourdomain.com`)
    - Langfuse (`langfuse.yourdomain.com`, if enabled)
  - **Restricted APIs** (exposed only as needed to specific clients):
    - Ollama API (`ollama.yourdomain.com`)
  - **Internal-only data services** (no direct internet exposure):
    - Postgres, Redis/Valkey, Qdrant, Neo4j core ports, Minio.

- **R5: Network & firewall alignment**
  - UDM Pro SE must:
    - Forward 80/443 **only** to the Windows 11 host running Docker.
    - Block all other inbound ports at WAN.
  - Windows Firewall must allow inbound 80/443 to Docker Desktop.

- **R6: Hardening & observability**
  - Enforce HTTPS-only (redirect 80 → 443 in Caddy).
  - Add standard security headers at Caddy.
  - Ensure n8n, Supabase, and Open WebUI are configured with strong credentials.
  - Enable central logging and simple monitoring for Caddy and key services.

---

## Research Findings

### Best Practices

- **Caddy as sole ingress:**
  - Official Caddy docs recommend routing all external traffic through a single Caddy instance exposing ports 80/443, with `reverse_proxy` to internal services.
  - Avoid HTTPS between Caddy and internal Docker services; use HTTP on the private network (lower complexity, still encrypted between client and Caddy).

- **HTTP → HTTPS redirects:**
  - Caddy is designed to automatically obtain certificates when configured with domain names; ensure DNS is correct and ports 80/443 reach Caddy.
  - Configure `redir` or global settings so that plain HTTP (80) is redirected to HTTPS (443).

- **Supabase self-hosting:**
  - Supabase self-hosting docs recommend exposing **Kong** / gateway on public ports with TLS, while keeping Postgres and internal services behind it.
  - Supabase JWT secrets and keys must be set correctly in `.env` and must be strong, unique values for production.

- **Home router constraints (UDM Pro SE):**
  - A given WAN port (e.g., 443) can only forward to a single LAN host.
  - For multiple services under one IP, use **virtual hosts behind a reverse proxy** (Caddy) instead of multiple port forwards.

### Reference Implementations

- **Caddy reverse proxy examples**
  - `example.com { reverse_proxy app:80 }` style patterns, with TLS automatically provisioned.
- **Docker + Caddy**
  - Official patterns use `caddy` as a service publishing `80:80` and `443:443`, with other services only `expose`d.

### Technology Decisions

- **Ingress:** Caddy v2 (already in repo) is the **single ingress gateway**.
- **TLS:** Lets Encrypt certificates stored under `./letsencrypt`, loaded by Caddy.
- **Reverse proxy routing:** Hostname-based routing defined in `Caddyfile` using `{$SERVICE_HOSTNAME}` placeholders.
- **Security boundary:**
  - WAN → UDM Pro → Caddy (TLS termination) → Docker network services.
  - No direct WAN access to containers.

---

## Implementation Tasks

### Phase 1: Foundation  Environment & DNS

1. **Confirm environment mode and profiles**
   - Description: Ensure the stack is running with `--environment public` and the desired profile (`cpu`, `gpu-nvidia`, or `gpu-amd`).
   - Files to modify/create: `.env`, `start_services.py` usage.
   - Dependencies: Working Docker Desktop, WSL2, and cloned repo.
   - Estimated effort: 0.5h.

2. **Align `.env` and `supabase/docker/.env` hostnames with DNS**
   - Description:
     - Set `N8N_HOSTNAME`, `WEBUI_HOSTNAME`, `FLOWISE_HOSTNAME`, `SUPABASE_HOSTNAME`, `OLLAMA_HOSTNAME`, `SEARXNG_HOSTNAME`, `NEO4J_HOSTNAME`, and `LETSENCRYPT_EMAIL` to real domains and a valid email.
     - Ensure those domains have **A records** pointing to the UDM Pros public IP.
   - Files to modify/create:
     - `.env`
     - `supabase/docker/.env`
   - Dependencies:
     - Working DNS provider access.
   - Estimated effort: 1h.

3. **Verify UDM Pro SE port forwarding and firewall rules**
   - Description:
     - In UniFi UI, ensure only **TCP 80 and 443** are forwarded to the Windows 11 host running Docker.
     - Confirm no conflicting forwards for those ports.
     - Ensure WAN firewall rules allow 80/443 in.
   - Files to modify/create: none (router config only).
   - Dependencies: UniFi controller access.
   - Estimated effort: 1h.

4. **Check Windows Firewall and WSL/Docker networking**
   - Description:
     - Ensure inbound 80 and 443 are allowed on the Windows host for Docker.
     - Confirm that Docker Desktop is binding `0.0.0.0:80` and `0.0.0.0:443` for the `caddy` service when the stack is up.
   - Files to modify/create: none (OS network config).
   - Dependencies: Administrative access to Windows.
   - Estimated effort: 1h.

### Phase 2: Caddy & TLS Hardening

5. **Validate and, if necessary, adjust `Caddyfile` global options**
   - Description:
     - Review the global block in `Caddyfile` to ensure safe defaults:
       - `email {$LETSENCRYPT_EMAIL}` is set.
       - Consider enabling HTTP → HTTPS redirects if not already covered.
   - Files to modify/create: `Caddyfile`.
   - Dependencies: `.env` with `LETSENCRYPT_EMAIL` set.
   - Estimated effort: 0.5h.

6. **Ensure host-specific site blocks match `.env` hostnames**
   - Description:
     - Verify, for each service, that the `{$SERVICE_HOSTNAME}` block exists and the `reverse_proxy` backend matches the Docker service name and port.
     - Example (Ollama): `reverse_proxy ollama:11434`.
   - Files to modify/create: `Caddyfile`.
   - Dependencies: Docker service names in `docker-compose.yml`.
   - Estimated effort: 1h.

7. **Provision Lets Encrypt certificates into `./letsencrypt`**
   - Description:
     - Use project scripts (e.g., `phase4-certbot-certificate-generation.sh`) or a manual certbot run to request certificates for all configured hostnames.
     - Store the certificates under `./letsencrypt/live/<yourdomain>/` so that Caddy can read them.
   - Files to modify/create:
     - `./letsencrypt/**` (certs and keys).
   - Dependencies:
     - DNS A records already in place.
     - UDM Pro and Windows firewall forwarding 80/443 to Caddy.
   - Estimated effort: 1-2h.

8. **Confirm Caddy container stability and TLS loading**
   - Description:
     - Restart the stack with `--environment public`.
     - Inspect `docker compose ... logs caddy` to confirm Caddy starts without errors and new certificates are loaded.
   - Files to modify/create: none.
   - Dependencies: Steps 5-7.
   - Estimated effort: 0.5h.

9. **Enforce HTTP → HTTPS redirect behavior**
   - Description:
     - Ensure that visiting any `http://<service-hostname>` results in an automatic redirect to `https://<service-hostname>`.
     - If needed, add `redir` directives or rely on Caddys automatic HTTPS behavior.
   - Files to modify/create: `Caddyfile`.
   - Dependencies: Step 8.
   - Estimated effort: 0.5h.

10. **Apply security headers consistently at Caddy**
    - Description:
      - Confirm that each site block includes HSTS, X-Frame-Options, X-Content-Type-Options, Referrer-Policy, and any XSS protection headers.
      - Ensure the SearXNG-specific CSP and Permissions-Policy directives remain intact.
    - Files to modify/create: `Caddyfile`.
    - Dependencies: Existing headers already partially configured.
    - Estimated effort: 1h.

### Phase 3: Service-Specific Access Policies

11. **n8n (workflow automation) access pattern**
    - Description:
      - Expose n8n through `https://n8n.yourdomain.com` only.
      - Ensure `N8N_ENCRYPTION_KEY` and `N8N_USER_MANAGEMENT_JWT_SECRET` are set to strong values.
      - Confirm that sign-ups are restricted and that only intended admins can access the instance.
    - Files to modify/create:
      - `.env` (secrets).
      - `docker-compose.yml` (n8n service env, if adjustments needed).
    - Dependencies: Caddy TLS setup complete.
    - Estimated effort: 1-2h.

12. **Open WebUI access pattern**
    - Description:
      - Expose Open WebUI via `https://openwebui.yourdomain.com`.
      - Ensure user accounts are protected by strong passwords and any available 2FA options.
      - Decide whether external users should be able to reach Open WebUI or whether it should be restricted (e.g., via IP allowlists or VPN).
    - Files to modify/create:
      - `.env` (WEBUI_HOSTNAME).
      - `Caddyfile` (Open WebUI site block verification).
    - Dependencies: DNS and TLS.
    - Estimated effort: 1h.

13. **Ollama API exposure and client configuration**
    - Description:
      - Provide external access to Ollama via `https://ollama.yourdomain.com`.
      - Document recommended client settings:
        - External: `OLLAMA_HOST=https://ollama.yourdomain.com`.
        - Internal (containers): `http://ollama:11434`.
      - Consider introducing a simple authentication or IP restriction layer in front of the Ollama endpoint (e.g., API gateway in n8n, or auth middleware in a thin gateway service) if usage will be shared.
    - Files to modify/create:
      - `.env` (OLLAMA_HOSTNAME).
      - `Caddyfile` (Ollama block verification).
      - Optional: new gateway service or n8n workflow documentation.
    - Dependencies: Steps 5-9.
    - Estimated effort: 2-3h.

14. **Supabase public access pattern**
    - Description:
      - Ensure `SUPABASE_HOSTNAME` is configured and points to the Kong gateway (through Caddy) for Supabase APIs and Studio.
      - Confirm that Supabase JWT, ANON_KEY, and SERVICE_ROLE_KEY values are production-grade and consistent between root `.env` and `supabase/docker/.env`.
      - Verify which Supabase endpoints are externally reachable and document recommended usage (e.g., use Supabase client SDKs from frontends, not direct DB access).
    - Files to modify/create:
      - `.env`
      - `supabase/docker/.env`
      - `Caddyfile` (Supabase block).
    - Dependencies: Supabase stack healthy.
    - Estimated effort: 2-3h.

15. **Flowise exposure decision**
    - Description:
      - Decide whether Flowise should be reachable from the public internet or only internally.
      - If public, ensure it is routed via `https://flowise.yourdomain.com` and protected by authentication.
      - If internal only, keep it unexposed and access via VPN or SSH tunnels.
    - Files to modify/create:
      - `.env` (FLOWISE_HOSTNAME) and `Caddyfile` if exposed.
    - Dependencies: DNS, TLS.
    - Estimated effort: 1h.

16. **SearXNG access and safety**
    - Description:
      - If exposing SearXNG publicly via `https://searxng.yourdomain.com`, confirm its CSP and security headers, and ensure rate limiting / abuse considerations are documented.
      - Decide whether it should be a private tool only.
    - Files to modify/create:
      - `.env` (SEARXNG_HOSTNAME) and `Caddyfile`.
    - Dependencies: Caddy site block already exists.
    - Estimated effort: 1-2h.

17. **Langfuse access**
    - Description:
      - Decide whether Langfuse UI is exposed via `https://langfuse.yourdomain.com`.
      - Ensure credentials, encryption keys, and S3/Minio settings are aligned with production usage.
    - Files to modify/create:
      - `.env`
      - `docker-compose.yml` (Langfuse env, if needed).
      - `Caddyfile` (Langfuse block).
    - Dependencies: Langfuse stack healthy.
    - Estimated effort: 2h.

18. **Neo4j access control**
    - Description:
      - Determine if Neo4j browser/HTTP interface should be exposed (`https://neo4j.yourdomain.com`) or kept internal.
      - Given sensitivity, consider keeping it internal and using SSH/VPN to access.
    - Files to modify/create:
      - `.env` (NEO4J_HOSTNAME) and `Caddyfile`.
    - Dependencies: Neo4j running and stable.
    - Estimated effort: 1-2h.

### Phase 4: Internal-Only Services & Network Guardrails

19. **Enforce internal-only status for data stores**
    - Description:
      - Confirm that Postgres, Redis/Valkey, Qdrant, and Neo4j core ports are only `expose`d on the Docker network and not mapped to host ports in `docker-compose.yml`.
      - Document these internal-only endpoints for internal client usage.
    - Files to modify/create:
      - `docker-compose.yml`.
      - Documentation update in `docs/primer/local-ai-packaged-primer.md`.
    - Dependencies: Running stack.
    - Estimated effort: 1h.

20. **Document internal access patterns for containers**
    - Description:
      - For each service, record its internal URL for use by n8n, Archon containers (if added), and other internal tools:
        - Ollama: `http://ollama:11434`
        - Qdrant: `http://qdrant:6333`
        - Supabase Postgres: `postgres://postgres:<password>@postgres:5432/postgres`
        - Redis: `redis://redis:6379`
      - Keep these in the primer and any developer docs.
    - Files to modify/create:
      - `docs/primer/local-ai-packaged-primer.md`.
    - Dependencies: None beyond current documentation.
    - Estimated effort: 1h.

21. **Optional: introduce VPN or zero-trust access layer**
    - Description:
      - Consider adding a VPN (e.g., WireGuard, Tailscale) or a zero-trust access proxy in front of sensitive UIs (n8n, Neo4j, Flowise, SearXNG) instead of exposing them directly.
      - This can be noted as a future enhancement if not implemented immediately.
    - Files to modify/create:
      - Documentation only (e.g., `docs/ubuntu-docker-production-guide.md` and primer).
    - Dependencies: Router and OS capabilities.
    - Estimated effort: 2-4h (if implemented).

### Phase 5: Integration, Testing & Observability

22. **End-to-end connectivity tests from the internet**
    - Description:
      - For each exposed hostname, verify:
        - DNS resolution (e.g., `nslookup n8n.yourdomain.com`).
        - HTTPS connectivity and valid certificates.
        - Correct routing to the intended service.
      - Confirm that non-exposed services are unreachable from the internet.
    - Files to modify/create: none.
    - Dependencies: All previous phases.
    - Estimated effort: 2h.

23. **Application-level tests for n8n, Supabase, Open WebUI, and Ollama**
    - Description:
      - Log into n8n via `https://n8n.yourdomain.com` and run a simple workflow that uses Ollama and Qdrant.
      - Use Supabase client SDK from a test script to connect via `https://supabase.yourdomain.com` and perform simple CRUD.
      - Access Open WebUI via `https://openwebui.yourdomain.com` and confirm it can call n8n/Ollama workflows.
    - Files to modify/create:
      - Optional test scripts or Postman collections.
    - Dependencies: Phase 3 tasks.
    - Estimated effort: 2-3h.

24. **Log aggregation and monitoring setup**
    - Description:
      - Ensure container logs for Caddy, n8n, Supabase, and Ollama are persisted and rotated.
      - Optionally integrate with Langfuse for LLM telemetry and add simple alerts for Caddy failures.
    - Files to modify/create:
      - `docker-compose.yml` (logging options, already partially configured).
      - Documentation of how to view logs.
    - Dependencies: Stack running stably.
    - Estimated effort: 2h.

25. **Security review and checklist**
    - Description:
      - Verify that:
        - No non-essential ports are exposed on WAN.
        - Caddy only listens on 80/443 and proxies to internal HTTP.
        - All public UIs require authentication with strong credentials.
        - Secrets in `.env` and `supabase/docker/.env` are strong and not committed.
      - Document residual risks and future enhancements.
    - Files to modify/create:
      - Security checklist section in this plan and/or `docs/primer/local-ai-packaged-primer.md`.
    - Dependencies: All earlier phases.
    - Estimated effort: 2h.

---

## Codebase Integration Points

### Files to Modify

- `docker-compose.yml`
  - Confirm internal-only `expose` vs `ports` for all services.
  - Validate `caddy` service ports and environment variables for hostnames.
- `Caddyfile`
  - Ensure site blocks exist for each hostname with appropriate `reverse_proxy` targets.
  - Configure HTTPS-only behavior and security headers.
- `.env`
  - Set hostnames (`N8N_HOSTNAME`, `WEBUI_HOSTNAME`, etc.), secrets (n8n, Supabase, Langfuse), and `LETSENCRYPT_EMAIL`.
- `supabase/docker/.env`
  - Align Supabase-specific hostnames and JWT/DB settings with root `.env`.
- `docs/primer/local-ai-packaged-primer.md`
  - Update primer with final access patterns (external vs internal) and URLs.
- `docs/ubuntu-docker-production-guide.md`
  - Optionally extend with UDM Pro → Windows → Docker → Caddy-specific guidance.

### New Files to Create

- Optional:
  - `docs/access-patterns-production.md` — consolidated summary of public endpoints, internal endpoints, and recommended client configuration.
  - Test scripts or collections for API verification (e.g., `tests/api/access-smoke-tests.http`).

### Existing Patterns to Follow

- Use service names on the Docker network (`ollama`, `qdrant`, `postgres`, `redis`, `langfuse-web`, etc.).
- Central ingress via Caddy, similar to existing SearXNG and n8n blocks.
- Supabase self-hosting model where Postgres and other internals are not publicly exposed.

---

## Technical Design

### Architecture Diagram

```text
[Internet Clients]
      |
      v
[UDM Pro SE]
  - WAN firewall & NAT
  - Port forwards: 80, 443 → Windows 11 host
      |
      v
[Windows 11 Host]
  - Windows Firewall allows 80/443
  - WSL2 + Docker Desktop
      |
      v
[Docker Network: local-ai-packaged]
  ├─ caddy (80/443 published)
  │    ├─ n8n.yourdomain.com     → n8n:5678
  │    ├─ openwebui.yourdomain.com → open-webui:8080
  │    ├─ flowise.yourdomain.com → flowise:3001 (optional)
  │    ├─ supabase.yourdomain.com → kong:8000 (via Supabase stack)
  │    ├─ ollama.yourdomain.com  → ollama:11434
  │    ├─ searxng.yourdomain.com → searxng:8080
  │    ├─ langfuse.yourdomain.com → langfuse-web:3000
  │    └─ neo4j.yourdomain.com   → neo4j:7474 (optional)
  ├─ n8n
  ├─ open-webui
  ├─ flowise
  ├─ supabase stack (db, kong, auth, etc.)
  ├─ ollama
  ├─ qdrant
  ├─ redis/valkey
  ├─ neo4j
  ├─ searxng
  └─ langfuse (web, worker, clickhouse, postgres, minio)
```

### Data Flow

- **User → n8n/Open WebUI**
  - Client connects via HTTPS to Caddy using service hostname.
  - Caddy terminates TLS and forwards HTTP to `n8n` or `open-webui` containers.
  - n8n workflows call internal services:
    - Ollama via `http://ollama:11434`.
    - Qdrant via `http://qdrant:6333`.
    - Supabase via internal or external endpoints depending on design.

- **User → Supabase**
  - Frontend or API clients connect via `https://supabase.yourdomain.com`.
  - Caddy proxies to the Supabase gateway (Kong) on the Docker network.
  - Kong routes to internal Supabase components.

- **User → Ollama directly**
  - If allowed, clients (e.g., local CLI, Archon in another environment) call `https://ollama.yourdomain.com`.
  - Caddy proxies to `ollama:11434` on Docker network.

---

## Dependencies and Libraries

- **Caddy v2** (reverse proxy, TLS termination).
- **Docker & Docker Compose** (already in use).
- **Supabase self-hosting stack** (via `supabase/docker` include).
- **Lets Encrypt certificates** (via certbot or Caddy automatic management, depending on final approach).
- Optional VPN / zero-trust tools (WireGuard, Tailscale, etc.) for securing sensitive management UIs.

---

## Testing Strategy

- **DNS & routing tests**
  - For each hostname, confirm DNS resolution and connectivity from external networks.
- **TLS tests**
  - Use `curl -v https://service.yourdomain.com` and online SSL checkers to validate certificates.
- **Application smoke tests**
  - n8n: log in and run a workflow using Ollama and Qdrant.
  - Supabase: run sample CRUD operations over HTTPS.
  - Open WebUI: send prompts that go through n8n workflows.
- **Security posture checks**
  - Nmap or similar scanner from the internet-facing side to verify only 80/443 are open.
  - Confirm non-exposed ports are not reachable externally.

---

## Success Criteria

- [ ] Only ports 80 and 443 are exposed on the public IP (no other open ports on WAN).
- [ ] Caddy starts cleanly, serves valid HTTPS certificates for all configured hostnames.
- [ ] n8n, Open WebUI, Supabase, and (optionally) Langfuse are reachable only via HTTPS and require authentication.
- [ ] Ollama is reachable at `https://ollama.yourdomain.com` for approved external clients and at `http://ollama:11434` internally.
- [ ] Postgres, Redis/Valkey, Qdrant, and Neo4j core ports are not reachable from the internet.
- [ ] Documentation (primer + this plan) accurately describes all external and internal endpoints.

---

## Notes and Considerations

- This plan assumes a **single public IP** and one UDM Pro SE acting as the router/firewall.
- DNS, TLS, and UniFi configuration steps may need minor adaptation depending on your exact domain registrar and UniFi firmware.
- For high-security use cases, consider adding:
  - VPN-only or zero-trust access to sensitive admin UIs (n8n, Neo4j, Flowise, SearXNG).
  - Rate limiting and WAF-like protections in front of Caddy or via an additional gateway.
- All secrets in `.env` and `supabase/docker/.env` must be treated as sensitive, stored securely, and never committed or shared.

---
*This plan is ready for execution with `/execute-plan PRPs/requests/production-access-patterns-local-ai-stack.md`.*
