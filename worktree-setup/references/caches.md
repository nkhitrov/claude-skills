# Shared dependency caches

Goal: N worktrees ≠ N full copies of dependencies. Prefer tools that keep a global store and hardlink/clone into each worktree.

| Stack | Bad | Good | Migration |
|-------|-----|------|-----------|
| Node | npm (`package-lock.json`), yarn classic | **pnpm** (content-addressable store, hardlinks), bun | `pnpm import` (converts lockfile) → delete `package-lock.json`/`node_modules` → `pnpm install`; add `"packageManager": "pnpm@<ver>"`; replace `npm run`/`npx` in scripts, CI, Dockerfile, docs. Watch for packages relying on hoisting: fix with `public-hoist-pattern` in `.npmrc` rather than `shamefully-hoist` |
| Python | pip + venv, poetry | **uv** (global cache, hardlink/clone into `.venv`) | `uv init --bare` / `uv add -r requirements.txt` or convert poetry deps to `[project]`; `uv sync`; keep `.venv` per worktree (cheap, links) |
| Rust | own `target/` per worktree (GBs) | **sccache** (`RUSTC_WRAPPER=sccache`) | Do NOT share one `CARGO_TARGET_DIR` across worktrees — cargo's lock serialises builds and branches thrash each other's artifacts |
| Go | — | global module + build cache by default | nothing |
| Ruby | `BUNDLE_PATH=vendor/bundle` | default gem dir / shared `BUNDLE_PATH` outside repo | remove per-project `BUNDLE_PATH` |
| JVM | — | `~/.gradle`, `~/.m2` global by default | enable Gradle build cache if builds are slow |
| Docker | image per worktree | build once, tag by commit; share BuildKit cache | — |

Also check:
- Tool caches inside the repo that could live outside: `.pytest_cache`, `.mypy_cache`, `.turbo`, `.next/cache` — fine per worktree unless huge; turbo/nx support remote/shared cache dirs.
- Volume of existing worktrees: `du -sh $(git worktree list | awk '{print $1}')` — show the user before/after if they care about disk.

Package-manager migration is a visible change for the whole team — always confirm with the user before doing it.
