#!/usr/bin/env bash
# Worktree-readiness audit. Read-only: prints findings, changes nothing.
# Usage: audit.sh [project_dir]
# Output lines: "<STATUS> <rule-id> <message>", STATUS = OK | WARN | FAIL | INFO
# Exit code: number of FAIL findings (capped at 100).

set -u
ROOT="${1:-.}"
cd "$ROOT" 2>/dev/null || { echo "FAIL setup cannot cd into $ROOT"; exit 1; }
ROOT="$(pwd)"

FAILS=0
ok()   { echo "OK   $1 $2"; }
warn() { echo "WARN $1 $2"; }
fail() { echo "FAIL $1 $2"; FAILS=$((FAILS + 1)); }
info() { echo "INFO $1 $2"; }
has()  { [ -e "$ROOT/$1" ]; }
# grep in existing files only, quiet; args: pattern file...
grepq() {
  local pat="$1"; shift
  local f found=1
  for f in "$@"; do
    [ -f "$f" ] && grep -Eqi -- "$pat" "$f" && found=0
  done
  return $found
}

echo "# worktree audit: $ROOT"

# ---------- context ----------
if git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  GITDIR="$(git -C "$ROOT" rev-parse --git-dir)"
  COMMON="$(git -C "$ROOT" rev-parse --git-common-dir)"
  if [ "$GITDIR" != "$COMMON" ]; then info context "running inside a linked worktree"; fi
  WT_COUNT="$(git -C "$ROOT" worktree list 2>/dev/null | wc -l | tr -d ' ')"
  info context "git worktrees registered: $WT_COUNT"
else
  fail context "not a git repository — worktrees need git; run 'git init' first"
  exit 1
fi

STACK=""
has package.json && STACK="$STACK node"
{ has pyproject.toml || has requirements.txt || has setup.py; } && STACK="$STACK python"
has Gemfile && STACK="$STACK ruby"
has go.mod && STACK="$STACK go"
has Cargo.toml && STACK="$STACK rust"
has composer.json && STACK="$STACK php"
{ has pom.xml || has build.gradle || has build.gradle.kts; } && STACK="$STACK jvm"
COMPOSE=""
for f in compose.yaml compose.yml docker-compose.yml docker-compose.yaml; do
  has "$f" && COMPOSE="$COMPOSE $ROOT/$f"
done
[ -n "$COMPOSE" ] && STACK="$STACK docker-compose"
info context "stack:${STACK:- unknown}"

AGENT_DOCS=""
for f in CLAUDE.md AGENTS.md .claude/CLAUDE.md GEMINI.md .cursorrules; do
  has "$f" && AGENT_DOCS="$AGENT_DOCS $ROOT/$f"
done
TASKFILES=""
for f in Makefile makefile GNUmakefile justfile Justfile Taskfile.yml Taskfile.yaml package.json mise.toml .mise.toml; do
  has "$f" && TASKFILES="$TASKFILES $ROOT/$f"
done
ENVFILES=""
for f in .env.example .env.sample .env.template .env.dist .env.development .env; do
  has "$f" && ENVFILES="$ENVFILES $ROOT/$f"
done

# ---------- 1. branches: agents must use worktrees, not checkout ----------
if [ -z "$AGENT_DOCS" ]; then
  fail branches "no agent docs (CLAUDE.md / AGENTS.md) — nothing tells agents to use worktrees"
else
  # shellcheck disable=SC2086
  if grepq 'worktree' $AGENT_DOCS; then
    ok branches "agent docs mention worktrees"
  else
    fail branches "agent docs never mention worktrees"
  fi
  # shellcheck disable=SC2086
  if grepq '(never|do not|don.t|нельзя|запрещ|не (переключ|использ)).{0,60}(checkout|switch|branch|ветк)' $AGENT_DOCS; then
    ok branches "agent docs forbid switching branches in the main checkout"
  else
    fail branches "agent docs do not forbid 'git checkout/switch' — parallel agents will jump branches"
  fi
fi

# ---------- 2. lifecycle: automated setup / teardown ----------
# shellcheck disable=SC2086
if [ -n "$TASKFILES" ] && grepq '(wt|worktree)[-_:]?(setup|init|up|create|bootstrap)|^(setup|bootstrap|init)[: ]|"(setup|bootstrap)"[[:space:]]*:' $TASKFILES; then
  ok lifecycle "setup/bootstrap command found in task runner"
else
  fail lifecycle "no automated setup command (e.g. 'make wt-setup') — a fresh worktree won't run"
fi
# shellcheck disable=SC2086
if [ -n "$TASKFILES" ] && grepq '(wt|worktree)[-_:]?(teardown|clean|down|destroy|remove)|^(teardown|clean)[: ]' $TASKFILES; then
  ok lifecycle "teardown/cleanup command found"
else
  fail lifecycle "no teardown command (drop DB, free ports, remove worktree) for when the PR is sent"
fi
# shellcheck disable=SC2086
if [ -z "$AGENT_DOCS" ]; then
  :
elif grepq '(wt|worktree)[-_:]?(setup|teardown|init|clean)|make (setup|bootstrap)' $AGENT_DOCS; then
  ok lifecycle "agent docs tell when to run setup/teardown"
else
  warn lifecycle "agent docs don't instruct agents to run setup on create and teardown on PR"
fi
if has .env.example || has .env.sample || has .env.template || has .env.dist; then
  ok lifecycle "env template present (.env.example or similar)"
elif has .env; then
  warn lifecycle ".env exists but no committed template — new worktrees get no .env"
fi
if has .worktreeinclude; then
  ok lifecycle ".worktreeinclude present (Claude Code copies listed gitignored files into new worktrees)"
fi

# ---------- 3. database: one DBMS, one database per worktree ----------
DB_USED=0
# shellcheck disable=SC2086
if grepq 'postgres|mysql|mariadb|mongo|DATABASE_URL|DB_NAME|POSTGRES_DB' $COMPOSE $ENVFILES; then DB_USED=1; fi
if [ "$DB_USED" = 1 ]; then
  # shellcheck disable=SC2086
  if grepq '(DB_NAME|POSTGRES_DB|DATABASE_URL|MYSQL_DATABASE)[^#]*(\$\{?(WT|WORKTREE)|_wt_|worktree)' $ENVFILES $TASKFILES $AGENT_DOCS \
     || grepq 'createdb|CREATE DATABASE|dropdb|DROP DATABASE' $TASKFILES $(ls "$ROOT"/bin/* "$ROOT"/scripts/* 2>/dev/null); then
    ok database "database name appears derived from the worktree / created per worktree"
  else
    fail database "database name is static — worktrees share one DB and fight over migrations"
  fi
  if [ -n "$COMPOSE" ]; then
    # shellcheck disable=SC2086
    if grep -Eq '^name:' $COMPOSE || grepq 'COMPOSE_PROJECT_NAME|(-p|--project-name)[ =]' $TASKFILES $ENVFILES; then
      ok database "compose project name is pinned — DB server can be shared across worktrees"
    else
      warn database "compose project name defaults to the directory name — each worktree starts its OWN DB server"
    fi
  fi
else
  info database "no database detected"
fi

# ---------- 4. ports ----------
HARD=0
if [ -n "$COMPOSE" ]; then
  # "5432:5432" or - 3000:3000 with literal host port
  # shellcheck disable=SC2086
  HP="$(grep -Eh '^[[:space:]]*-[[:space:]]*"?([0-9.]+:)?[0-9]{2,5}:[0-9]{2,5}' $COMPOSE | head -5 | tr -s ' ' | tr '\n' ';')"
  if [ -n "$HP" ]; then HARD=1; fail ports "hardcoded host ports in compose: $HP"; fi
fi
# shellcheck disable=SC2086
if grepq '(--port|-p)[ =][0-9]{4}|PORT=[0-9]{4}|localhost:[0-9]{4}' $TASKFILES; then
  HARD=1; fail ports "hardcoded ports in task runner / package.json scripts"
fi
# shellcheck disable=SC2086
if grepq '^[A-Z_]*PORT=[0-9]+' $ENVFILES; then
  # fine only if setup rewrites them
  # shellcheck disable=SC2086
  if grepq 'free.?port|find.?port|wt-ports|port.?offset|PORT_BASE' $TASKFILES $(ls "$ROOT"/bin/* "$ROOT"/scripts/* 2>/dev/null); then
    HARD=2; ok ports "env ports are static but a port allocator exists"
  else
    HARD=1; warn ports "ports are fixed in env files and nothing allocates free ports per worktree"
  fi
fi
[ "$HARD" = 0 ] && ok ports "no hardcoded ports found"

# ---------- 5. heavy checks go through a machine-wide lock ----------
if command -v heavy >/dev/null 2>&1; then
  ok heavy "'heavy' is installed ($(command -v heavy))"
else
  warn heavy "'heavy' is not installed (brew install mokevnin/tap/heavy)"
fi
# shellcheck disable=SC2086
if [ -n "$TASKFILES" ] && grepq 'heavy[[:space:]]+(--[a-z-]+[[:space:]=]+[^ ]+[[:space:]]+)*--' $TASKFILES; then
  ok heavy "test/lint commands are wrapped with 'heavy --'"
else
  fail heavy "tests/linters/typecheck run unthrottled — parallel worktrees will choke the machine"
fi

# ---------- 6. shared dependency caches ----------
case " $STACK " in *" node "*)
  if has pnpm-lock.yaml; then ok caches "pnpm (content-addressable store shared across worktrees)"
  elif has bun.lockb || has bun.lock; then ok caches "bun (global cache, hardlinks)"
  elif has package-lock.json; then fail caches "npm: every worktree gets a full node_modules copy — switch to pnpm"
  elif ! has yarn.lock; then warn caches "node: no lockfile (likely npm) — every worktree copies node_modules; use pnpm"
  elif has yarn.lock; then
    if grepq 'nodeLinker:[[:space:]]*pnpm|enableGlobalCache:[[:space:]]*true' "$ROOT/.yarnrc.yml"; then ok caches "yarn berry with global cache"
    else warn caches "yarn: check global cache / consider pnpm"; fi
  fi ;;
esac
case " $STACK " in *" python "*)
  if has uv.lock; then ok caches "uv (global cache with hardlinks/clones)"
  elif has poetry.lock; then warn caches "poetry: per-worktree venvs copy packages — consider uv"
  else warn caches "pip: per-worktree venvs duplicate packages — consider uv"; fi ;;
esac
case " $STACK " in *" rust "*)
  if [ -n "${RUSTC_WRAPPER:-}" ] || grepq 'sccache' "$HOME/.cargo/config.toml" "$ROOT/.cargo/config.toml"; then ok caches "sccache configured"
  else warn caches "rust: each worktree has its own target/ (GBs) — configure sccache"; fi ;;
esac
case " $STACK " in *" go "*) ok caches "go module + build caches are global by default" ;; esac
case " $STACK " in *" ruby "*)
  if grepq 'BUNDLE_PATH' "$ROOT/.bundle/config"; then warn caches "BUNDLE_PATH is per-project — gems duplicated per worktree"
  else ok caches "bundler installs to shared gem dir"; fi ;;
esac

echo "# summary: $FAILS FAIL"
[ "$FAILS" -gt 100 ] && FAILS=100
exit "$FAILS"
