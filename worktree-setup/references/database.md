# Database per worktree, one DBMS for all

## Goal

- One DB server (Postgres/MySQL/Mongo/Redis) shared by every worktree.
- Each linked worktree gets its own database `<project>_wt_<slug>`; the main checkout keeps its existing name.
- The test database is per worktree too (`<db>_test`), otherwise parallel test runs truncate each other's tables.

## Steps

1. Find where the DB name comes from: `DATABASE_URL`, `DB_NAME`, `POSTGRES_DB`, app config (`config/database.yml`, `settings.py`, `prisma/schema.prisma` → `env("DATABASE_URL")`, `drizzle.config.ts`, `knexfile`), test config (`conftest.py`, `vitest.setup`, `.env.test`). Make **all** of them read the env var; a fallback to the old name is fine for the main checkout.
2. If the URL embeds the name, build it from parts in `.env`: `DATABASE_URL=postgres://user:pass@localhost:5432/${DB_NAME}` (only if the loader expands variables — dotenv-expand, compose, direnv do; plain dotenv doesn't) — otherwise have `bin/wt` write the full `DATABASE_URL` into `.env.worktree`.
3. `bin/wt setup` creates the DB (`CREATE DATABASE`), `teardown` drops it (`DROP DATABASE ... WITH (FORCE)` on PG ≥ 13).
4. If the DB server runs via docker compose, make it **shared**:
   - Compose project name defaults to the directory name → every worktree would start its own Postgres container. Pin it: top-level `name: myapp-infra` in a separate `compose.infra.yml`, or `docker compose -p myapp-infra`.
   - Start it once (`make infra-up`), setup only checks it is reachable (`pg_isready`).
   - Its port can stay fixed (`5432`) — it is one shared service. Only per-worktree processes need allocated ports.
5. Other shared stores:
   - Redis: per-worktree DB index (0–15) or key prefix `WT_NAME:`; same for queue names (Celery, BullMQ, Sidekiq namespaces).
   - S3/minio: bucket or prefix per worktree.
   - Elasticsearch/OpenSearch: index prefix per worktree.

## Pitfalls

- Postgres DB names: lowercase, `[a-z0-9_]`, max 63 chars — the template's `slug` already truncates.
- Migrations tool may create the DB itself (Rails `db:prepare`, Prisma `migrate dev`) — then setup only exports `DATABASE_URL`.
- Don't let teardown drop by pattern; drop exactly the computed name.
