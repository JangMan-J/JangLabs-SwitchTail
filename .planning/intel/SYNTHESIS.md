# Synthesis Summary

_Generated 2026-06-11 by gsd-doc-synthesizer. Mode: new (net-new bootstrap; no
existing .planning/ context). Precedence: ADR > SPEC > PRD > DOC (no overrides)._

## Doc counts by type

- ADR: 0
- SPEC: 0
- PRD: 0
- DOC: 1 — docs/direction-report-2026-06.md ("SwitchTail direction report —
  modularization timing, coupling friction, language"; confidence: medium)
- UNKNOWN: 0

Cross-ref graph: empty (no planning-doc cross-refs) — cycle detection trivially
clean.

## Extracted intel

- Decisions locked: 0 (no ADRs). See `decisions.md` — note that the DOC carries
  decision-like verdicts (timing verdict SELECTIVE; ranked spine-language
  guidance) that were deliberately NOT promoted to decisions; promote to ADRs and
  re-ingest if they should be binding.
- Requirements: 0 (no PRDs). See `requirements.md` — the DOC's "do now" items
  (kind-table slice, per-pane session-ID markers, hardenings) are candidate
  requirement material for the roadmapper, recorded under context.
- Constraints: 0 (no SPECs). See `constraints.md` — de-facto contracts (`--json`
  contract, marker protocol, window-class contract) are recorded as context, not
  normative constraints.
- Context topics: 6 (system shape and scale; friction matrix; timing verdict
  SELECTIVE with do-now list and defer-trigger table; spine-language guidance
  with trigger table; residual bias statement; bottom line). See `context.md`.

## Conflicts

0 blockers, 0 competing-variants, 0 auto-resolved.
Detail: ../INGEST-CONFLICTS.md (/home/jangmanj/JangLabs/switchtail/.planning/INGEST-CONFLICTS.md)

## Intel files

- decisions.md (ADRs — empty)
- requirements.md (PRDs — empty)
- constraints.md (SPECs — empty)
- context.md (DOCs — 6 topics, all sourced to docs/direction-report-2026-06.md)

## Pointers for the roadmapper

The single ingested doc is guidance-dense: it prescribes three immediate
low-effort work items (some already landed per repo history — kind table seam,
per-pane session-ID hold markers, emitter unification noted on the `versioning`
branch), a defer/trigger table for everything else, and a debiased language
ranking that endorses the hardened status-quo bash spine. All of it is advisory
context — nothing in the ingest set is locked.
