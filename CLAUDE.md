# SwitchTail — lab instructions

> **Lab scope**: you are in the `switchtail` lab of the JangLabs workspace —
> its own git repo. This file is the authority inside `switchtail/`; it
> overrides the workspace root. Don't edit sibling labs from here.

SwitchTail is the **operator's switchboard for agentic terminals** — a Zellij
plugin (Rust → `wasm32-wasip1`, zellij-tile 0.44.x on a zellij 0.45 host).
Start with `README.md`, `docs/DESIGN.md` (the design contract and domain
vocabulary), and `docs/zellij-api-notes.md` (source-verified API facts — do
NOT trust training-data Zellij API names; when in doubt, read the vendored
crate source under `~/.cargo/registry/src/*/zellij-tile-*/`).

## The vocabulary is the domain language

Exchange (session) · board (tab) · line (pane) · seat (main position) · deck
(one-press key map) · patch (focus/swap/route) · trunk (N parallel lines) ·
call log / call (event feed) · ringing/answered/parked (triage) · operator
(the human). Use these names in types, functions, keys, docs, and commit
messages. New concepts should extend the metaphor before inventing new terms.

## Architecture invariant (the expandability seam)

- `crates/switchtail-core` — the pure model. **No zellij dependency, ever.**
  All host effects are `HostIntent` values returned by core operations.
  Everything decidable without a host is decided (and unit-tested) here.
- `crates/switchtail-plugin` — thin adapter only: zellij `Event` → core
  mutation; `HostIntent` → one shim call; render the core's view model.
  No business logic in the adapter. New capability = new intent + one
  dispatcher arm.
- **No-kill discipline**: no `close_*`/kill shim call sites in the adapter
  (a test greps for this). Declared permissions stay minimal — adding one is
  an owner decision.
- UI is CB-safe: never encode meaning red↔green (operator runs a daltonized
  theme); states use blue↔amber + lightness + a redundant text/shape cue.

## Build / test / verify

```bash
tools/dev.sh test     # cargo test (core + adapter units), capped jobs
tools/dev.sh build    # wasm32-wasip1 debug build of the plugin
tools/dev.sh reload   # build + start-or-reload-plugin into the live session
tests/e2e.sh          # headless zellij smoke (best-effort; needs a TTY via `script`)
```

- **Memory discipline (this box)**: always build via `tools/dev.sh` (it sets
  `CARGO_BUILD_JOBS=4`); `debug=0` is set in the workspace profile. Never run
  parallel cargo builds or agent fan-outs that compile concurrently.
- Gate for "done": `cargo test` green + wasm builds + (when UI-affecting)
  a reload smoke in a live/scripted session.
- Plugin panics: check `/tmp/zellij-<uid>/zellij-log/zellij.log`.

## History

This repo restarted 2026-06-12 (owner directive). The kitty-based v1 lives at
git tag `kitty-era-final` and `~/JangLabs/.archive/switchtail-kitty-era/`
(with RESTORE.md). Carried-over lessons: `docs/legacy-learnings.md`. Do not
resurrect kitty-era code paths from old memory — the architecture changed.

## Conventions

- Trunk-based on `main`; small atomic commits, conventional-commit style
  (`feat(core): …`, `feat(plugin): …`, `docs: …`, `test: …`).
- GSD planning lives in `.planning/` (fresh v0.1 milestone docs).
- Rust 2021, `cargo fmt` defaults, clippy-clean where cheap; tests live next
  to the code (`#[cfg(test)]`) for the core crate.
