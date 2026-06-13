# Roadmap: SwitchTail

## Milestones

- ✅ **v0.1 Switchboard Groundwork** — Phases 1–4 (shipped 2026-06-13) ·
  archived: [`milestones/v0.1-ROADMAP.md`](milestones/v0.1-ROADMAP.md)

- 🚧 **v0.2 Composing the Exchange** — Phases 1–3 (numbering reset; v0.1 phase
  dirs archived to `milestones/v0.1-phases/`)

## Phases

<details>
<summary>✅ v0.1 Switchboard Groundwork (Phases 1–4) — SHIPPED 2026-06-13</summary>

- [x] Phase 1: Core Model — completed 2026-06-12
- [x] Phase 2: Plugin Adapter — completed 2026-06-12
- [x] Phase 3: Pipes & Protocol — completed 2026-06-12
- [x] Phase 4: Operator Polish & E2E — completed 2026-06-13 (UAT 9/9, gap-closure 04-05/04-06)

Full detail: [`milestones/v0.1-ROADMAP.md`](milestones/v0.1-ROADMAP.md) ·
requirements: [`milestones/v0.1-REQUIREMENTS.md`](milestones/v0.1-REQUIREMENTS.md)

</details>

### 🚧 v0.2 Composing the Exchange

Numbering reset to Phase 1 (owner directive; v0.1 archived). The unit of
composition is a **board of agent lines** (default 5 `claude` lines), so a board
of N is foundational, not deferred.

- [ ] **Phase 1: Board Foundation — Spawn One Board of Agents** - Modifier-aware
  key model + config + the board verb spawning ONE default-size board of `claude`
  lines (bare, N=1), with async board-fill reconciliation, default-agent-in-core,
  deck-cap warning, and exit-127 surfaced no-kill.

- [ ] **Phase 2: Count Grammar — N Boards in One Gesture** - The count-entry
  sub-state (verb + digit 1–9, Esc aborts) and its CB-safe status-line indicator,
  upgrading the board verb to N boards of the default size.

- [ ] **Phase 3: Line Verb — Top Up the Current Board** - The secondary line verb
  that adds individual `claude` lines to the current board (bare = 1, verb + count
  = N), reusing the count grammar from Phase 2.

## Phase Details

### Phase 1: Board Foundation — Spawn One Board of Agents

**Goal**: The operator can press one board compose verb and immediately get a
new board (tab) staffed with the default number of `claude` lines (5) — the
board-of-agents unit, live, with the "press → it happens" feel. This phase
lays the modifier-aware key foundation every verb needs and proves async
board-fill reconciliation under the real Zellij event model.
**Depends on**: Nothing (first v0.2 phase; builds on the shipped v0.1 core)
**Requirements**: COMP-01, COMP-02, COMP-03, COMP-09, COMP-10, COMP-11, COMP-12
**Success Criteria** (what must be TRUE):

  1. The operator presses the board compose verb once and exactly one new board
     appears, becomes focused, and carries the default number of `claude` lines
     (5), each assigned a deck key (the first board of 5 fills 5 of the 10 deck
     slots — within capacity).

  2. Each spawned line runs the configured default agent (`claude`); changing
     the configured default lines-per-board changes how many lines a freshly
     spawned board carries, and a bare-shell line is reachable as the explicit
     `n` opt-out.

  3. The board's tab and its lines arrive via later TabUpdate/PaneUpdate events
     yet reconcile correctly — every line lands on the intended new board, and a
     line selected before the gesture stays selected on the same identity (no
     cursor drift) throughout the spawn burst.

  4. A spawned line whose command exits immediately (e.g. `claude` not on PATH,
     exit 127) shows as a call-log entry and stays in the directory; the plugin
     never closes or kills any pane (no-kill discipline preserved).

  5. The board compose verb is read from config as a Shift/Super-modified binding
     (off Zellij's Ctrl/Alt), and the core key model + adapter key mapping carry
     that modifier information rather than a bare character.
**Plans**: 3 plans (3 waves)
Plans:

- [x] 01-01-PLAN.md — Modifier-carrying KeyInput + configurable compose-verb binding (COMP-09)
- [x] 01-02-PLAN.md — SpawnBoard intent + agent/board-size config + fan-out + deck-cap warning + exit-127 + async no-drift (COMP-01,02,03,10,11,12; core/TDD)
- [ ] 01-03-PLAN.md — Adapter SpawnBoard arm + RunCommands permission + CommandPaneExited routing + live reload smoke (COMP-01,02,11; human-verify)

**UI hint**: yes

### Phase 2: Count Grammar — N Boards in One Gesture

**Goal**: The operator can spawn N boards of agents in a single gesture — board
verb followed by a digit 1–9 — and the mid-bind state is never invisible. This
phase adds the count-entry sub-state (cloned from v0.1's Prompt pattern, gated
at the top of `key()` so digits do not collide with deck-jump) and its CB-safe
status-line indicator.
**Depends on**: Phase 1 (the board verb, modifier key model, async board-fill
reconciliation, and the deck-cap warning are all established there)
**Requirements**: COMP-04, COMP-06, COMP-07, COMP-08
**Success Criteria** (what must be TRUE):

  1. The operator presses the board verb then a single digit 1–9 and that many
     boards appear, each carrying the default number of `claude` lines (verb+3 →
     3 boards of 5 = 15 agents).

  2. After the board verb the operator is in a count-entry sub-state where digit
     keys accumulate the count instead of jumping to a deck line; a digit fires
     the count immediately and Esc aborts the sub-state without spawning anything
     or mutating the exchange.

  3. A bare board verb with no following count acts in unit — exactly one board
     of the default size — preserving the Phase 1 "press and it happens" feel.

  4. While the board verb is pending the operator sees a CB-safe status-line
     indication of the pending verb and accumulating count (blue↔amber + text,
     never red↔green), so the mid-bind state is always visible.

  5. Spawning 2+ boards exceeds the deck's 10-key capacity (2 boards of 5 = 10,
     3 = 15); the overflow lines still spawn but are surfaced with the CB-safe
     deck-cap call-log warning from Phase 1 — never silently dropped or capped.
**Plans**: TBD
**UI hint**: yes

### Phase 3: Line Verb — Top Up the Current Board

**Goal**: The operator can add individual `claude` lines to the current board
with a second, separate line compose verb — bare adds exactly one line, verb +
count (1–9) adds that many — letting the operator top up a specific board after
the board-level composition of Phases 1–2.
**Depends on**: Phase 1 (default-agent resolution, async line reconciliation,
deck-cap warning) and Phase 2 (the count-entry sub-state + status-line indicator
the line verb reuses unchanged)
**Requirements**: COMP-05
**Success Criteria** (what must be TRUE):

  1. The operator presses the line compose verb (bare) and exactly one new
     `claude` line is added to the current board, taking the next deck key.

  2. The operator presses the line verb then a single digit 1–9 and that many
     `claude` lines are added to the current board in one gesture (a trunk of N
     parallel lines), reusing the same count-entry grammar and status-line
     indicator as the board verb.

  3. The line verb is a configurable Shift/Super binding distinct from the board
     verb, and when adding lines would push a board past the deck's 10-key
     capacity the overflow lines still spawn but carry the CB-safe deck-cap
     warning — never a silent drop or cap.
**Plans**: TBD
**UI hint**: yes

## Progress

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1. Core Model | v0.1 | 1/3 | In Progress|  |
| 2. Plugin Adapter | v0.1 | — | Complete | 2026-06-12 |
| 3. Pipes & Protocol | v0.1 | — | Complete | 2026-06-12 |
| 4. Operator Polish & E2E | v0.1 | — | Complete | 2026-06-13 |
| 1. Board Foundation — Spawn One Board of Agents | v0.2 | 2/3 | In Progress | - |
| 2. Count Grammar — N Boards in One Gesture | v0.2 | 0/0 | Not started | - |
| 3. Line Verb — Top Up the Current Board | v0.2 | 0/0 | Not started | - |
