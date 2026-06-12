# Deferred items — Phase 01

## Pre-existing test-fixture drift: renamed/removed labs (discovered during 01-01)

**Found:** 2026-06-12, while recording the pre-edit baseline for plan 01-01.

**What:** The regression suites hardcode the labs `claude` and `jangsjedi`, but the
live workspace changed on 2026-06-11: the `claude` lab was renamed to `synapse`
(repo `JangLabs-Claude` → `JangLabs-Synapse`) and `jangsjedi` was removed entirely.
Current `_discover_labs` output: `agent jangsjyro proton switchtail synapse`.

**Effect:** 35 pre-existing assertion failures, present BEFORE any 01-01 edit and
byte-identical after it (verified):

| Suite | Baseline | Failure cause |
|---|---|---|
| stail-test-1.sh | 24 passed, 1 failed | `generate` lab-set assertion expects `agent claude jangsjedi jangsjyro proton` |
| stail-test-2.sh | 13 passed, 3 failed | B1/B2 running-set + list --json assertions expect `claude`/`jangsjedi` panes in the exchange union |
| stail-test-3.sh | 15 passed, 0 failed | — |
| stail-test-4.sh | 18 passed, 8 failed | `cmd_trunk`/`_emit_trunk_session` fixtures use labs `claude` and `jangsjedi` (no longer valid lab dirs) |
| stail-test-5.sh | 16 passed, 23 failed | `lab=claude` patch specs fail `_patch_resolve` lab validation (lab gone) |
| stail-kitten-test.py | 27 passed, 0 failed | — |
| tail-test.py | 18 passed, 0 failed | — |

**Why not fixed in 01-01:** out of scope — failures are not caused by this plan's
mechanical STAIL_BIN substitution (executor scope boundary: unrelated pre-existing
test failures are logged, not fixed). 01-01's action text also explicitly forbids
fixture changes ("Mechanical substitution ONLY").

**Impact on the phase:** every later plan's "ALL SUITES PASSED" / "147-assertion
baseline green" verification gate is unattainable until the fixtures are re-pointed
at the current lab set (`claude`→`synapse` as a *lab* name; `kind=claude` rows are
unaffected — `claude` remains a valid agent *kind*; `jangsjedi` fixtures need a
surviving lab substitute). Note the kind-vs-lab distinction when fixing: only
`lab=`/argv lab names drift, not the kind table. Also re-check whether the
`_display_name jangsjedi` inner-cap override test should survive in bin/stail.

**Suggested resolution:** a small fixture-refresh task (planner decision: fold into
01-03's test-suite work or insert as a standalone fix) BEFORE 01-03/01-04 rely on
suite-green gates. Recorded as a blocker in STATE.md.
