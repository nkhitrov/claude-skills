# claude-skills

Personal [Claude Code](https://docs.claude.com/en/docs/claude-code) skills. This repo lives at `~/.claude/skills`, so every skill here is available in all projects.

## Install on a new machine

```bash
git clone git@github.com:nkhitrov/claude-skills.git ~/.claude/skills
```

## Skills

| Skill | What it does |
|-------|--------------|
| [worktree-audit](worktree-audit/SKILL.md) | Read-only check that a project is ready for parallel agents in git worktrees: branch discipline, setup/teardown, per-worktree DB and ports, `heavy`-throttled checks, shared caches |
| [worktree-setup](worktree-setup/SKILL.md) | Fixes what the audit found: `bin/wt` template, per-worktree DB in a shared DBMS, free ports, `heavy`, pnpm/uv, agent docs |
