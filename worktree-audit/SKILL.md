---
name: worktree-audit
description: Audit a project for readiness to run many parallel agent sessions in git worktrees — branch discipline in agent docs, automated worktree setup/teardown, per-worktree databases, per-worktree ports, throttled heavy checks (heavy), shared dependency caches. Use when the user asks to check/audit a repo for worktrees, parallel agents, "проверь проект на worktree", or before running worktree-setup. Read-only.
---

# Worktree audit

Checks a project against six rules for painless parallel work in git worktrees.
Read-only: never modifies the project. To fix findings, use the `worktree-setup` skill.

## The rules

| id | Rule | Why |
|----|------|-----|
| `branches` | Agent docs (CLAUDE.md / AGENTS.md) say: work only in worktrees, never `git checkout`/`switch` in a shared checkout | One agent switching branches breaks every other session in that directory |
| `lifecycle` | One command prepares a fresh worktree (deps, `.env`, DB, ports) and one cleans it up; agent docs say to run them on create and after the PR is sent | A raw worktree is just files — it won't start or pass tests |
| `database` | Each worktree gets its own **database** (name derived from the worktree) inside **one shared DBMS** | Shared DB → migrations from different branches collide. One DBMS per worktree → RAM exhaustion |
| `ports` | App, tests and dev services pick free ports per worktree (and per-worktree domains if DNS is used) | Two worktrees can't both bind :3000 |
| `heavy` | Tests, linters, typecheckers, builds run through a machine-wide semaphore (`heavy -- <cmd>`) | Five parallel `tsc`/`pytest` runs freeze the machine |
| `caches` | Package managers share artifacts outside the worktree (pnpm, uv, bun, sccache, go cache) | npm/pip venv per worktree eats disk fast |

## Process

1. Run the script from the project root (it is fast and read-only):
   ```bash
   bash ~/.claude/skills/worktree-audit/scripts/audit.sh <project_dir>
   ```
   Lines are `OK|WARN|FAIL|INFO <rule-id> <message>`.
2. The script is heuristic. Verify every FAIL/WARN by reading the actual files before reporting — e.g. a DB name may be built in app config rather than `.env`, ports may be read from env with a fallback, setup may live in `bin/setup`. Downgrade false positives; also look for problems the script can't see:
   - app config that hardcodes DB name / port despite env vars
   - test config (pytest, vitest, jest, rspec) using a fixed test DB name or port
   - `docker compose up` in setup with no pinned project name (spawns a DBMS per worktree)
   - global singletons: fixed Redis DB index, fixed queue names, fixed tmp/socket paths, fixed local domains
   - CI/hooks (pre-commit, lefthook, husky) that run heavy checks without `heavy`
3. Report as a table: rule → status → evidence (file:line) → concrete fix. Order by impact: `branches`, `database`, `ports`, `heavy`, `lifecycle`, `caches`.
4. End by offering to apply fixes with the `worktree-setup` skill (all, or selected rules).

## Notes

- Go's module and build caches are global by default — nothing to fix.
- `INFO context` lines show the detected stack and whether you are inside a linked worktree.
- Exit code = number of FAILs, so the script can also gate CI.
