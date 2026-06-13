# Pitfalls Research

**Domain:** Zellij plugin — live in-plugin composition (v0.2 verb+count spawn)
**Researched:** 2026-06-13
**Confidence:** HIGH (grounded in verified API source, v0.1 incident record, and zellij-tile 0.44.3 vendored facts)

---

## Critical Pitfalls

### Pitfall 1: Digit-Key vs. Deck-Key Collision in Count-Entry Sub-State

**What goes wrong:**
`1`–`9` are deck jump keys in normal mode (`Exchange::key` routes `KeyInput::Char(c)` to `FocusLine` when `deck.line_for(c).is_some()`). If a verb+count sub-state is introduced without first placing the exchange into a dedicated input mode, pressing `3` after a spawn verb immediately triggers `FocusLine` for deck slot 3 instead of accumulating the digit as a count.

**Why it happens:**
The v0.1 `key()` dispatch table routes bare digit chars to `FocusLine` unconditionally (except when `prompt.is_some()` — the only existing sub-state guard). A count-entry state for verbs requires the same sub-state pattern the `i` prompt already uses: a gate at the top of `key()` that short-circuits normal dispatch when the state is active.

**The v0.1 analogy — what "prompt sub-state" already solved:**
The `i` prompt sub-state redirects *all* char input (including `'1'`–`'9'`) into `prompt_key()` via the `if self.prompt.is_some()` check at line 199 of `exchange.rs`. The digit-key regression is live-tested in `prompt_types_and_sends_with_cr`: a `'1'` keypress during prompt goes into the buffer, not a deck jump. Count-entry state must use the exact same pattern: a new `pub count_state: Option<CountEntry>` field, checked before the normal dispatch arm.

**How to avoid:**
- Add `pub count_state: Option<CountEntry>` to `Exchange` (analogous to `prompt`).
- At the top of `key()`, gate: `if let Some(state) = &mut self.count_state { return self.count_key(key, state); }`.
- In `count_key()`, `'0'`–`'9'` accumulate digits; the verb letter (or `Enter`) commits the spawn; `Esc` aborts and returns to normal mode; any unrecognized key (e.g. `Tab`, `Up`) also aborts.
- `'0'` is itself a deck key (slot index 9 in `DECK_KEYS`). If the verb+count grammar allows multi-digit counts, `'0'` mid-count must stay in count-accumulation mode, not jump to deck slot 9.

**Warning signs:**
- Core unit test: `count_entry_digits_do_not_focus_lines` — press `3` while in count state, assert no `FocusLine` intent and `count_state` has digit `3` accumulated.
- If the selection or focus changes when the user presses a digit during a compose gesture, this pitfall is active.

**Phase to address:** Phase implementing the verb+count grammar (first slice of v0.2).

---

### Pitfall 2: Async Spawn Reconciliation — Selection Drift Under N Sequential PaneUpdates

**What goes wrong:**
`open_terminal` / `open_command_pane` returns `Option<PaneId>` synchronously, but the pane does not yet appear in `PaneManifest`. Zellij delivers one `PaneUpdate` event per newly-opened pane (not a batch). When N panes are spawned in a loop, N separate `PaneUpdate` events arrive, each triggering `ingest_panes()`. Each ingest call re-runs `sorted_lines()`, which re-ranks by deck assignment. The newly-ingested lines receive new deck slots in the order events arrive (not the order of spawn calls), and the selection anchor (`selected_line_id`) may jump because `navigate()` looks at the post-re-sort position.

**Why it happens:**
This is the v0.1 selection-drift bug class, now with multiple concurrent sources of churn. v0.1 fixed *one* churn source (re-sort on ring) by anchoring selection to `LineId` identity. But N-spawn adds another: if the operator selects a line, then spawning 5 more triggers 5 separate ingests, each potentially re-sorting the deck view. Selection survives because it is anchored to `LineId` — but the *visual row* the selection occupies shifts after each ingest, which may confuse the operator if the cursor appears to "wander" across rows during the spawn burst.

Additionally: the plugin pane itself is a tab participant. `ingest_panes()` filters it via `p.is_plugin`, but a rapid-spawn loop produces many intermediate states where deck assignments are mid-flight. If the operator presses a deck key during this window, they may jump to a line whose deck key was just reassigned.

**How to avoid:**
- The selection anchor is already identity-based (`selected_line_id: Option<LineId>`) — this is the right foundation. Confirm no regression: after spawning N panes, the selection must still resolve to the pre-spawn line (not the first row).
- Do not attempt to "wait for all N PaneUpdates before committing deck assignments" — the host gives no batch-complete signal, and WASM plugins have no async/await. Accept that deck assignments trickle in.
- Add a unit test: `spawn_n_panes_selection_does_not_drift` — simulate N sequential `ingest_panes` calls each adding one line; assert selection stays on the pre-existing line throughout.
- For the deck-key-mid-burst window: there is no clean fix without a pending-spawn counter, but the risk is low because deck keys only change for *new* lines; existing lines keep their key for life (`deck.assign()` is idempotent).
- "Spawn a board then fill it" compounds this: if `new_tab()` and pane spawns are issued rapidly, `TabUpdate` and `PaneUpdate` events arrive interleaved, not ordered. Do not assume a board is "current" until a `TabUpdate` confirms it.

**Warning signs:**
- After pressing a spawn verb with count=5, the selection cursor visually moves without the operator navigating.
- A deck key pressed immediately after spawning jumps to a wrong line.
- Unit tests that simulate rapid sequential `ingest_panes` calls reveal selection oscillation.

**Phase to address:** Phase implementing multi-spawn (verb+count N>1); the single-spawn (N=1) case is already covered by v0.1's identity anchor.

---

### Pitfall 3: Default-Command Failure Does Not Close the Pane (No-Kill Discipline)

**What goes wrong:**
When `command = ["claude"]` and `claude` is not on PATH in the pane's environment, `open_command_pane` creates the pane, the shell/exec call fails immediately, and the pane enters an "exited" state (Zellij shows its "command wrapper" UI with exit status). The plugin receives `CommandPaneExited(id, Some(127), ctx)` (or `PaneUpdate` with `exited: true`). The naive response — closing the pane to clean up — violates the no-kill discipline and is test-enforced to be impossible.

**Why it happens:**
The no-kill guard (`grep -r 'close_' crates/switchtail-plugin/`) exists precisely to prevent the plugin from destroying panes the operator did not explicitly close. The operator may have mistyped a command and wants to see the error, re-run, or preserve the pane for inspection. Silently closing it removes their work artifact.

Additionally, `open_command_pane` (as opposed to `open_terminal`) runs through Zellij's command-pane lifecycle: the pane stays open showing exit status, the user can press `Enter` to re-run. The plugin should not interfere with this lifecycle.

**PATH environment note:** Zellij issue #3924 (and related #3856) documents that `new-tab` and `open_command_pane_*` do not guarantee full environment inheritance. The `claude` binary may be on the interactive login PATH (e.g. via `.bashrc` / fish `config.fish` initialization) but absent in the subprocess environment if Zellij was launched with a trimmed environment. This is a real risk for the default-agent feature.

**How to avoid:**
- When a `CommandPaneExited` (exit_status = 127, or `exited: true` in `PaneUpdate`) is detected for a spawned line, log a ring-level call log entry: "line N exited immediately (127 — command not found?)" using the existing `CallKind::LineExited` path. This surfaces the failure on the operator's call log without touching the pane.
- Never emit `close_*` or `kill_*` intents. The no-kill guard in `intent.rs` and the test grep already enforce this; the adapter has no such shim. Maintain this invariant.
- For the PATH problem: document in the plugin config that `line_command` should be an absolute path (e.g. `/home/user/.local/bin/claude`) or a wrapper script on a guaranteed PATH, not a bare name. The `env` workaround (`CommandToRun::new_with_args("env", vec!["PATH=/…", "claude"])`) is available but verbose.
- Optionally: attempt `which claude` resolution at plugin `load()` time via a `ReadSessionEnvironmentVariables` permission query — but this permission is currently withheld. If added for this purpose, it is an owner decision.
- `open_terminal` (no command) is always safe from this failure mode — it opens a shell that inherits PATH and never exits immediately.

**Warning signs:**
- `PaneUpdate` for a spawned line arrives with `exited: true` and `exit_status: Some(127)` within a second of spawn.
- The call log shows `LineExited` for a new line immediately after `LineOpened`.
- A bare `claude` command in a fresh shell returns "command not found" (test this at the terminal before configuring the plugin).

**Phase to address:** Phase implementing default-command spawn (first slice of v0.2). Must be addressed before shipping, because the default is `claude`, which may silently not work.

---

### Pitfall 4: Board Targeting — Spawned Pane Lands on the Wrong Tab

**What goes wrong:**
`open_terminal()` and `open_command_pane()` spawn on the **currently focused tab**, not necessarily on the board the operator intends. The SwitchTail plugin is floating (`floating true` in the keybind config). When the operator presses the spawn verb from inside the plugin UI, the focused tab is the tab that was active *before* the plugin floated up — which may not be the board the operator wants the new line on.

For the "spawn a board (tab) then fill it" use case, if `new_tab()` is called and the operator immediately issues `open_terminal()` in the same dispatch cycle, the tab switch has not yet been reflected in `TabUpdate`. The terminal will open on the *previously* focused tab, not the new board.

**Why it happens:**
`open_terminal` routes to the active tab of the requesting client (confirmed by Zellij's Screen routing: "route ScreenInstruction messages to the active tab of the requesting client"). When the plugin is floating, the active tab for the client is the underlying tab, not the plugin's hypothetical "home tab". The `_near_plugin` variants spawn on the plugin's own tab (the tab where the plugin pane is resident), which is likely not where the operator wants the new line either.

**How to avoid:**
- For spawning a line on the current board: use plain `open_terminal()` / `open_command_pane()`. The currently focused tab is the right default — the operator is looking at it when they invoked the plugin. This is probably correct as-is for the single-board use case.
- For spawning a line onto a specific board other than the current one: there is no direct API. The workaround is: `focus_tab_with_index(target)` (or equivalent), then `open_terminal()`. But this changes focus, which the operator may not want. For v0.2, scope this to "spawn on current board" only, which is unambiguous.
- For "spawn board + fill it": do not assume the board is current after `new_tab()`. The `TabUpdate` event confirming the new tab's `position` and `active` state has not arrived yet. Gate pane spawning for the new board on receiving a `TabUpdate` with the expected board position. This requires a "pending board" state in `Exchange` — or simply defer "fill a new board" to a later milestone.
- The plugin's own pane is always visible in `PaneManifest` but is filtered out by `p.is_plugin` in `ingest_panes()` — this is correct and must remain so. Do not accidentally spawn a line that replaces or overlaps the plugin pane's slot.

**Warning signs:**
- Spawned pane appears on the wrong tab (operator sees nothing on the intended board, but a pane appeared elsewhere).
- After spawning a board + fill in one gesture, the fill lands on the pre-existing tab.
- `ingest_panes` processes the new line with `board` field pointing to the wrong tab index.

**Phase to address:** Phase implementing board-spawn (`b` / `B` verb). Single-board line-spawn is lower risk; multi-board "fill new board" is the hard case and should be deferred or gated on TabUpdate confirmation.

---

### Pitfall 5: Deck Exhaustion — Spawning Past 10 Lines Silently Leaves Lines Undeck-able

**What goes wrong:**
`DECK_KEYS: [char; 10]` gives exactly 10 slots (`'1'`–`'9'`, `'0'`). `deck.assign()` returns `None` when all 10 are occupied. The exchange already handles this gracefully (lines without deck keys are reachable via selection only), but with a count-spawn verb, the operator can easily request 50 or 100 lines in a single gesture. Beyond 10, all new lines are undeck-able — one-press jump is no longer available for them.

This is not a crash, but a UX surprise. More critically: if a count-spawn is used to populate a board with agent lines, and the operator's mental model is "one key per line," they will be confused when lines 11–50 have no deck key.

**Why it happens:**
The deck is intentionally finite (10 keys, numpad-friendly). `deck.assign()` returning `None` is an explicit design: "deck full — line reachable via selection only". The current `key()` dispatch has no guard against spawning past the deck limit.

**How to avoid:**
- Enforce a spawn-count cap in core before issuing `OpenLine` intents. Recommended cap: `min(count, DECK_KEYS.len() - current_deck_size)` — spawn only as many as fit in the deck from the current occupancy. Alternatively, a hard cap of 10 total lines (deck-sized world) — but this may be too restrictive for a fleet manager.
- Cleaner alternative: allow spawning past 10 but surface a CB-safe warning in the call log when the count would exceed available deck slots: "spawning N lines; M will not have deck keys (deck is full at 10)." Use amber text and a text label, not a red indicator.
- For large counts (>= 50): log the warning, execute the spawn in batches of a few at a time to avoid a PaneUpdate flood that hammers the render loop. In practice, 50 sequential `open_terminal()` calls in a single `dispatch()` loop is unexplored territory — Zellij may queue them fine, or the host may drop some. Cap at a safe number (suggest 20) pending live verification.
- The `render()` already takes a `rows` parameter and calls `view::render()` with it — if there are more lines than body rows, only `take(body_rows)` are shown. This is already implemented. Beyond-cap lines are visible only by scrolling, if scrolling is implemented.

**Warning signs:**
- `deck.assign()` returns `None` for a newly spawned line (visible in a unit test that spawns 11 lines and checks the 11th).
- A count-spawn of 15 creates 15 lines but only 10 have deck keys — the call log should have warned.
- Render output shows only the first N lines (body-rows-limited) with no scroll indicator.

**Phase to address:** Phase implementing verb+count > 1 (multi-spawn). The cap and warning must be in core, not in the adapter.

---

### Pitfall 6: Board-Spawn Requires Verifying Permission Coverage

**What goes wrong:**
`new_tab()` (the Zellij API for creating a new tab/board) is covered by `ChangeApplicationState` permission, which SwitchTail v0.1 already declares. However, if the board-spawn feature also needs `open_command_pane_in_new_tab` or similar variants, verify that `OpenTerminalsOrPlugins` is also in scope (it is, in v0.1). The risk is that a new API call fails silently at runtime with no error surface — permission denials in Zellij plugins often result in a no-op with no event delivered back.

**Why it happens:**
Permissions are declared in `load()` and granted once interactively. If v0.2 calls an API that requires a permission not declared (e.g., `RunCommands` for running a shell wrapper), the call is silently dropped. The grant cache at `<cache>/zellij/permissions.kdl` must be cleared and re-granted when new permissions are added — otherwise old sessions silently reject the new calls.

**How to avoid:**
- Before any new API call in v0.2, grep the vendored crate source to confirm which permission it guards. Do not assume from docs.
- Adding a permission is an owner decision (per CLAUDE.md). Document the decision in `PROJECT.md` key decisions before merging.
- When testing a new permission, clear `~/.cache/zellij/permissions.kdl` (or the `XDG_CACHE_HOME` equivalent) to force re-grant. The e2e harness pre-seeds an isolated cache — update it when permissions change.
- **CORRECTED 2026-06-13:** `open_command_pane` requires **`RunCommands`** (verified against Zellij's official command reference — NOT `OpenTerminalsOrPlugins`; the earlier claim here was wrong). Owner decision: v0.2 **declares `RunCommands`** to spawn `claude` lines natively (see PROJECT.md key decisions + research/STACK.md). So the grant cache MUST be cleared/re-seeded for the new permission. `open_command_pane_in_new_tab` (board spawn) needs only `ChangeApplicationState`, already declared.

**Warning signs:**
- A spawn call returns `None` (for `open_terminal` / `open_command_pane`) with no pane appearing and no log entry.
- `PermissionRequestResult` event delivers a denial at startup.
- The plugin `load()` is not requesting the needed permission.

**Phase to address:** Before first board-spawn implementation. Verify at the vendored source before touching the permission list.

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Storing spawn count as a raw `u8` in `Exchange` | Simple | If count grammar grows (e.g., `3b` for 3 boards, `3l` for 3 lines), need separate counters per verb | Acceptable if the count state is per-verb-pending, cleared on commit/abort |
| Spawning lines in a tight loop without a pending counter | Simpler dispatch | Cannot distinguish "spawn in progress" from "stable state"; deck-key-mid-burst is unguarded | Acceptable for v0.2 single-board line spawn; revisit for multi-board |
| Using `open_terminal(cwd)` instead of `open_command_pane(claude)` as a fallback | No PATH issue | Operator gets a shell, not an agent | Acceptable as opt-out (`bare` flag), not as silent fallback on 127 |
| Putting the count cap in the adapter rather than core | Simpler | Not unit-testable | Never — caps belong in core |

---

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| `open_command_pane` with `claude` | Passing bare `"claude"` and assuming PATH | Verify at `load()` or require absolute path in config; log clearly on exit 127 |
| `new_tab()` then immediate pane spawn | Assuming the new tab is focused before `TabUpdate` | Gate pane spawn on `TabUpdate` confirming new tab active, or scope to "current board only" in v0.2 |
| Permission grant cache | Testing with the old cache after adding a permission | Clear `XDG_CACHE_HOME/zellij/permissions.kdl` or use e2e isolated cache |
| `open_terminal_near_plugin` vs `open_terminal` | Using near-plugin variant thinking it targets the "current board" | Near-plugin spawns on the plugin's resident tab; plain `open_terminal` targets the focused tab — usually what the operator wants |
| Environment variables for `open_command_pane` | Passing env via `CommandToRun` struct fields | There is no env field on `CommandToRun` (issue #3856); use `env KEY=VAL cmd` workaround or absolute paths |

---

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| N sequential `open_terminal()` calls in one `dispatch()` | Host queues N ScreenInstructions; N PaneUpdate events each trigger full `ingest_panes()` + `render()` | Cap at 20; log warning above threshold | Untested above ~10; Zellij memory leak issues (#3598) suggest caution above 50 panes total |
| `ingest_panes` O(N) `seen.contains()` on large line sets | Render lag as fleet grows | Switch `seen` to a `HashSet<LineId>` inside `ingest_panes` | Noticeable above ~50 lines; current `Vec::contains` is O(N) per pane |
| Re-rendering on every PaneUpdate during N-spawn burst | N renders during a burst of 10 spawns | `update()` already returns `bool` to gate render; ensure `ingest_panes` returns non-empty intents only on real changes | Cosmetic jank; not a crash |
| WASM debug build memory | debug wasm is larger; slower JIT | This box already deploys debug wasm by owner decision (release-lto SIGSEGV); no regression from v0.2 | Not applicable — debug wasm is the production artifact here |

---

## UX Pitfalls

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| No feedback while N lines are spawning | Operator unsure if keypress registered; may press again | Show a "spawning N…" transient in the call log or header immediately on verb commit, before PaneUpdates arrive |
| Count entry has no visible echo | Operator types `1`, `5` but sees nothing until commit | Render the accumulated count in the header/status bar during count-entry mode |
| Exit-127 pane left open with no log entry | Operator doesn't know claude is missing | Log `LineExited` as ringing-level with a note "exit 127 — command not found?" |
| CB-unsafe spawn feedback | Progress bar or error in red | Use amber text labels, deck-key character glyphs, and text count ("3/5 lines spawned") — never red/green |
| Esc aborts a partial count unexpectedly | Operator pressed Esc to dismiss plugin, aborts count instead | Esc in count-entry mode should first abort the count; a second Esc (back in normal mode) hides the plugin. This is consistent with how `i` prompt works (Esc cancels the prompt, not the whole plugin). |

---

## "Looks Done But Isn't" Checklist

- [ ] **Digit-key routing:** Pressing `3` during count-entry accumulates, does not `FocusLine(deck_slot_3)`. Test with a line on slot 3.
- [ ] **Count state clears on commit AND abort (Esc):** After a spawn gesture, `count_state` is `None` and normal mode resumes.
- [ ] **Selection identity after N-spawn:** Pre-existing selected line is still selected after 5 sequential `ingest_panes` calls adding one new line each.
- [ ] **Exit-127 log entry:** Spawning `open_command_pane(CommandToRun::new("/nonexistent"))` results in a `LineExited` call log entry, not a silent disappearance.
- [ ] **No close_* in adapter:** `grep -r 'close_\|kill_' crates/switchtail-plugin/src/` returns zero matches (the existing no-kill test already gates this).
- [ ] **Deck exhaustion warning:** Spawning 11 lines results in a call log warning; the 11th line has no deck key; the plugin does not crash.
- [ ] **Board-spawn on correct tab:** A line spawned via the plugin lands on the tab that was focused *before* the plugin floated up, not on the plugin's own tab.
- [ ] **Permission grant re-seeded:** After adding any new permission, the e2e cache and `permissions.kdl` are updated to include the new grant.
- [ ] **Debug-wasm only:** `tools/dev.sh reload` deploys the debug artifact. Release wasm is never attempted on this box.

---

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Digit-key collision discovered post-merge | MEDIUM | Add `count_state` gate to `key()`, rewrite test suite for count-entry; core-only change |
| Selection drift under N-spawn | LOW | Already anchored by identity; add regression test; no architectural change needed |
| Default command fails silently | LOW | Add `CommandPaneExited` subscription in `load()`, emit call log entry on exit_status 127; no pane close |
| Pane lands on wrong tab | MEDIUM | Scope v0.2 to current-board-only; defer multi-board fill; no API workaround without focus-change |
| Deck exhaustion at 10 | LOW | Add cap + warning in core before `OpenLine` loop; one function change |
| Permission silent no-op | LOW | Grep vendored source for permission guard; add to `load()` permission list; re-grant interactively |

---

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| Digit-key vs. deck collision | Phase: verb+count grammar (first slice) | Core unit test: `count_entry_digits_do_not_focus_lines`; test the `'0'` deck key explicitly |
| Async spawn reconciliation / selection drift | Phase: multi-spawn (N>1) | Core unit test: N sequential `ingest_panes` calls; assert `selected_line()` stable |
| Default-command exit-127 / no-kill | Phase: default-command spawn | Subscribe `CommandPaneExited`; assert no close_* shims; test with invalid command path |
| Board targeting wrong tab | Phase: board-spawn verb | Manual smoke: spawn line from floating plugin, confirm tab; defer multi-board fill |
| Deck exhaustion | Phase: multi-spawn (N>1) | Core unit test: spawn 11, assert deck warning log entry and 11th line has no deck key |
| Permission coverage for new_tab | Phase: board-spawn verb | Grep vendored source before PR; clear permissions.kdl; e2e confirms pane appears |
| Release-wasm SIGSEGV (pre-existing) | ALL phases | Gate: `tools/dev.sh build && tools/dev.sh reload` only; NEVER `cargo build --release` on this box |

---

## Sources

- `/home/jangmanj/JangLabs/switchtail/crates/switchtail-core/src/deck.rs` — DECK_KEYS constant, `assign()` returns None on full deck
- `/home/jangmanj/JangLabs/switchtail/crates/switchtail-core/src/exchange.rs` — `prompt_key()` sub-state pattern (v0.1 analog); `ingest_panes()` reconciliation; `selected_line_id` identity anchor; v0.1 regression tests for selection drift
- `/home/jangmanj/JangLabs/switchtail/crates/switchtail-core/src/intent.rs` — No-kill discipline, `HostIntent` enum, `OpenLine` shape
- `/home/jangmanj/JangLabs/switchtail/crates/switchtail-plugin/src/main.rs` — `dispatch()` loop, `OpenLine` shim, `open_command_pane` call site
- `/home/jangmanj/JangLabs/switchtail/docs/zellij-api-notes.md` — Verified API signatures, `CommandToRun`, `open_terminal` / `open_command_pane`, permission list, empirical gotchas
- `/home/jangmanj/JangLabs/switchtail/CLAUDE.md` — No-kill discipline, CB-safe color rules, build hygiene (debug-only wasm, CARGO_BUILD_JOBS=4)
- Zellij documentation — [Plugin Lifecycle](https://zellij.dev/documentation/plugin-lifecycle) (async event ordering; no guaranteed delivery order)
- Zellij documentation — [Plugin API Commands](https://zellij.dev/documentation/plugin-api-commands.html) (`new_tab`, `open_terminal`, `_near_plugin` variants, tab targeting)
- Zellij documentation — [Plugin API Permissions](https://zellij.dev/documentation/plugin-api-permissions.html) (`ChangeApplicationState` covers tab creation)
- GitHub issues: [#3856 — no env vars in open_command_pane](https://github.com/zellij-org/zellij/issues/3856), [#3924 — PATH not inherited in new-tab](https://github.com/zellij-org/zellij/issues/3924), [#3864 — memory failure on new tab in constrained environments](https://github.com/zellij-org/zellij/issues/3864)
- Zellij [Colliding Keybindings tutorial](https://zellij.dev/tutorials/colliding-keybindings/) — key routing architecture; `InterceptInput` vs. normal `Key` event delivery

---
*Pitfalls research for: SwitchTail v0.2 live in-plugin composition (Zellij plugin, wasm32-wasip1, zellij-tile 0.44.3)*
*Researched: 2026-06-13*
