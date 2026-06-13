---
status: resolved
resolved_in: 04-05
resolved_date: 2026-06-13
resolution: "Fixed by identity-anchored selection (Option<LineId> / call seq) in 04-05. Live-verified 2026-06-13: R keeps the cursor glued to the rung line through the RingingFirst re-sort; a clears it to zero ringing lines."
trigger: "ring-targets-wrong-line: SwitchTail ring action (R key) does not consistently surface on the line the operator actually selected. UAT gap from Phase 4."
created: 2026-06-12T15:46:50-07:00
updated: 2026-06-13T00:00:00-07:00
---

## Current Focus
<!-- OVERWRITE on each update - reflects NOW -->

hypothesis: CONFIRMED — selection cursor is a bare usize index into a re-sortable view; the view reorders underneath the cursor (most violently: RingingFirst sort re-sorts the moment R lands), so subsequent and even concurrent actions resolve to the wrong line.
test: complete (static trace of R/a/p/s/m/i/Enter through selected_line(); list-dump order matched against all three SortModes)
expecting: n/a
next_action: Return ROOT CAUSE FOUND diagnosis (goal: find_root_cause_only — no fix in this session).

## Symptoms
<!-- Written during gathering, then IMMUTABLE -->

expected: "`R` rings the selected line: the target pane gets an amber tint + highlight. `a` (answer) or `p` (park) clears it."
actual: "Not consistently selecting the correct window/terminal for ring; perhaps related to the swap function issue from earlier in the testing session."
errors: None reported
reproduction: Test 6 in .planning/phases/04-operator-polish-e2e/04-UAT.md
started: Discovered during UAT 2026-06-12, after user exercised seat-swap (m+s) and sort cycling (o).
corroborating: Live {"op":"list"} pipe dump showed lines 0 AND 2 both ringing:true (user intended one). JSON array order was deck_key "1" (line 0), "3" (line 2), "2" (line 1), "4" (line 4) — rendered/iterated order matches NEITHER line-id order NOR deck-key order. Line id 3 absent (closed pane) — sparse ids.

## Eliminated
<!-- APPEND only - prevents re-investigating -->

- hypothesis: "R resolves the wrong line at the instant of the keypress (render order != action-resolution order at the same moment)"
  evidence: "view.rs render_directory and exchange.rs selected_line() both index the SAME sorted_lines() with the same ex.selected — at any single instant the inverted row and the resolved LineId agree. The divergence is strictly ACROSS TIME (view reorders between render/keypress or between two consecutive actions)."
  timestamp: 2026-06-12T15:55

- hypothesis: "Adapter mistargets the host pane (TintLine/HighlightLines map to wrong PaneId)"
  evidence: "HostIntent::TintLine/HighlightLines carry stable LineIds; main.rs term() maps LineId(n) -> PaneId::Terminal(n) with no index involved. set_pane_color / highlight_and_unhighlight_panes / focus_pane_with_id signatures verified against docs/zellij-api-notes.md lines 47-57 (pinned 0.44.3 facts). No index->id conversion exists in the adapter."
  timestamp: 2026-06-12T15:55

- hypothesis: "Deck key handling collides with action keys (R/a/p resolved via deck.line_for)"
  evidence: "DECK_KEYS are digits '1'..'0' only (deck.rs:9); exchange.rs:194 guard `deck.line_for(c).is_some()` can never match letters, so R/a/p always reach their own arms."
  timestamp: 2026-06-12T15:55

## Evidence
<!-- APPEND only - facts discovered -->

- timestamp: 2026-06-12T15:56
  checked: full key->action trace + concrete repro reconstruction with the dump's deck layout
  found: |
    Repro (sort=RingingFirst, lines [0(k1),1(k2),2(k3),4(k4)], no ringers):
    1. j,j -> selected=2 -> cursor on line 2. Press R.
    2. selected_line() -> line 2 (correct). Ring placed; refresh_ring_flags().
    3. sorted_lines() now [2(ringing),0,1,4]; selected stays 2 -> cursor silently now on line 1.
    4. Press a (per Test 6 "a clears it") -> settle_selected -> settles line 1 (no-op). Line 2 keeps ringing; amber never clears.
    5. Operator concludes mistarget, moves to intended pane, presses R again -> a SECOND line rings.
    End state: two lines ringing simultaneously == the exact live dump (lines 0 & 2 ringing, RingingFirst order).
  implication: Mechanism fully reproduces both the reported behavior and the corroborating pipe dump.

- timestamp: 2026-06-12T15:56
  checked: grep for every write/read of Exchange.selected
  found: "`selected` is only ever: reset to 0 (Tab, o), inc/dec (j/k/Up/Down), length-clamped (clamp_selection). NO code re-anchors it to a stable LineId when the view reorders. ALL action consumers (Enter-focus, m seat, s swap, i say, a/p settle, R ring) resolve via selected_line()/selected_call_seq() = index into the re-sortable view."
  implication: Single shared root cause across focus/seat/swap/say/triage — including the separately-tracked seat-swap gap's targeting component.

- timestamp: 2026-06-12T15:57
  checked: secondary aggravators
  found: |
    (a) Log view has the same bug class: selected_call_seq() indexes log_view_calls(), which in
        RingingFirst sort reorders as triage flips (Enter answers -> re-sort under cursor).
    (b) clamp_selection() clamps to lines.len(), but render shows only take(body_rows) rows ->
        cursor can sit on an OFF-SCREEN row (no visible inversion) while actions still land there.
    (c) Swap suppression link (unconfirmed statically): replace_pane_with_existing_pane(suppress=true)
        suppresses the displaced pane; if suppressed panes leave the PaneUpdate manifest or become
        is_selectable=false, ingest_panes() REMOVES the line -> indices shift + deck key freed/reused.
        Live dump shows line 3 absent and its key '4' reused by line 4 — consistent with this OR a
        normal close. Host-side manifest behavior for suppressed panes is not statically verifiable
        from the vendored crate; flag for the seat-swap session / live verification.
  implication: The fix must re-anchor selection by stable identity (LineId / call seq), not just patch the R handler.
## Evidence
<!-- APPEND only - facts discovered -->

- timestamp: 2026-06-12T15:50
  checked: crates/switchtail-core/src/exchange.rs (full read)
  found: |
    Selection model: `Exchange.selected: usize` is an INDEX into the sorted view.
    `selected_line()` resolves Directory selection as `sorted_lines().get(self.selected)`.
    `sorted_lines()` order depends on `self.sort`; SortMode::RingingFirst sorts by
    `(!l.ringing, deck_rank, id)` — i.e., the order CHANGES the instant any line's
    ringing flag flips. `R` key handler: resolve selected_line() -> log.place(Ring)
    -> refresh_ring_flags() -> the just-rung line jumps to the top of the sorted view,
    while `self.selected` (the index) stays put. The cursor now silently rests on a
    DIFFERENT line. Every subsequent action (R/a/p/s/i/m/Enter) resolves through the
    same index and lands on the wrong line.
  implication: Index-into-reorderable-view selection. Re-sort-under-cursor is the prime mechanism.

- timestamp: 2026-06-12T15:50
  checked: corroborating list-dump order vs the three SortModes (static analysis)
  found: |
    Dump order: line0(key1), line2(key3), line1(key2), line4(key4), with lines 0 & 2 ringing.
    - Deck sort would give key order 1,2,3,4 -> lines 0,1,2,4. NO match.
    - Board sort would give id order 0,1,2,4. NO match.
    - RingingFirst with {0,2} ringing gives: ringing by deck_rank [line0(k1), line2(k3)]
      then non-ringing [line1(k2), line4(k4)] -> EXACT match to the dump.
  implication: User was in RingingFirst sort mode when mistargeting occurred. Confirms `o` sort cycling was active, the precondition for the re-sort-under-cursor mechanism.

- timestamp: 2026-06-12T15:50
  checked: async reorder paths in exchange.rs
  found: |
    The view can also reorder WITHOUT any user key: (a) a pipe `ring`/`status` op from an
    agent calls refresh_ring_flags() -> re-sorts under cursor in RingingFirst mode;
    (b) ingest_panes() on every host PaneUpdate removes closed lines (sparse ids 0,1,2,4
    show line 3 closed during the session), shifting all later indices up by one;
    clamp_selection() only clamps length, never tracks content. Selection is never
    re-anchored to a stable LineId across any of these.
  implication: Multiple independent reorder sources all drift the cursor; sparse-id close (line 3) very likely also moved the selection mid-session.

## Resolution
<!-- OVERWRITE as understanding evolves -->

root_cause: |
  Selection is stored as a bare row index (`Exchange.selected: usize`) into a view whose
  order is NOT stable (`sorted_lines()` / `log_view_calls()`), and nothing ever re-anchors
  the index when the order changes. The most violent reorder source is self-inflicted:
  in SortMode::RingingFirst, the `R` handler (exchange.rs:270-281) rings the line under
  the cursor, then refresh_ring_flags() flips that line's `ringing` flag, which instantly
  re-sorts it to the top of sorted_lines() (exchange.rs:456) — while `selected` keeps its
  numeric value, so the cursor lands on a DIFFERENT line. The follow-up `a`/`p` (Test 6's
  own script) then settles the wrong line; the original ring never clears; a retry rings a
  second line (matching the live dump: lines 0 & 2 both ringing, list order == RingingFirst).
  Asynchronous reorder sources compound it in every sort mode: pipe ring/status ops from
  agents (refresh_ring_flags) and ingest_panes() line removals (sparse ids 0,1,2,4 prove a
  removal happened; swap's suppress=true is a suspected removal trigger — unconfirmed).
fix: |
  (Direction only — diagnose-only session.) Re-anchor selection by stable identity instead
  of raw index: store Option<LineId> (Directory) / Option<call seq> (Log), or recompute the
  index against the new order after ANY mutation that can reorder the view (key handlers,
  pipe ops, ingest_panes). j/k navigation maps id->index, steps, maps back. Alternatively/
  additionally: make ringing-first ordering only re-sort on explicit operator action, never
  as a side effect of the action itself.
verification: n/a (no fix applied; goal find_root_cause_only)
files_changed: []
