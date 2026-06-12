---
status: diagnosed
trigger: "SwitchTail seat swap (`s` key) does not perform a true positional exchange. UAT gap from Phase 4."
created: 2026-06-12T00:00:00Z
updated: 2026-06-12T16:00:00Z
---

## Current Focus
<!-- OVERWRITE on each update - reflects NOW -->

hypothesis: "CONFIRMED: replace_pane_with_existing_pane(seat, line, suppress=true) is by host construction a one-way 'bring pane here' (pane-picker primitive), not an exchange. Host source (exact installed commit e9173cb) proves: line is extracted from its slot (slot collapses / tab may auto-relayout), line takes seat's geometry, seat goes into suppressed_panes (hidden, unplaced). Layout changes, panes do not trade places."
test: "Verified against zellij-server source at the exact installed host commit (zellij-git 0.44.1.r33.ge9173cb from CachyOS): screen.rs:4486 replace_pane_with_existing_pane, tab/mod.rs:4069 extract_pane, tab/mod.rs:2337 suppress_pane_and_replace_with_other_pane."
expecting: "n/a — investigation complete"
next_action: "Return ROOT CAUSE FOUND to orchestrator (goal: find_root_cause_only — no fix applied)"

## Symptoms
<!-- Written during gathering, then IMMUTABLE -->

expected: "`m` marks the selected line as the seat. Selecting another line and pressing `s` swaps it into the seat position. A true positional exchange: the two panes trade places precisely, overall layout unchanged."
actual: "User reported: the swap should cause both windows to exchange their positions precisely so that the layout remains the same but the terminals have traded places — current behavior does not do this."
errors: None reported
reproduction: "Test 4 in .planning/phases/04-operator-polish-e2e/04-UAT.md"
started: "Discovered during UAT 2026-06-12. Known pre-existing concern in .planning/STATE.md — swap shipped using replace_pane_with_existing_pane with suppress=true; true positional-swap semantics never confirmed empirically."

## Eliminated
<!-- APPEND only - prevents re-investigating -->

- hypothesis: "zellij-tile 0.44.3 offers a direct arbitrary-pair swap_panes(a, b) primitive that was overlooked"
  evidence: "Exhaustive grep of all `pub fn` in vendored zellij-tile-0.44.3/src/shim.rs (180+ functions). Only 'swap' hits are previous_swap_layout/next_swap_layout (preset layout cycling — unrelated). No swap_panes(a,b) exists in this SDK version."
  timestamp: 2026-06-12

## Evidence
<!-- APPEND only - facts discovered -->

- timestamp: 2026-06-12
  checked: "crates/switchtail-core/src/exchange.rs lines 234-258 (m/s key handling)"
  found: "Core logic is correct per design: `m` sets seat, `s` emits exactly HostIntent::SwapIntoSeat{seat, line} when both exist and differ. Core decides nothing about HOW the swap happens — that is the adapter's job."
  implication: "Bug is not in core model logic; it is in what the intent maps to at the host boundary."

- timestamp: 2026-06-12
  checked: "crates/switchtail-plugin/src/main.rs lines 123-128 (dispatcher arm)"
  found: "SwapIntoSeat dispatches as a SINGLE call: replace_pane_with_existing_pane(term(seat), term(line), true). In-code comment admits: 'True positional swap is a post-v0.1 refinement pending empirical E2E.'"
  implication: "The swap is implemented as a one-way replace with suppression, never as a two-way exchange. This was a known shortcut, now empirically falsified by UAT."

- timestamp: 2026-06-12
  checked: "Vendored ~/.cargo/registry/src/*/zellij-tile-0.44.3/src/shim.rs:2711 and zellij-utils-0.44.3/src/data.rs:3546"
  found: "replace_pane_with_existing_pane(pane_id_to_replace, existing_pane_id, suppress_replaced_pane) → PluginCommand::ReplacePaneWithExistingPane. Client side is a dumb forwarder; no positional-exchange semantics promised anywhere. Param name is literally 'suppress_replaced_pane' — the replaced pane is suppressed (hidden), not relocated."
  implication: "By construction this call moves ONE pane (line) into the seat's slot and HIDES the seat pane. The seat pane never lands in line's old slot; line's old slot is vacated and the tiled layout re-flows to fill the hole. Layout is NOT preserved and panes do NOT trade places."

- timestamp: 2026-06-12
  checked: "Full shim surface scan of zellij-tile 0.44.3 (all pub fn in shim.rs) for positional primitives"
  found: "Candidates that exist: (1) move_pane_with_pane_id(pane_id) — doc: 'Switch the position of the pane with this id with a different pane' (host picks the partner — not arbitrary-pair); (2) move_pane_with_pane_id_in_direction(pane_id, direction) — doc: 'Switch the position of the pane with this id with a different pane in the specified direction' — a TRUE positional swap but only with the ADJACENT pane in a direction; (3) run_action(Action, ctx) — Action enum has MovePaneByPaneId{pane_id, direction} (same adjacency limit; also likely needs withheld RunActionsAsUser permission); (4) override_layout / dump_session_layout — whole-layout rewrite (heavy); (5) change_floating_panes_coordinates — floating panes only."
  implication: "No single arbitrary-pair swap primitive exists in zellij-tile 0.44.3. A true positional exchange must be composed."

- timestamp: 2026-06-12
  checked: "Installed host identity: pacman -Qi zellij → zellij-git 0.44.1.r33.ge9173cb-1 (CachyOS repo). Self-reports 0.45.0 but is actually upstream main at commit e9173cb."
  found: "Fetched zellij-server source at that EXACT commit from GitHub (raw.githubusercontent.com/zellij-org/zellij/e9173cb)."
  implication: "Host-side semantics below are verified against the literal code the installed binary was built from — not training data, not docs."

- timestamp: 2026-06-12
  checked: "zellij-server/src/screen.rs:4486 replace_pane_with_existing_pane (host handler, commit e9173cb)"
  found: "Handler does exactly three things: (1) finds both tabs; (2) extract_pane(existing_pane_id, true) — rips the line OUT of its tab's layout and returns it as Box<dyn Pane>; (3) with suppress=true calls tab.suppress_pane_and_replace_with_other_pane(seat, extracted_line) — line gets seat's geometry via tiled_panes.replace_pane(), and the seat pane is pushed into the tab's suppressed_panes map (tab/mod.rs:2337-2356). With suppress=false the seat pane would be CLOSED instead. In neither case is the seat pane ever placed into the line's old slot."
  implication: "ONE-WAY replace by construction. Web docs corroborate: the primitive exists for 'pane pickers' (bring-that-pane-here), not exchanges."

- timestamp: 2026-06-12
  checked: "zellij-server/src/tab/mod.rs:4069 extract_pane (commit e9173cb), tiled branch"
  found: "tiled_panes.remove_pane(id) removes the pane; the vacated geometry is reclaimed by neighbors (standard close-reflow), and if auto_layout is on and the swap-layout is undamaged it triggers relayout_tiled_panes — the WHOLE TAB can snap to the next layout template."
  implication: "The line's old slot is destroyed the moment the swap starts. Layout visibly changes — directly contradicts 'overall layout unchanged'. This is the second half of the broken UX (first half: seat pane vanishes into suppression)."

- timestamp: 2026-06-12
  checked: "Exhaustive PluginCommand enum scan (vendored zellij-utils-0.44.3 data.rs, full enum) + suppressed-pane addressability (tab/mod.rs has_pane_with_pid:2682 includes suppressed_panes; extract_pane third branch can extract FROM suppressed_panes; open_terminal_pane_in_place_of_pane_id shim doc: close_replaced_pane=false ⇒ replaced pane suppressed and restored when the new pane closes)"
  found: "No SwapPanes/exchange variant exists anywhere in the plugin command surface. But a composed true swap IS expressible: suppressed panes remain addressable by pid for later replace calls, and the in-place-of-pane-id open variants can pin a slot with a placeholder before extraction collapses it."
  implication: "Fix is achievable inside the existing declared permissions; see Resolution.fix direction."

- timestamp: 2026-06-12
  checked: "Cross-link to second UAT gap (ring/R mistargeting) — exchange.rs:64 `selected: usize`, :470-472 selected_line() = sorted_lines().get(self.selected)"
  found: "Selection is a POSITIONAL INDEX into the sorted line list, not a LineId. A swap mutates the PaneUpdate manifest (seat line becomes suppressed:true at line.rs sync exchange.rs:142, focus and geometry change), so any resulting reorder of sorted_lines() silently retargets the same index to a different line."
  implication: "Plausible shared-state mechanism behind the ring mistargeting the user suspected was 'related to the swap'. NOT this session's deliverable — flagged for the parallel ring investigation."

## Resolution
<!-- OVERWRITE as understanding evolves -->

root_cause: "The seat swap is implemented as a single replace_pane_with_existing_pane(seat, line, suppress=true) call (crates/switchtail-plugin/src/main.rs:127), but that zellij primitive is by host construction a ONE-WAY 'bring pane here' operation (built for pane pickers), not a positional exchange. Verified at the installed host's exact source commit (zellij-git 0.44.1.r33.ge9173cb): the host (a) extracts the line from its slot — destroying that slot via close-reflow and possibly auto-relayouting the whole tab (tab/mod.rs:4069 extract_pane → tiled_panes.remove_pane), (b) places the line into the seat's geometry, and (c) shoves the seat pane into the tab's invisible suppressed_panes map (tab/mod.rs:2337 suppress_pane_and_replace_with_other_pane) — it is never placed into the line's old slot. Net: one pane visible where two were, layout geometry changed, seat pane hidden. No swap_panes(a,b) primitive exists anywhere in the zellij plugin API (exhaustive PluginCommand enum scan), so no single-call fix is possible — the one-call implementation was inherently incapable of expressing the designed semantics."
fix: "(diagnose-only session — fix direction for planner) Option A (recommended, fully within declared permissions): compose the exchange in 3 host calls — (1) open_terminal_pane_in_place_of_pane_id(line, cwd, close_replaced_pane=false) to pin the line's slot with a throwaway placeholder P (line becomes suppressed but stays pid-addressable: has_pane_with_pid includes suppressed_panes and extract_pane has a suppressed-pane branch); (2) replace_pane_with_existing_pane(seat, line, suppress=true) — line takes seat's slot, seat suppressed; (3) replace_pane_with_existing_pane(P, seat, suppress=false) — seat takes P's slot (= line's original slot) and the placeholder P is closed (note: suppress=false closes OUR OWN placeholder only; owner must bless this vs the no-kill discipline; the no-kill grep targets close_* call-site names and would not fire). Sequence must be E2E-verified live for FIFO ordering and the suppressed-restore edge when P closes. Option B (cheap special case): when seat and line are geometrically adjacent (PaneInfo pane_x/pane_y/pane_columns/pane_rows), a single move_pane_with_pane_id_in_direction(line, dir_toward_seat) IS a true positional swap — could handle the common case without placeholders. Option C (fallback, heavy): dump_session_layout_for_tab + override_layout whole-layout rewrite."
verification: "Root cause verified by static source analysis at the exact installed host commit (no builds permitted this session). Fix candidates NOT yet verified live — STATE.md already flags that live E2E confirmation is required."
files_changed: []
