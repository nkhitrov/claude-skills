# Agent docs: worktree rules

Add a section to the project's agent docs (CLAUDE.md, AGENTS.md — whichever exist; if both, put it in AGENTS.md and reference it from CLAUDE.md). Write it in the docs' existing language. Replace commands with the ones you actually created. Keep it short — agents read it every session.

```markdown
## Worktrees (parallel agents)

Several agents work on this repo at the same time.

- Never run `git checkout <branch>` / `git switch` / `git stash` in the main checkout or in someone else's worktree. Start every task in a new worktree:
  `git worktree add ../<repo>-<task> -b <task-branch>` and work only there.
- Right after creating a worktree: `make wt-setup` (deps, .env, own database, own ports). Ports and DB name are in `.env.worktree` — use them, don't hardcode 3000/5432.
- Run tests, linters and typechecks only via `make test` / `make lint` / `make typecheck` — they queue through `heavy` so parallel agents don't overload the machine. Never call the raw tools.
- Don't start your own database server or `docker compose up` for infra; the shared one is started by `make infra-up`.
- After the PR is created (`gh pr create` succeeded): `make wt-teardown`, then `git worktree remove <path>` from outside the worktree.
```

If the user runs Claude Code, its built-in worktree support (`claude --worktree`, the EnterWorktree tool, desktop app worktree sessions) also counts as "a new worktree" — the rule is about not switching branches in a shared directory, not about which command creates the worktree.
