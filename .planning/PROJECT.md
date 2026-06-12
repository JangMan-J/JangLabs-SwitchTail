# SwitchTail

## What This Is

SwitchTail is a one-handed agent switchboard: each lab of a multi-repo workspace becomes a board of Claude Code lines, with a numpad deck for focus control, a Plasma 6 widget as launcher/introspector, and a deliberate park-to-resume lifecycle. This milestone replaces the kitty foundation entirely — SwitchTail is rebuilt as a large Zellij plugin (WASM, Rust via zellij-tile), with the `stail` CLI and its `--json` contract remaining the integration boundary for the widget and systemd surfaces.

## Core Value

The operator can route, watch, park, and resume a fleet of Claude Code sessions one-handed — and the daily-driver cockpit never breaks while its foundation is being replaced.

## Requirements

### Validated

<!-- The kitty-based v1, shipped 2026-06 and daily-dogfooded. It stays the daily driver until cutover. -->

- ✓ Board/line/trunk/patch lifecycle on kitty (generate/line/trunk/patch/active/list/switch) — kitty v1
- ✓ Per-pane session-ID hold markers with atomic consume + `--continue` fallback — kitty v1 (seam 2)
- ✓ Agent-kind table single-sources argv + holdable/stylable policy — kitty v1 (seam 1)
- ✓ Unified session emitters (`_emit_session`) — kitty v1 (seam 4)
- ✓ Plasma 6 widget bound exclusively to `stail --json` — kitty v1
- ✓ systemd regen units watching workspace lab membership — kitty v1
- ✓ 147-assertion regression suite green — kitty v1

### Active

<!-- Current milestone: Zellij Foundation — functional parity with the kitty system, running on Zellij. -->

- [ ] Pre-migration state seam: stail-owned running state; kdotool shrinks to raise/focus (SEAM)
- [ ] Zellij plugin feasibility: four kitty roles answered, permissions validated, prior art assessed (PLUG)
- [ ] Board/line/trunk/patch/exchange lifecycle on Zellij (LIFE)
- [ ] Hold/resume marker protocol on Zellij, fleet-safe (HOLD)
- [ ] Watcher/styling/attention rebuilt in-plugin with structural pane-safety (WATCH)
- [ ] One-handed deck focus control + hot-seat swap on Zellij (DECK)
- [ ] Widget, systemd, launchers, and regression suite at parity; cutover (CUT)

See `.planning/REQUIREMENTS.md` for the full numbered set.

### Out of Scope

- WezTerm / tmux-hybrid mux paths — the owner locked the Zellij pivot; alternatives are closed for this milestone
- Mux-agnostic helper daemon — ranked last by the direction report; trades the send-text-only safety property down to config policy
- Rewriting the bash spine — it survives near-term as the CLI; spine-language triggers T1–T5 are noted, not preempted
- Foreign agent kinds (opencode etc.) — the safety-critical "continue is cwd-scoped" column is unverifiable without running each agent; deferred until one is actually installed
- Multi-box distribution / release packaging — single CachyOS/KDE box; compiled-distribution pressure (T4) has not fired

## Context

- Repo is two days past kitty v1, daily-dogfooded by a single author on one CachyOS / KDE Plasma 6 / Wayland box. WIP lives on the `versioning` branch; `main` is stable.
- Ingested intel: `docs/direction-report-2026-06.md` (DOC, advisory) — fully synthesized into `.planning/intel/context.md`. Its "defer the mux swap" verdict is superseded by the owner firing the "mux migration is scheduled" trigger; its migration-order prescription survives: **state seam first, then emitters — before, not during**. Emitter unification already landed (commit ee250e1); the state seam has not, hence Phase 1.
- kitty is load-bearing in four fused roles that each need an explicit Zellij-era answer: mux/session grammar, scriptable window model, in-process watcher host, and a hidden GUI-host role (rendering, window-class stamping, `.desktop` ownership, beyond-PATH binary resolution). The interaction layer (~28% of source: kittens + deck.conf) is a per-backend paradigm rewrite, not an adapter.
- What survives unchanged: the `--json` contract (every external surface binds to it), the Plasma widget, agent-kind table semantics, per-pane session-ID resume semantics (`claude --resume <id>` is mux-independent), and the bash spine as the CLI.
- Prior art to evaluate during phase research (not hand-roll blindly): zellij-attention, zellaude, zellij-sessionizer/zjsh/zsm/zellij-switch, zellij-pane-picker/room.
- Hard-won operational lesson: GUI-spawned processes (plasmashell, systemd user units) lack `~/.local/bin` on PATH — absolute paths everywhere they invoke `stail`.

## Constraints

- **Tech stack**: Zellij plugin compiled to WASM; Rust via zellij-tile unless plan-phase research finds a strong reason otherwise — owner decision
- **Compatibility**: `stail --json` contract is the frozen integration boundary — the Plasma widget and systemd surfaces must keep working against it unmodified
- **Continuity**: the kitty-based v1 stays the daily driver until parity; no phase may break the working kitty system before the cutover phase
- **Safety**: the watcher must become *structurally* unable to kill a pane — claim Zellij's permission model (the kitty design only had discipline)
- **Runtime**: Linux (CachyOS), KDE Plasma 6 / Wayland; kdotool retained for raise/focus only after Phase 1
- **Verification**: parity = the current verified behavior set; regression breadth ≥ the 147-assertion kitty baseline

## Key Decisions

<!-- LOCKED decisions constrain all phases. Source: owner unless noted. No ADR-locked decisions existed in the ingest set. -->

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| **LOCKED (owner, 2026-06-11): Replace the kitty foundation entirely — rebuild SwitchTail as a large Zellij plugin (WASM; Rust/zellij-tile first-class)** | Owner explicitly fired the report's "mux migration is scheduled" trigger, superseding its defer verdict | — Pending |
| Milestone success = functional parity with the kitty system, on Zellij | Parity is the only honest cutover gate for a daily-driver tool | — Pending |
| State seam first, then build (Phase 1 before any Zellij work) | Ingest guidance: "state seam first, then emitters — before, not during"; emitters already unified | — Pending |
| `--json` contract frozen as the integration boundary | Every external surface binds to it, not to bash/kitty — it is what makes the swap tractable | — Pending |
| Bash spine survives this milestone as the CLI | Report's debiased ranking; T1–T5 triggers noted, not preempted | — Pending |
| Declare minimal Zellij plugin permissions (watcher cannot destroy panes) | Converts a discipline-only safety property into a structural one | — Pending |
| Roadmap stays goal-level; Zellij API specifics resolved by per-phase research | workflow.research enabled; avoids freezing hallucinated API details | — Pending |

---
*Last updated: 2026-06-11 after project initialization (new-project-from-ingest)*
