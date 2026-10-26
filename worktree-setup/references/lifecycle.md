# Lifecycle: setup on create, teardown on PR

A fresh `git worktree add` contains tracked files only: no `node_modules`, no `.venv`, no `.env`, no DB.

## What setup must do (idempotent)

1. `.env` from `.env.example` (or copy gitignored files from the main checkout — see `.worktreeinclude` below)
2. write `.env.worktree`: `WT_NAME`, `DB_NAME`, one free port per port variable
3. install deps (with a shared-cache manager — see caches.md)
4. create the worktree's database in the shared DBMS, run migrations (+ seeds if the project has them)
5. print the resulting env so the agent sees its ports

## What teardown must do

1. stop processes started from this worktree (dev server, compose services scoped to it)
2. drop the worktree's database (never the main one)
3. remove `.env.worktree`
4. optionally `git worktree remove` — only if the agent is not running inside it

"Done" = the PR is sent. Agent docs must say: after `gh pr create` succeeds, run teardown.

## Implementation

- Copy `~/.claude/skills/worktree-setup/templates/wt` to `bin/wt` (or `scripts/wt`), `chmod +x`, fill the CONFIG block and the `install_deps` / `migrate` hooks.
- Add `.env.worktree` to `.gitignore`.
- Expose it through the project's task runner:

```make
wt-setup:    ## prepare this worktree: deps, .env, own DB, own ports
	bin/wt setup
wt-teardown: ## drop this worktree's DB and generated env
	bin/wt teardown
```

  or `"wt:setup": "bin/wt setup"` in package.json, or `just` recipes.
- Make the app load `.env.worktree` **after** `.env` so its values win. Examples:
  - dotenv (node): `dotenv -e .env -e .env.worktree --override` or `dotenv.config({ path: ['.env.worktree', '.env'] })` (first wins)
  - Make: `-include .env.worktree` + `export`
  - python-dotenv / pydantic-settings: `env_file=(".env", ".env.worktree")` (later wins)
  - docker compose: `--env-file .env --env-file .env.worktree`
  - direnv: `dotenv_if_exists .env.worktree` in `.envrc`

## Claude Code hooks (optional, if the user runs Claude Code)

- `.worktreeinclude` in repo root (gitignore syntax) lists gitignored files Claude Code copies into worktrees it creates — e.g. `.env`, `.env.local`.
- Settings `hooks.WorktreeCreate` / `WorktreeRemove` can call `bin/wt setup` / `bin/wt teardown`. Check current Claude Code docs for the exact hook contract before configuring (claude-code-guide agent).
