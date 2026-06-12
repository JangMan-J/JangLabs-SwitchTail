# Phase 1: Running-State Seam - Research

**Researched:** 2026-06-12
**Domain:** Live bash CLI refactor (stail) + kitty watcher API + filesystem state design — no Zellij work in this phase
**Confidence:** HIGH (codebase-first phase; every load-bearing claim verified against the live repo, the live deployment, or the installed kitty 0.47.1 source)

## Summary

Phase 1 moves running-board detection off kdotool/KWin window-class search and into state that stail itself owns, on the live kitty daily driver, without breaking it. The codebase audit shows the seam is well-confined: kdotool appears at exactly 7 functional call sites in `bin/stail`, of which 4 are detection (must move), 2 are raise (must stay), and 1 is dual-use (`_win_ids`, which stays for raise but loses its detection caller). The Plasma widget consumes only the `--json` stdout shapes (`{lab,display,running}` rows; `{lab,display,exchange}` for active) and parses defensively — holding those shapes constant satisfies the zero-widget-change criterion.

The recommended design is a **per-pane run-marker scheme that mirrors the proven hold-marker layout**: `stail line` (which already runs at the boot of every pane, of every kind, on every board) writes `$STATE/run/<lab>/<pid>` before its `exec` (exec preserves the PID, so the marker's filename is the live agent process), with the marker content carrying the process start-time (PID-reuse guard), the board identity, kind, and sid. Liveness is checked lazily at read time via `/proc/<pid>` + start-time comparison, and dead markers are reaped on read — crash-clean with no exit hooks. `stail active` (which SEAM-01 also names, though the roadmap success criteria omit it) moves to a watcher-maintained `$STATE/active` file: kitty's documented `on_focus_change` watcher hook (verified present in the installed 0.47.1 source) writes/clears the focused board's identity, which the emitter stamps on every pane as a new `--var board=` user var. This design is deliberately **mux-agnostic**: Zellij panes in Phase 3 can run the same `stail line` and write the same markers, which is exactly why the ingest prescribed this seam *before* the migration.

The main risks are operational, not algorithmic: the repo's `bin/stail` is live via symlink (merge = deploy, and the widget polls it every few seconds); pre-seam boards that are already running have no markers and will read as down until relaunched; and the regression suite's kdotool-stub listing tests (test-2 B1–B5, test-3 R2-switch, test-4 #10) assert the *old* detection source and must be rewritten to the new one while the rest of the 147-assertion baseline stays intact.

**Primary recommendation:** Implement PID-keyed run markers written by `stail line` + lazy `/proc` reaping for `list`, a `--var board=` stamp in `_emit_session` + a new dedicated `on_focus_change` watcher for `active`, keep kdotool only inside `cmd_switch`, and rewrite the kdotool-stub tests against the state dir.

## Project Constraints (from CLAUDE.md)

Directives extracted from `switchtail/CLAUDE.md` (lab authority) and the user-level harness that bind this phase:

1. **Window-class contract (6-point lockstep)** — points 1–3 (CLI class emission, `os_window_class` in sessions, `.desktop` `StartupWMClass`) and point 6's JSON binding must NOT change; point 5 (kdotool greps class for running detection) is precisely what this phase replaces, so **CLAUDE.md itself must be updated in this phase** to describe the new state source. Point 4 (kittens read `--var` identity/policy flags) is *extended* (new `board` var), never contradicted.
2. **Hold-marker contract** — `$STATE/hold/<lab>/<sid>` layout and the atomic-mv claim are a 2-way contract between `bin/stail` and `hold.py`: "change the state-dir layout in stail and hold.py together or not at all." The run-marker scheme adds a *sibling* dir (`run/`), it must not disturb `hold/` or the legacy `<lab>.hold` flags.
3. **Runtime placement rules** — `bin/`, `kitty/`, `tests/` are live via **relative symlinks**; edits are live immediately. A new watcher file in `kitty/` needs a new relative symlink into `~/.config/kitty/` plus a `kitty.conf` include. `systemd/` files are copied, not symlinked (unaffected this phase).
4. **PATH discipline** — plasmashell/systemd invoke `$HOME/.local/bin/stail` by absolute path; nothing in this phase may introduce a bare-name invocation in any GUI-spawned context.
5. **Verification gate** — `tests/run-all.sh` (147 assertions) must run green before any commit touching `bin/stail`, the kittens, or the tests.
6. **Branch model** — work on `versioning` (or the GSD phase branch `gsd/phase-1-…`), merge to `main` when stable. Worktrees are enabled in config — see Pitfall 1 for the live-symlink interaction.
7. **Verify-before-act / Context7** — library API surface (kitty watchers) verified against installed source + official docs this session; planner should not introduce new unverified API usage.

## Phase Requirements

<phase_requirements>

| ID | Description | Research Support |
|----|-------------|------------------|
| SEAM-01 | `stail list` / `stail active` / `stail list --json` report board running state from stail-owned state, not kdotool/KWin window-class search | Run-marker design (Pattern 1) covers `list`; watcher-maintained active file (Pattern 3) covers `active`. kdotool call-site inventory (below) identifies exactly what moves. Note: ROADMAP success criteria omit `active` but SEAM-01 includes it — design provided; see Open Question 1. |
| SEAM-02 | kdotool usage reduced to raise/focus only; running detection no longer depends on `os_window_class` stamping | Call-site classification shows `cmd_switch` keeps kdotool for `windowactivate` + the id `search`; `cmd_list`, `cmd_active`, `cmd_trunk`'s already-up check, and `_need_kdotool` gating of list/active all move to the state dir. Class stamping itself stays (needed by `.desktop`/`StartupWMClass` and the raise path) — only *detection* decouples from it. |

</phase_requirements>

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Run-state record (who is up) | stail-owned state dir (`$STATE/run/`) | — | The seam's whole point: state owned by the CLI layer, not the WM or the mux |
| Run-state writes (pane boot) | `stail line` (in-pane process, pre-`exec`) | — | Only component guaranteed to run at every pane boot on *any* future mux |
| Run-state liveness/cleanup | `stail list`/readers (lazy reap via `/proc`) | `stail line` (opportunistic reap of own lab) | No exit hook survives `exec`; crash-cleanliness must live at read time |
| Focused-board record | kitty watcher (`on_focus_change`, in-process) → `$STATE/active` | `cmd_active` cross-check vs run markers | Focus is host-GUI-owned; the watcher is the only stail-controlled component that receives focus events without polling the WM |
| Board identity per pane | `_emit_session` (`--var board=` + argv) | — | Single emitter = single place to stamp board identity (the seam landed in commit ee250e1 pays off here) |
| Raise/focus action | kdotool/KWin (`cmd_switch` only) | — | KWin owns window activation on Plasma/Wayland; explicitly retained per SEAM-02 and PROJECT.md runtime constraint |
| Running-state display | Plasma widget via `stail … --json` (unchanged) | CLI text output | `--json` contract held; zero widget changes is a phase success criterion |
| Session regen | `stail generate` + systemd path unit (unchanged logic, regenerated output) | — | Regen rewrites session files with the new `board` stamping; units themselves don't change |

## Current-State Map (verified against the live repo and deployment)

### kdotool call-site inventory in `bin/stail` (the SEAM-02 ledger)

| Line | Site | Used by | Classification | Phase action |
|------|------|---------|----------------|--------------|
| 114 | `_win_ids` — `kdotool search --class "$(_class_re …)"` | `cmd_switch` (676, 688), `cmd_trunk` (508) | Dual-use | Keep for `cmd_switch` raise; `cmd_trunk`'s caller moves to state |
| 146 | `_running_labs` — `kdotool search --class 'switchtail-' getwindowclassname '%@'` | `cmd_list` (650) | **Detection** | Replace body with run-marker scan |
| 151 | `_need_kdotool` guard | `cmd_active` (623), `cmd_list` (646), `cmd_switch` (671) | Gate | Remove from list/active (they must work with kdotool absent); keep for switch |
| 508 | `cmd_trunk` already-up warning via `_win_ids` | trunk launch path | **Detection** | Re-key off run markers |
| 626 | `cmd_active` — `kdotool getactivewindow getwindowclassname` | active query | **Detection (focus query)** | Replace with `$STATE/active` read |
| 681 | `cmd_switch` — `kdotool windowactivate` (standalone) | raise | **Raise** | Keep |
| 691 | `cmd_switch` — `kdotool windowactivate` (exchange fallback) | raise | **Keep** (the *decision* to take this branch can move to state; the activation stays kdotool) |

Related non-kdotool detection helpers: `_aggregate_labs`/`_lab_in_aggregate` (172–177) grep the on-disk exchange session *file* to union exchange lines into the running set and to drive `cmd_switch`'s raise-the-exchange fallback. With run markers carrying `board=exchange`, both consumers can use live state instead of a file grep (strictly more accurate — see Pitfall 6). [VERIFIED: bin/stail read in full this session]

### The `--json` contract the widget binds to (must hold byte-shape)

- `stail active --json` → `{"lab":"x","display":"X","exchange":false}` or `{"lab":null,"display":null,"exchange":false}`; exit 0 on a board, 1 off. Widget parses `d.lab`, `d.display`, `d.exchange` defensively (ignores exit code, keeps prior state on parse failure). Polled continuously ("Always track the focused lab cheaply"). [VERIFIED: plasmoid main.qml 138–166, 204–210]
- `stail list --json` → array of `{"lab":"x","display":"X","running":bool}`. Polled only while the popup is open; custom-dir rows in the widget are never updated from list output (they default `running:false`), so slug parity is NOT needed — only lab-name parity. "exchange" never appears as a list row (`_discover_labs` excludes it); the union only matters for member labs. [VERIFIED: main.qml mergeLabs + cmd_list]
- Widget invokes stail by absolute `$HOME/.local/bin/stail` (configurable). [VERIFIED: main.qml line 26–28]

### Live deployment facts

- `~/.local/bin/stail`, `~/.config/kitty/{hold,swap,tail}.py`, `{hold,keys,tail}.conf` are **relative symlinks into this repo** — an edit to the checked-out branch is live for the next invocation/kitty launch. [VERIFIED: ls -la]
- `kitty.conf` includes `hold.conf`, `keys.conf`, `tail.conf` (lines 3203–3209). `allow_remote_control` and `listen_on` are **at defaults (off)** — there is no kitty remote-control socket on this box. [VERIFIED: grep kitty.conf]
- The tail watcher is a **global** watcher (`watcher tail.py`), loaded per kitty process; each board is a separate kitty process. [VERIFIED: tail.conf + kitty.conf include]
- `stail line` ends in `exec` for every kind (shell, cmd:, agent) — the pane's foreground process keeps the shell's PID. [VERIFIED: cmd_line]

## Standard Stack

### Core (no new packages — everything is already installed)

| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| bash | 5.x (system) | stail spine edits | Locked decision: bash spine survives this milestone |
| kitty | 0.47.1 | watcher host (`on_focus_change`), session launch | Daily driver; watcher hooks verified in installed source [VERIFIED: /usr/lib/kitty/kitty/{launch.py,window.py}] |
| coreutils `mv` / `rm` | 9.x | atomic marker claim/write (same-FS rename) | Already the proven claim primitive in `_hold_claim` |
| `/proc` (procfs) | kernel | PID liveness + start-time (stat field 22) | Standard Linux; field parsing verified empirically this session [VERIFIED: /proc/self/stat] |
| python3 | 3.14.5 | new watcher file (kitty embedded interpreter uses kitty's own python; test scripts use system python3) | Same runtime hold.py/tail.py already use |
| kdotool | v0.2.3 | raise/focus ONLY after this phase | Retained per SEAM-02 / PROJECT.md runtime constraint |
| uuidgen | util-linux 2.42.1 | sid minting (unchanged) | Already in use |

### Supporting

| Tool | Version | Purpose | When to Use |
|------|---------|---------|-------------|
| jq | 1.8.1 | JSON emission hardening | OPTIONAL. T1 trigger ("first arbitrary-string field in --json → jq same day") has NOT fired: list/active emit only charset-validated lab names and booleans. Current `printf` emission is contract-safe; adopting `jq -n --arg` is an intel-suggested hardening at planner discretion, output must stay byte-compatible. |
| shellcheck | installed | lint gate for stail edits | Intel "status-quo hardenings" suggested it as a run-all.sh gate; in-scope only if cheap |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| PID run markers (recommended) | kitty remote-control socket queries (`kitten @ ls`) | Ground truth incl. focus, but requires enabling `allow_remote_control`+`listen_on` in the live kitty.conf (currently OFF — an attack-surface expansion tail.py's design deliberately avoided), and re-couples listing to *kitty* on the eve of a kitty exit. Markers are mux-agnostic: Zellij panes run the same `stail line` in Phase 3. Reject as primary. |
| PID run markers | watcher-written run markers (`on_close`/`on_resize` in a kitty watcher) | `on_close` fires only on graceful `Window.destroy()` — a kitty crash/SIGKILL leaves stale markers with no liveness datum; and the writer evaporates at mux migration. Reject for run state; the watcher IS right for focus (active), where staleness is bounded by cross-check. |
| Lazy reap at read | a cleanup daemon / systemd timer | A new moving part to own; lazy reap is O(markers) at each `list` poll and self-heals. Reject. |
| Start-time PID-reuse guard | bare `/proc/<pid>` existence | Simpler, but a wrapped PID false-positives for the lifetime of the reused process. Start-time costs one read of `/proc/<pid>/stat`. Keep the guard. |

**Installation:** none. No packages are added in this phase.

## Package Legitimacy Audit

No external packages are installed in this phase (pure edits to in-repo bash/python/conf files; all runtime tools already present on the box).

**Packages removed due to [SLOP] verdict:** none
**Packages flagged as suspicious [SUS]:** none

## Architecture Patterns

### System Architecture Diagram

```
                          ┌──────────────────────────────────────────────┐
                          │  _emit_session (single emitter, bin/stail)   │
                          │  per launch line adds:                       │
                          │   --var lab= kind= holdable= stylable=       │
                          │   --var board=<board>          (NEW)         │
                          │   argv: stail line <lab> <dir> <kind> <board>│
                          └───────────────┬──────────────────────────────┘
                                          │ kitty --session (per-lab file /
                                          │ transient trunk/patch via stdin)
                                          ▼
   pane boot ────────────► stail line  ───┬─► writes $STATE/run/<lab>/<PID>     (NEW)
                                          │     content: start= board= kind= sid=
                                          │     (tmp+mv, never fails the pane)
                                          └─► exec claude/--resume/--continue/$SHELL/cmd
                                                (exec keeps PID ⇒ marker == live process)

   kitty focus events ───► state watcher (NEW kitty/state.py, on_focus_change)
                              gain: atomic-write $STATE/active = <board>
                              loss: compare-and-clear if still own board

   READERS (no kdotool):
     stail list [--json] ──► scan $STATE/run/*/*: /proc liveness + start-time check,
     stail active [--json]    reap dead markers, union board=exchange members;
                              active = $STATE/active cross-checked against live run set
                              └─► SAME JSON shapes ──► Plasma widget (ZERO changes)

   RAISE PATH (kdotool kept):
     stail switch <lab> ──► decision from run markers ──► kdotool search --class + windowactivate
                            (no window found despite state ⇒ fall through to launch)
```

### Recommended Project Structure

```
bin/stail            # _running_labs rewritten; cmd_active rewritten; cmd_list/_need_kdotool
                     # adjusted; cmd_trunk warning re-keyed; _emit_session stamps board;
                     # cmd_line writes run marker; new helpers _run_mark/_pane_alive/_reap
kitty/state.py       # NEW: focus watcher (active file). Separate file — tail.py's audited
                     # "send-text only" safety property stays clean
kitty/state.conf     # NEW: `watcher state.py` (included from kitty.conf, like tail.conf)
tests/stail-test-6.sh# NEW: state-seam assertions (markers, reap, list/active from state,
                     # kdotool-absence proof)
tests/stail-test-2.sh# B1–B5 rewritten: state-dir fixtures instead of kdotool stubs for listing
tests/stail-test-3.sh# R2 switch tests: decision now from state fixtures; raise stubs stay
tests/stail-test-4.sh# #10 already-up warning re-keyed to state fixture
tests/run-all.sh     # add test-6
CLAUDE.md            # window-class contract point 5 rewritten to the new state source
```

### Pattern 1: PID-keyed run markers with start-time guard (run state)

**What:** At pane boot, before `exec`, `stail line` writes `$STATE/run/<lab>/<PID>` whose content records the process start time (jiffies, `/proc/self/stat` field 22), board, kind, and sid. Because `exec` preserves the PID, the marker names the live agent process for the pane's whole life. Readers treat a marker as live iff `/proc/<pid>/stat` exists AND its start time matches the recorded one; otherwise they `rm -f` it (lazy reap).
**When to use:** every pane kind — claude, shell, and cmd: panes all count toward "board running" today (window-class detection counts the window), so all kinds must write markers to preserve semantics.
**Why it survives the migration:** Zellij panes will also boot via `stail line`; the marker protocol is the part of detection that is mux-independent — exactly the seam the ingest prescribed.

**Key liveness detail (verified):** kitty closes a pane when its exec'd process exits and closes the OS window when its last pane closes; conversely closing the window kills the child. So PID-liveness tracks pane-liveness in both directions, including hold (hold.py closes the pane → process dies → marker reaped → lab correctly reads down, matching today's class-disappears behavior).

### Pattern 2: Board identity stamped by the single emitter

**What:** `_emit_session` already computes the window class (`$1=cls`); derive `board="${cls#switchtail-}"` and (a) add `--var board=$board` to every launch line, (b) pass `$board` as `stail line`'s 4th argv (defaulting to `$lab` when absent, so pre-regen session files keep working).
**Why:** one edit point (the emitter seam from commit ee250e1) gives both the watcher (reads `user_vars['board']` for active) and the run marker (records `board=` so `list` can union exchange members and `switch` can decide "live only inside the exchange") a consistent board identity — replacing both the class-grep (`_running_labs`) and the session-file grep (`_aggregate_labs`) with live data.

### Pattern 3: Watcher-maintained active file with compare-and-clear (focus state)

**What:** A new global watcher `kitty/state.py` implements `on_focus_change(boss, window, data)` — `data={'focused': bool}` [VERIFIED: installed kitty 0.47.1 window.py:1412 + official docs]. On gain: atomically write the window's `board` user var to `$STATE/active` (tmp + `os.replace`). On loss: re-read and unlink only if the content still equals own board (compare-and-clear, so a gain event from the newly focused board that lands first is not clobbered). Windows without a `board` var (non-stail kitty windows) are ignored, but a stail board losing focus to anything still fires its own loss event, clearing the file.
**Crash staleness:** if a focused kitty dies (no loss event), `$STATE/active` goes stale — `cmd_active` must cross-check the named board against the live run-marker set and report off-board on mismatch.
**Why a separate file from tail.py:** tail.py's header documents an incident-bought property — "ONLY ever calls send-text… structurally cannot destroy a pane." Adding filesystem-write responsibility to it muddies that audit. A second watcher file keeps both single-purpose; kitty supports multiple `watcher` directives. [CITED: sw.kovidgoyal.net/kitty/launch/#watchers]

### Pattern 4: Raise decision from state, raise action via kdotool

**What:** `cmd_switch` keeps its shape but re-sources decisions: "is the lab up standalone" and "is it live only inside the exchange" come from run markers; the *activation* still does `kdotool search --class … windowactivate`. If state says running but kdotool finds no window (sub-second race or stale state), fall through to the existing launch path with a warning rather than failing.
**Why:** keeps "running ⇒ switch raises" honest by having `list` and `switch` consult the SAME state source (success criterion 2 + the verified R2 behavior set).

### Anti-Patterns to Avoid

- **Marker write that can kill a pane:** the run-marker write happens before `exec` in the agent boot path. Any failure (read-only state dir, ENOSPC) must degrade *listing*, never abort the pane — guard every write with `|| true` semantics and write the marker only after the `cd` validation succeeds.
- **`awk '{print $22}'` on `/proc/<pid>/stat`:** the comm field may contain spaces/parens. Strip through the last `) ` first (`rest="${stat##*) }"`), then start time is field 20 of the remainder. [VERIFIED: empirically this session — both methods agree only when comm has no spaces]
- **Treating `on_close` as a reliable exit hook:** it fires only in graceful `Window.destroy()` [VERIFIED: window.py:1926], never on kitty crash/SIGKILL. Liveness must come from `/proc`, not close events.
- **Enabling kitty remote control "just for ls":** expands attack surface the watcher design deliberately avoided, and re-couples detection to kitty.
- **Interpolating unvalidated marker filenames/file content into paths, `kill`, or JSON:** the run dir is operator-owned but defensive validation is established house style (`_hold_claim`'s `_SID_RE` gate). PIDs must match `^[0-9]+$` before any `/proc/$pid` or `rm` use; the active file's content must match the lab charset before reaching JSON output.
- **Editing `~/.local/bin/stail`'s target in place without a green suite:** the widget executes the live symlink every poll interval; broken intermediate states are user-visible within seconds (see Pitfall 1 for the worktree interaction).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Atomic single-writer state updates | lockfiles/flock protocols | `printf > tmp && mv -f` (same-FS rename) | Already the repo's proven primitive (`_hold_claim`); rename is atomic on one filesystem |
| Focus tracking | polling kdotool/wmctrl/KWin scripting | kitty `on_focus_change` watcher | Event-driven, in-process, documented public watcher API, zero polling cost [VERIFIED: installed source + docs] |
| Pane liveness | `pgrep claude` / process-name matching | `/proc/<pid>` + start-time compare | Name-matching breaks for shell/cmd kinds and other claude processes on the box; PID+starttime is exact |
| Session/board identity transport | parsing window titles or re-grepping session files | `launch --var` user vars via the single emitter | Documented kitty mechanism the kittens already gate on (contract point 4) |
| JSON emission for new fields | string concatenation of arbitrary values | keep charset-validated printf; `jq -n --arg` if any arbitrary string ever enters the contract | T1 trigger discipline from the ingest |

**Key insight:** every primitive this phase needs (atomic mv, `/proc`, user vars, watcher events) already exists in the repo's verified vocabulary or kitty's documented API — the phase is recomposition, not invention.

## Runtime State Inventory

This is a live-system refactor; the canonical question — *after the code changes, what runtime systems still hold old-shape state?*

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | `$STATE` (`~/.local/state/switchtail/`): existing `hold/<lab>/<sid>` markers and possible legacy `<lab>.hold` flags. New `run/` dir and `active` file are net-new siblings. | No migration of hold data; create `run/` lazily (`mkdir -p`). Do NOT touch hold layout (CLAUDE.md 2-way contract). |
| Live service config | On-disk generated session files `~/.config/kitty/sessions/labs/*.kitty-session` and the exchange file carry the OLD 3-arg launch lines without `--var board=`. `.desktop` files unaffected. | Run `stail generate` at deploy (the systemd path unit also triggers on lab changes); `stail line` defaults `board=lab` for any stale file in the interim. |
| OS-registered state | **Already-running boards were launched pre-seam: their panes never wrote run markers and their kitty processes loaded only the old watcher set.** They will read as DOWN and won't feed `active`. | One-time operator step at deploy: hold/relaunch (or close/reopen) running boards. Document in the plan's checkpoint; no code can backfill PIDs from kdotool reliably. |
| Secrets/env vars | None — no secrets in this system; tunables (`SWITCHTAIL_*`) unaffected. Verified by reading bin/stail's full env surface. | None |
| Build artifacts | None — interpreted bash/python/QML only; `__pycache__` under `~/.config/kitty/` regenerates automatically. | None |

## Common Pitfalls

### Pitfall 1: The live-symlink × worktree trap
**What goes wrong:** `~/.local/bin/stail` symlinks to the *main checkout's* `bin/stail`, and every test script starts with `cp ~/.local/bin/stail /tmp/stail-fns.sh`. If the phase executes in a git worktree (config: `use_worktrees: true`), the suite silently tests the OLD live code, not the edited worktree code — green tests prove nothing about the change.
**Why it happens:** tests hardcode the deployed path; the symlink follows whatever branch the main checkout has.
**How to avoid:** parametrize the test harness early in the phase: `STAIL_BIN="${STAIL_BIN:-$HOME/.local/bin/stail}"` in each test (a small, suite-wide mechanical edit), and run the suite with `STAIL_BIN=<worktree>/bin/stail` during development, then once more unset (against the live path) after merge. Conversely remember: on the main checkout, **commit/merge = instant deploy** to a widget that polls every few seconds.
**Warning signs:** a test passes before any code lands; assertions referencing behavior you haven't written yet.

### Pitfall 2: Marker write failure killing an agent pane
**What goes wrong:** `set -uo pipefail` is active in stail; an unguarded `mkdir`/`printf` failure in the new `_run_mark` aborts `cmd_line` before its `exec` — the pane dies at boot, on the daily driver.
**How to avoid:** `_run_mark` returns 0 unconditionally (`|| return 0` on every step); call it after the `cd` guard. Add an explicit test: stail line still execs (stubbed) when `$STATE` is unwritable.
**Warning signs:** any new code between `cd` validation and `exec` that can exit non-zero.

### Pitfall 3: PID reuse and stat parsing
**What goes wrong:** bare `/proc/<pid>` existence false-positives after PID wraparound (a reused PID makes a dead board read running indefinitely); and naive field-22 parsing of `/proc/<pid>/stat` breaks when comm contains spaces/parens.
**How to avoid:** record start time at write (`stat="$(</proc/$$/stat)"; rest="${stat##*) }"; start=$(awk '{print $20}' <<<"$rest")`) and compare at read. Same strip-comm parse on both sides. [VERIFIED: empirical /proc/self/stat check this session]
**Warning signs:** marker content with no `start=` line; any `awk '{print $22}'` in review.

### Pitfall 4: The 147-assertion baseline contains assertions about the OLD mechanism
**What goes wrong:** test-2's B1–B5 (running-set/list via kdotool stubs), test-3's R2 switch-decision stubs, and test-4's #10 (already-up warning via kdotool stub) assert exactly the behavior this phase removes. "Run the suite green" is impossible without rewriting them — but rewriting must preserve the *behavioral* assertions (exchange union semantics, JSON validity, raise-first-id, duplicate warnings) against the new source, or coverage silently shrinks.
**How to avoid:** rewrite each removed kdotool-listing stub as a state-dir fixture (`STATE=/tmp/…` + synthetic `run/<lab>/<pid>` markers using live helper PIDs, e.g. background `sleep` processes whose real `/proc` start times make markers live; test-1 §6 already models the isolated-STATE fixture pattern). Keep total assertion breadth ≥ 147 (criterion 4: baseline *plus* new state-seam assertions).
**Warning signs:** deleted `ok(...)` lines without replacements; a passing suite with a lower printed assertion count.

### Pitfall 5: Watcher deploy needs a kitty relaunch and a kitty.conf edit
**What goes wrong:** `state.py` only loads into kitty processes started *after* the `watcher state.conf` include lands; already-running boards never feed `$STATE/active`, and a missed kitty.conf include means active silently never populates while list works — confusing partial state.
**How to avoid:** deploy order: symlink `state.py`/`state.conf` → add include to kitty.conf → `stail generate` → relaunch boards (same relaunch Pitfall/Inventory item already requires). Make `cmd_active`'s no-file case identical to today's off-board output (`{"lab":null,…}` exit 1), so the degraded mode is correct, not wrong.
**Warning signs:** active always null while list shows boards running and a board is focused.

### Pitfall 6: Exchange semantics quietly improve — tests must encode the NEW truth
**What goes wrong:** today exchange-up ⇒ ALL aggregate-session-file labs report running (a file grep), even labs whose exchange pane already exited. Run markers report only labs with a live pane — strictly more accurate, but test-2 B1/B2 literally assert the old union. A planner who "preserves behavior" exactly will fight the better semantics; one who ignores it breaks `switch`'s raise-the-exchange promise.
**How to avoid:** decide explicitly (recommended: adopt the accurate semantics; they still satisfy "running ⇒ switch raises" because switch's exchange-fallback decision uses the same markers). Update the contract comments in stail and CLAUDE.md to match.
**Warning signs:** `_aggregate_labs`/`_lab_in_aggregate` still grepping the session file post-seam for anything but generate-time concerns.

### Pitfall 7: Concurrent readers reaping the same marker
**What goes wrong:** widget poll + manual `stail list` race on reaping a dead marker; or a reader reads a half-written marker.
**How to avoid:** `rm -f` is idempotent (exit 0 on already-gone); marker writes go through tmp + `mv -f`. No locking needed — single-writer-per-file by construction (writer names the file with its own PID).
**Warning signs:** any design where two processes write the SAME marker path.

## Code Examples

Verified patterns; sources are this repo and the installed kitty/proc surfaces.

### Run-marker write (in `cmd_line`, after `cd` guard, before kind dispatch)
```bash
# Source: pattern composed from bin/stail house style (_hold_claim atomicity) + verified /proc parse
_run_mark() {  # $1=lab $2=board $3=kind $4=sid(may be empty) — NEVER fails the caller
  local d="$STATE/run/$1" stat rest start
  mkdir -p "$d" 2>/dev/null || return 0
  stat="$(cat /proc/$$/stat 2>/dev/null)" || return 0
  rest="${stat##*) }"                       # strip "pid (comm) " — comm may contain spaces
  start="$(awk '{print $20}' <<<"$rest")"   # overall field 22 = field 20 after the strip
  printf 'start=%s\nboard=%s\nkind=%s\nsid=%s\n' "$start" "$2" "$3" "${4:-}" \
    > "$d/$$.tmp" 2>/dev/null && mv -f "$d/$$.tmp" "$d/$$" 2>/dev/null
  return 0
}
```

### Liveness check + lazy reap (replacement core of `_running_labs`)
```bash
# Source: /proc(5) starttime semantics, verified empirically on this box
_pane_alive() {  # $1=pid $2=recorded start -> 0 iff the same process is still alive
  local stat rest
  stat="$(cat "/proc/$1/stat" 2>/dev/null)" || return 1
  rest="${stat##*) }"
  [ "$(awk '{print $20}' <<<"$rest")" = "$2" ]
}
_running_labs() {  # echo each running lab (+ 'exchange' if any live board=exchange marker)
  local d f lab pid start board saw_exchange=0
  shopt -s nullglob
  for d in "$STATE"/run/*/; do
    lab="$(basename "$d")"; local up=0
    for f in "$d"*; do
      pid="$(basename "$f")"
      [[ "$pid" =~ ^[0-9]+$ ]] || continue          # never trust a stray filename
      start="$(grep -m1 '^start=' "$f" 2>/dev/null | cut -d= -f2)"
      if [ -n "$start" ] && _pane_alive "$pid" "$start"; then
        up=1
        board="$(grep -m1 '^board=' "$f" 2>/dev/null | cut -d= -f2)"
        [ "$board" = exchange ] && saw_exchange=1
      else
        rm -f "$f" 2>/dev/null                       # lazy reap; rm -f is race-idempotent
      fi
    done
    [ "$up" = 1 ] && printf '%s\n' "$lab"
  done
  [ "$saw_exchange" = 1 ] && printf 'exchange\n'
}
```

### Board stamping in the single emitter (`_emit_session`)
```bash
# Source: bin/stail _emit_session (existing launch-line shape, extended)
local board="${cls#switchtail-}"
echo "launch --title \"${E_TITLE[$i]}\" --var lab=${E_LAB[$i]} --var board=$board --var kind=$cvar$flags stail line ${E_LAB[$i]} \"${E_DIR[$i]}\" \"$kind\" $board"
# cmd_line: board="${4:-$lab}"  — pre-regen session files (3 args) default board to lab
```

### Focus watcher (new `kitty/state.py`)
```python
# Source: kitty watcher API — on_focus_change data={'focused': bool}
# [VERIFIED: installed kitty 0.47.1 /usr/lib/kitty/kitty/window.py:1412 + launch.py:551]
# [CITED: https://sw.kovidgoyal.net/kitty/launch/#watchers]
import os, re
from typing import Any
from kitty.boss import Boss
from kitty.window import Window

_BOARD_RE = re.compile(r'[A-Za-z0-9._-]+')   # same charset the CLI enforces

def _active_path() -> str:
    state = os.path.join(
        os.environ.get('XDG_STATE_HOME', os.path.expanduser('~/.local/state')), 'switchtail')
    os.makedirs(state, exist_ok=True)
    return os.path.join(state, 'active')

def on_focus_change(boss: Boss, window: Window, data: dict[str, Any]) -> None:
    try:
        board = (window.user_vars or {}).get('board')
        if not board or not _BOARD_RE.fullmatch(board):
            return                              # not a stail board pane — never touch the file
        path = _active_path()
        if data.get('focused'):
            tmp = f'{path}.{os.getpid()}.tmp'
            with open(tmp, 'w') as f:
                f.write(board + '\n')
            os.replace(tmp, path)               # atomic
        else:
            try:                                # compare-and-clear: don't clobber a newer gain
                with open(path) as f:
                    if f.read().strip() == board:
                        os.unlink(path)
            except FileNotFoundError:
                pass
    except Exception:
        pass                                    # a watcher exception must never hurt the pane
```

### `cmd_active` from state (shape-compatible)
```bash
# Source: existing cmd_active JSON shape (bin/stail 619–641), re-sourced
cmd_active() {
  local json=0 lab="" exchange=false f="$STATE/active"
  [ "${1:-}" = "--json" ] && json=1
  if [ -r "$f" ]; then
    lab="$(head -n1 "$f" 2>/dev/null)"
    [[ "$lab" =~ ^[A-Za-z0-9._-]+$ ]] || lab=""          # never let junk reach JSON
    if [ -n "$lab" ]; then                                # crash-staleness cross-check
      _running_labs | grep -qxF -- "$lab" || lab=""
    fi
    [ "$lab" = "exchange" ] && exchange=true
  fi
  # …emit the EXACT current JSON / text shapes and exit codes (0 on board, 1 off)…
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `kdotool search --class 'switchtail-' getwindowclassname '%@'` (one KWin round-trip) for the running set | stail-owned `$STATE/run/<lab>/<pid>` markers + `/proc` liveness | this phase | KDE decoupling; survives the mux swap; widget unchanged |
| Exchange union via session-FILE grep (`_aggregate_labs`) | live `board=exchange` markers | this phase | Strictly more accurate (a closed exchange line no longer reports its lab running) |
| `kdotool getactivewindow` for `stail active` | watcher-maintained `$STATE/active` + liveness cross-check | this phase | Event-driven; widget's hot poll path gets cheaper (file read vs KWin DBus script) |
| `_need_kdotool` gating list/active/switch | kdotool required for `switch` only | this phase | SEAM-02's literal test: removing kdotool degrades raising, never listing |

**Deprecated/outdated (after this phase):** stail header comment lines 19–23 ("active/list/switch introspect the live windows via kdotool…") and CLAUDE.md contract point 5 — both must be rewritten as part of the phase, or the docs will assert the pre-seam world.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Holding `list`/`active` `--json` byte-shapes constant is sufficient for "zero widget changes" — the widget has no other coupling to detection (verified for the QML read paths; assumption extends to untested widget code paths) | Current-State Map | Low — main.qml read in the relevant regions; residual risk is an unseen consumer of exit codes; mitigated by also preserving exit-code behavior |
| A2 | kitty closes a pane when its exec'd process exits (so PID death ⇔ pane gone in both directions) for the session-launched panes as configured on this box | Pattern 1 | Listing could over/under-report if a pane lingers after process exit; verify live during Phase 1 smoke test (open a line, /exit, observe) |
| A3 | `on_focus_change` fires a loss event when focus moves from a kitty board to a non-kitty app (OS-window focus loss propagates to the focused kitty window) | Pattern 3 | `active` would stay stale until the next board gain; cross-check vs run markers bounds the damage to "reports a running board as focused while off-board"; verify live |
| A4 | A single operator box makes the gain/loss cross-process event-ordering race (two kitty processes) tolerable with compare-and-clear (no flock) | Pattern 3 | Worst case: transient wrong/empty active for one poll tick; acceptable; flock is the escalation if observed |

All other claims are [VERIFIED] against the repo, the live deployment, the installed kitty 0.47.1 source, or [CITED] from official kitty docs.

## Open Questions

1. **Does `stail active` move off kdotool in this phase (SEAM-01 says yes; ROADMAP success criteria don't mention it)?**
   - What we know: SEAM-01 explicitly names `active`; success criterion 2 says kdotool appears only in `stail switch`, which forbids `cmd_active`'s `getactivewindow` call.
   - What's unclear: whether the owner intended the lighter list-only reading the roadmap criteria suggest.
   - Recommendation: implement the watcher-based active (design above is complete and low-risk); it is required for the requirement as written and removes the widget's hot-path KWin dependency. If descoped, REQUIREMENTS.md must be amended — flag at plan checkpoint.
2. **Exchange-union semantics: preserve the old file-grep over-report or adopt live accuracy?**
   - Recommendation: adopt live accuracy (Pitfall 6); record the decision in the updated contract comments.
3. **Marker coverage for shell/cmd panes** — recommended yes (parity with class-based counting); a planner choosing agent-only markers changes user-visible running flags for shell-only boards.
4. **Test-harness `STAIL_BIN` parametrization** — recommended yes (Pitfall 1); strictly additive to the suite, default keeps today's behavior.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| kitty | watcher host, session launch | ✓ | 0.47.1 | — (daily driver) |
| kdotool | raise/focus path only (post-seam) | ✓ | v0.2.3 | switch degrades to launch-only (acceptable per criterion 2) |
| bash | stail | ✓ | system (5.x) | — |
| python3 | tests; kitty embeds its own for watchers | ✓ | 3.14.5 | — |
| uuidgen | sid minting | ✓ | util-linux 2.42.1 | `/proc/sys/kernel/random/uuid` (already coded) |
| jq | optional JSON hardening | ✓ | 1.8.1 | keep printf emission |
| shellcheck | optional lint gate | ✓ | installed | skip gate |
| `/proc` procfs | liveness | ✓ | kernel | — (Linux-only by project constraint) |
| Plasma 6 / plasmashell | widget verification | ✓ | running desktop | — |

**Missing dependencies with no fallback:** none.
**Missing dependencies with fallback:** none missing.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Hand-rolled bash assertion scripts (ok/no counters) + python3 scripts, orchestrated by `tests/run-all.sh` |
| Config file | none (scripts are self-contained; they source REAL stail functions with the dispatch tail stripped and stub `kdotool`/`_launch_detached`) |
| Quick run command | `bash tests/stail-test-2.sh` (listing/active/switch logic) — < 10s |
| Full suite command | `bash tests/run-all.sh` — 147-assertion baseline, all suites must report 0 failures |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| SEAM-01 | `list`/`list --json` running flags derive from run markers (live PID fixtures), valid JSON, display names intact | unit (state fixtures) | `bash tests/stail-test-6.sh` | ❌ Wave 0 |
| SEAM-01 | `active`/`active --json` derive from `$STATE/active` + liveness cross-check; off-board/missing-file ⇒ null + exit 1 | unit (state fixtures) | `bash tests/stail-test-6.sh` | ❌ Wave 0 |
| SEAM-01 | Dead-PID markers are reaped on read; start-time mismatch counts as dead | unit | `bash tests/stail-test-6.sh` | ❌ Wave 0 |
| SEAM-02 | `cmd_list`/`cmd_active` succeed with kdotool absent (stubbed to fail / PATH-hidden); `cmd_switch` still requires it | unit | `bash tests/stail-test-6.sh` | ❌ Wave 0 |
| SEAM-02 | trunk already-up warning keyed off state, not kdotool | unit | `bash tests/stail-test-4.sh` (rewritten #10) | ✅ (needs edit) |
| SEAM-01/02 | Rewritten exchange-union, switch-decision, dup-warning behavior set vs new source | unit | `bash tests/stail-test-2.sh`, `tests/stail-test-3.sh` (B1–B5 / R2 rewritten) | ✅ (needs edit) |
| Criterion 3 | Widget shows correct state, zero widget changes | manual-only (visual: panel heading + popup vs real boards; `journalctl --user -u plasma-plasmashell` clean) | — (justification: Plasma rendering not automatable here) | — |
| Criterion 4 | Full baseline green at ≥ prior breadth | integration | `bash tests/run-all.sh` | ✅ (add test-6 to the loop) |
| A2/A3 live checks | pane-exit ⇒ marker dead; focus loss to non-kitty app clears active | smoke (live kitty, one board) | scripted live check or checkpoint:human-verify | ❌ Wave 0 / checkpoint |

### Sampling Rate
- **Per task commit:** `bash tests/stail-test-6.sh && bash tests/stail-test-2.sh`
- **Per wave merge:** `bash tests/run-all.sh` (with `STAIL_BIN` pointed at the edited tree — see Pitfall 1)
- **Phase gate:** `bash tests/run-all.sh` green against the LIVE deployed path after merge, before `/gsd-verify-work`

### Wave 0 Gaps
- [ ] `tests/stail-test-6.sh` — covers SEAM-01 and SEAM-02 state-seam assertions (marker write/reap, list/active from state, kdotool-absence proof, marker-write-failure never kills the pane)
- [ ] `STAIL_BIN` parametrization across `tests/stail-test-{1..5}.sh` + run-all.sh (defaults to `~/.local/bin/stail`) — prerequisite for testing worktree edits honestly
- [ ] Live-smoke checklist (or `checkpoint:human-verify`) for A2/A3: relaunch one board post-deploy, verify list/active/widget against reality

*(Test fixtures: use isolated `STATE=/tmp/…` per test-1 §6's pattern; create "live" markers with background `sleep` helper PIDs and real `/proc` start times — unique per run, no fixed sleeps for window-dependent parts, per the established kitty/KWin smoke-test discipline.)*

## Security Domain

`security_enforcement: true` (ASVS L1). This is a single-user local CLI — most categories are N/A; the applicable surface is input/state validation.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | local single-user tool, no auth surface |
| V3 Session Management | no | "sessions" here are terminal panes, not auth sessions |
| V4 Access Control | no | filesystem perms (`~/.local/state`, user-owned) are the boundary |
| V5 Input Validation | yes | extend the existing charset-gate house style: PID filenames `^[0-9]+$` before `/proc`/`rm` use; active-file content `^[A-Za-z0-9._-]+$` before JSON emission; `board` argv re-validated like `lab` (`_require_valid_lab` pattern); watcher re-validates user-var charsets exactly as hold.py does |
| V6 Cryptography | no | none needed |

### Known Threat Patterns for this stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Path traversal via crafted state filenames (a stray `../x` in run/) | Tampering | numeric-PID filename gate + lab names re-validated before path interpolation (mirrors `_SID_RE` gate in `_hold_claim`) |
| JSON injection through corrupted `$STATE/active` content into `--json` output the widget parses | Tampering | charset validation before emission; widget already parses defensively, but stail must not rely on that |
| Watcher gaining destructive capability | Elevation | new `state.py` contains NO boss window-mutation calls — file writes only; keep it a separate file so tail.py's "send-text only" audit and state.py's "filesystem only" audit each stay one-screen verifiable |
| Pane-boot DoS via failing marker writes | DoS (self-inflicted) | `_run_mark` never propagates failure (Pitfall 2) |
| Untrusted doc/tool output (Context7 has carried injected commands on this box) | — | research used installed-source verification as the authority; no commands from fetched docs were executed |

## Sources

### Primary (HIGH confidence)
- Live repo read in full: `bin/stail` (714 lines), `kitty/{tail.py,hold.py,tail.conf,hold.conf,switchtail-lab.zsh}`, `tests/{run-all.sh,stail-test-1..5.sh}`, `plasmoid/.../main.qml` (read regions: contract header, stail-call layer, poll timer), `RunStail.qml`, `systemd/switchtail-sessions.service`, `CLAUDE.md`
- Installed kitty 0.47.1 source: `/usr/lib/kitty/kitty/launch.py` (watcher hook registration, lines 535–565), `/usr/lib/kitty/kitty/window.py` (on_focus_change at 1412 with `{'focused': bool}`; on_close in `destroy()` at 1926) — the authoritative API for the exact binary the daily driver runs
- Live deployment probes: `~/.config/kitty/kitty.conf` (includes; remote control OFF), symlink layout of `~/.local/bin/stail` and `~/.config/kitty/*`, `/proc/self/stat` field parse, tool versions (kitty 0.47.1, kdotool v0.2.3, jq 1.8.1, python 3.14.5, uuidgen 2.42.1)
- `.planning/` corpus: PROJECT.md, REQUIREMENTS.md, ROADMAP.md, STATE.md, intel/{SYNTHESIS.md,context.md}

### Secondary (MEDIUM confidence)
- [CITED: https://sw.kovidgoyal.net/kitty/launch/#watchers] — official kitty docs for watcher hooks and `launch --var` user variables (concordant with installed source; cached in research store, keys 925fd900…, c483929a…)

### Tertiary (LOW confidence)
- none used as a basis for any recommendation

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — zero new dependencies; every tool version probed on the box
- Architecture: HIGH for the marker/reaper/emitter design (composed entirely of repo-proven primitives + locally verified kitty API); MEDIUM for the two live-behavior assumptions (A2 pane-close ⇔ process-exit, A3 focus-loss event to non-kitty apps), each with a cheap smoke-test mitigation
- Pitfalls: HIGH — all seven derive from directly observed code/deployment facts, not speculation

**Research date:** 2026-06-12
**Valid until:** 2026-07-12 (stable: single-box system under the owner's control; re-verify only if kitty upgrades past 0.47.x before execution — rolling-release carry-tax noted in intel)
