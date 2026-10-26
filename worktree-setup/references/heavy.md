# Heavy checks through a machine-wide semaphore

[`heavy`](https://github.com/mokevnin/heavy) — counting semaphore over `flock` files in `$TMPDIR/heavy/<pool>`. Every process on the machine shares the slots, so parallel worktrees take turns instead of freezing the machine.

- install: `brew install mokevnin/tap/heavy` · `mise use -g github:mokevnin/heavy` · `cargo install heavy` (ask the user first)
- run: `heavy -- <cmd>`; status: `heavy --status`
- slots: `--slots N` / `HEAVY_SLOTS` (default: cores/4, min 1)
- pools: `--pool NAME` / `HEAVY_POOL` — separate queues, e.g. `test` vs `lint`
- `--timeout S` → exit 75 when waiting too long
- nested `heavy` in the same pool runs immediately (no deadlock), `CI` set → no queue
- crash-safe: a killed holder frees its slot

## What to wrap

Anything CPU/RAM-hungry an agent runs repeatedly: test suites, typecheck (`tsc`, `mypy`, `pyright`), linters (`eslint`, `golangci-lint`, `rubocop`), builds (`vite build`, `cargo build`, `go build ./...`), e2e browsers.
Don't wrap: dev servers / watchers (long-lived — they would hold a slot forever), quick formatters on single files.

## How

Wrap at the task-runner level so agents and humans get it automatically:

```make
HEAVY ?= $(shell command -v heavy >/dev/null 2>&1 && echo "heavy --")
test: ; $(HEAVY) pytest
lint: ; $(HEAVY) ruff check .
typecheck: ; $(HEAVY) mypy src
```

```json
"test": "heavy -- vitest run",
"lint": "heavy -- eslint .",
"typecheck": "heavy -- tsc --noEmit"
```

If `heavy` might be missing on some machines (teammates, CI images), use the Make fallback above or a tiny `bin/heavy-or-run` shim: `command -v heavy >/dev/null && exec heavy -- "$@" || exec "$@"`.

Also wrap the same commands in git hooks (lefthook/husky/pre-commit) — those run concurrently from many worktrees too.

Agent docs must say: run checks only via the task-runner commands (`make test`, `pnpm test`), never the raw tool.
