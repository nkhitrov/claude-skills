---
name: worktree-setup
description: Configure or fix a project so many parallel agent sessions can work in git worktrees — add worktree rules to CLAUDE.md/AGENTS.md (no branch switching), automate worktree setup/teardown (bin/wt + make targets), per-worktree databases in one shared DBMS, free-port allocation per worktree, wrap tests/linters with `heavy`, switch to shared-cache package managers (pnpm, uv). Use when the user asks to set up/fix/prepare a repo for worktrees or parallel agents, "настрой проект под worktree", or after worktree-audit reported problems.
---

# Worktree setup

Brings a project in line with the six worktree rules (see the `worktree-audit` skill for the rule table).

## Process

1. **Audit first.** Run `bash ~/.claude/skills/worktree-audit/scripts/audit.sh .` and verify findings by reading the files. Skip rules that already pass.
2. **Plan with the user.** List what you will change per rule and ask about anything that is a real decision: migrating npm → pnpm, the DB admin URL, which env vars hold ports, task runner (make / just / package.json scripts — use the one the project already has). Do not install global tools (`heavy`, `pnpm`, `uv`) without asking.
3. **Apply rules in this order**, each with its reference — read it only when you get to that rule:
   1. `lifecycle` + `database` + `ports` — one script does all three: [references/lifecycle.md](references/lifecycle.md), [references/database.md](references/database.md), [references/ports.md](references/ports.md). Start from the template `templates/wt`.
   2. `heavy` — [references/heavy.md](references/heavy.md)
   3. `caches` — [references/caches.md](references/caches.md)
   4. `branches` — last, because the agent-docs section must name the commands created above: [references/agent-docs.md](references/agent-docs.md)
4. **Verify for real**, not just by re-reading:
   - create a scratch worktree: `git worktree add ../<repo>-wt-check -b wt-check`
   - run the setup command there; start the app/tests and confirm they use their own DB and ports while the main checkout's app runs on its own
   - run the teardown command; confirm the DB is dropped, then `git worktree remove ../<repo>-wt-check && git branch -D wt-check`
   - re-run the audit; report remaining WARN/FAIL with reasons
5. Summarise changes per rule. Don't commit unless asked.

## Principles

- **Databases, not DBMSs.** One Postgres/MySQL/Redis server for all worktrees; each worktree gets its own database (or Redis DB index / key prefix). Never start a DB container per worktree.
- **Deterministic names.** Everything per-worktree (DB name, ports, compose services, domains) derives from the worktree directory name and is persisted in a gitignored `.env.worktree`, so restarts are stable.
- **Main checkout keeps its current values** (`myapp_dev`, port 3000) — only linked worktrees get derived ones. Don't break the user's existing workflow.
- **Idempotent.** Running setup twice is safe; teardown never touches the main checkout's DB.
- Match the project's conventions (task runner, script location, language of docs).
