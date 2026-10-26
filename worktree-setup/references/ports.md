# Ports (and domains) per worktree

## Find every fixed port

- package.json scripts: `--port 3000`, `-p 5173`, `PORT=3000 node ...`
- framework configs: `vite.config.*` (`server.port`), `next dev -p`, `playwright.config.*` (`webServer.port`, `baseURL`), `cypress.config.*`, Django `runserver 8000`, `uvicorn --port`, Rails `config/puma.rb`, Procfile/Procfile.dev
- docker compose: `ports: - "3000:3000"` for app-level services
- tests hitting `localhost:<port>` directly; CORS/callback URLs in `.env`

## Fix

1. Each per-worktree process reads its port from an env var with the old value as fallback: `${APP_PORT:-3000}`, `port: Number(process.env.APP_PORT ?? 3000)`.
2. List those vars in `PORT_VARS` in `bin/wt`; it writes free ports into `.env.worktree`. Allocation: deterministic start from a hash of the worktree path, skip ports that are listening (`lsof`) or already claimed by another worktree's `.env.worktree`.
3. Derived URLs (`APP_URL`, `VITE_API_URL`, OAuth callback) must use the same var: have `bin/wt` write them too, or build them in config.
4. Compose services that are per worktree: `"${APP_PORT}:3000"` and per-worktree project name (`-p "${COMPOSE_PROJECT_BASE}-${WT_NAME}"`). Shared infra (DB) keeps a fixed port in its own compose project — see database.md.
5. Test runners that start a server (Playwright `webServer`, Cypress) must use the allocated port, or ask the OS for port 0 when the framework supports it.

## Domains

If the project uses local DNS (`*.localhost`, `*.test`, Caddy/Traefik, puma-dev): one subdomain per worktree, `<wt_name>.myapp.localhost` → its port. `*.localhost` resolves to 127.0.0.1 in browsers without config. Have `bin/wt setup` register the route (e.g. Caddy admin API or a generated Traefik file) and teardown remove it.
