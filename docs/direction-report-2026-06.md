# SwitchTail direction report — modularization timing, coupling friction, language

_2026-06-10. Produced by an 18-agent adversarially-verified assessment (4 coupling-axis
analysts + 4 skeptics + cross-axis synthesis + modularize-now/defer debate with judge +
4-strategy language panel with familiarity-prior ban + bias audit). Every friction score
below is the post-adversarial corrected value, not the first-pass analyst value._

## 1. What SwitchTail is

A personal agent-cockpit system: each lab (git submodule under `~/JangLabs`) becomes a
tiled kitty window of Claude Code panes, with a numpad "deck" for focus control, a
Plasma 6 widget as launcher/introspector, and a deliberate park-to-resume lifecycle.
~1,560 source lines in five layers: a 618-line bash spine (`bin/stail`), three Python
kittens (261 lines) inside kitty's embedded interpreter, declarative kitty config,
systemd regen units, and a 530-line QML widget that talks to the system exclusively
through `stail`'s `--json` contract. Running-state detection is kdotool/KWin
window-class search — a KDE coupling independent of kitty. Two days past v1, daily
dogfooded by a single author on one CachyOS/KDE/Wayland box, 147-assertion suite green.

## 2. Premise correction: it is not "mostly Python"

The real shape is **bash 618 > QML 530 > Python 261** — and the 261 Python lines run
inside kitty's embedded interpreter, where kittens *are* Python. The language was never
chosen; kitty chose it, and it evaporates if kitty ever goes. This collapses two
questions into one: "should this stay Python?" reduces entirely to "should this stay
kitty?". Any "rewrite the kittens in X" plan is a category error. The language decision
actually owned is the bash spine.

## 3. Friction matrix (adversarially corrected; 1 = trivial, 5 = load-bearing rewrite)

| Axis | Depth | Extract | Replace | Parity | Exceed |
|---|---|---|---|---|---|
| claude CLI (agent payload) | moderate | 2 | 2 | 3 | 3 |
| kitty (mux + window model + watcher + GUI host) | deep | 3 | 4 | 3 | 2 |
| Python (the 3 kittens) | shallow (phantom axis) | 2 | 3 | 4 | 3 |
| kitty watcher (cockpit_monitor.py) | deep | 2 | 4 | 3 | 3 |

**The governing law of this codebase: coupling depth is inversely proportional to how
loudly the dependency announces itself.** The two visible dependencies are near-illusions;
the deep ones are quiet:

- `claude` the binary appears in exactly one file (`bin/stail` cmd_cockpit, two exec
  lines) and the chassis is agent-blind. The *real* Claude coupling hides in (a) the
  watcher's typed `/rename`+`/color` payload — client-side slash commands reachable only
  by typing into the running TUI; the cockpit outsources its labeling intelligence to
  the agent — and (b) the marker protocol's silent invariant that the resume argv is
  cwd-scoped like `--continue` (a globally-scoped continue would cross-wire labs).
- **The generic-kind seam leaks today**: the `'claude'` literal is duplicated into 2 of
  3 kittens (`cockpit_park.py:26`, `cockpit_monitor.py:39` `_STYLE_KINDS`). The swap
  trap is double-edged: a `kind=cmd:opencode` pane silently *loses* park/resume/styling,
  while swapping the exec argv but keeping `kind=claude` actively *gains* hostile
  behavior — Claude slash-commands typed into the foreign agent's REPL as input.
- kitty is load-bearing in **three-to-four fused roles**: multiplexer/session grammar,
  scriptable window model, in-process watcher host, plus a hidden fourth — GUI host
  terminal (rendering, `os_window_class` stamping, `.desktop` ownership, beyond-PATH
  binary resolution). The interaction layer (~28% of source: kittens + deck.conf) is a
  per-backend paradigm *rewrite*, not an adapter. Coverage: WezTerm is the only single
  tool covering all four roles; tmux covers mux+window-model but degrades the watcher to
  shell-forked hooks+polling and leaves GUI-host unfilled; Zellij needs a Rust/WASM
  plugin; Warp covers none. kitty+tmux hybrid is the cheap increment (kitty keeps
  GUI-host/watcher roles, tmux adds detach).
- The session grammar regenerates from **three emitters, not one** (`cmd_generate`,
  `cmd_fleet`, `cmd_build` heredocs) — the "one emitter" belief was a verifier-corrected
  myth. There is no mux output seam yet.
- The kdotool/KWin window-class introspection **survives any kitty swap** — replacing
  kitty does not free SwitchTail from KDE.
- Fleet-park collapse (parking resumes one pane per lab, nondeterministically under
  concurrency) is a property of the content-free one-shot marker file
  (`bin/stail:264-265`, consumed `:345`), not of any agent — `claude --resume <id>`
  already exists. Partly a documented contract, so fixing it is also a contract upgrade.
- The incident-derived "structurally cannot kill a pane" property is **discipline, not
  enforcement** — the watcher has the full Boss API in scope today. Don't penalize
  alternatives for losing a guarantee the incumbent never had. Only Zellij permissions
  or a kitty `remote_control_password` send-text allowlist make it structural.
- Carry tax: on a rolling-release box, routine kitty upgrades can break the kittens'
  private-API usage (`boss._cockpit_bounce`, on_resize-as-creation,
  `fast_data_types.add_timer`) at any time.

## 4. Timing verdict: SELECTIVE — cut the agent seams now, gate everything else on triggers

Do **now**, while the codebase is at its lifetime minimum (1,560 lines, green suite,
design fresh, author as same-day failure detector):

1. **Kind table, structural slice only** (low): single-source kind →
   (fresh argv, continue argv, style payload|null) in `cmd_cockpit` for the three kinds
   that exist today; kittens gate on shared membership instead of duplicated `'claude'`
   literals. Closes a seam the project already claims but verifiably leaks; cannot be
   invalidated by the forecast naming refactor; makes the swap trap's hostile edge
   structurally unreachable. **No foreign-agent rows yet** — the safety-critical
   "continue is cwd-scoped" column is unverifiable without running each agent, and a
   wrong row cross-wires labs (worse than no row).
2. **Per-pane session-ID resume markers** (low): atomic consume,
   `claude --resume <id>`, `--continue` fallback, schema = session id only. Fixes a
   present-tense defect (fleet-park collapse + concurrent marker-consume race) with the
   current agent.
3. **Status-quo hardenings** (low): shellcheck as a gate in `tests/run-all.sh`; the
   `jq -n --arg` rule for the two JSON emitters; quarantine `_build_resolve` behind a
   single serialized-record format. Optionally extract `switchtail_common.py` for the
   kittens (ends the park contract's bash/Python double-implementation skew; test the
   import path from plasmashell/systemd contexts — that seam is the verified outage genus).

Defer the rest behind **observable triggers** (hair-triggered where a proven incident
class is involved):

| Trigger (observable event) | Flips |
|---|---|
| A second agent CLI is actually installed and launched in a pane, even once | Write that agent's adapter row same day; empirically verify continue cwd-scoping first |
| Any recurrence of the styling incident class (boot-timing keystroke as prompt input, resume-path restyle, layout-churn refire) | Push→pull styling inversion (seam 3) |
| A claude update changes/removes `/rename` or `/color` | Seam 3 |
| A second in-use agent needs pane titling/coloring | Seam 3 (then designed against two real implementations, not zero) |
| The naming-doc vocabulary refactor actually begins | Unify the three emitters as that refactor's FIRST commit |
| One grammar change must be hand-edited in all three heredocs | Emitter unification — dedupe before, not after |
| Non-KDE host targeted, or kdotool breaks on a Plasma update | Move running-state to stail-owned state; kdotool shrinks to raise/focus |
| A mux migration is scheduled | State seam first, then emitters — before, not during |
| Demonstrated persistence need (live session lost to logout/crash and genuinely wanted back, more than once) | Mux decision: kitty+tmux hybrid (de-risked) or WezTerm (single-tool) |
| A kitty upgrade breaks kitten private APIs expensively | Re-open the mux decision rather than rebuilding twice on private API |

## 5. Language guidance (familiarity prior structurally removed)

Debiased ranking for the spine:

1. **Status quo bash spine, hardened now** — the verified workload (string emission,
   spawn/detach, glob discovery) is native to it; every external surface binds to the
   `--json` contract, not to bash; the domain vocabulary is still settling (a rewrite
   now freezes a half-formed model); no spine-language choice touches the kitty-bound ~28%.
2. **stdlib-only Python consolidation** — the best rewrite *if a trigger fires*: the
   only option that dissolves the verified park-contract duplication, shares the
   interpreter kitty already embeds, cheapest to reverse.
3. **Compiled single-binary (Rust/Go/Zig as a class)** — real wins (JSON valid by
   construction, typed Pane record, static binary killing the PATH-outage genus)
   concentrate in ~200 of 618 lines and price against futures; overtakes Python only if
   multi-box distribution / release artifacts become real.
4. **Mux-agnostic helper daemon** — last on timing, not insight: spends 300–500 lines
   on a second mux that doesn't exist and trades the incident-bought send-text-only
   property down to config policy.

Language trigger table: T1 first arbitrary-string field in `--json` → `jq` same day; a
second such field starts the Python port of active/list. T2 the
operator/line/trunk/fanout vocabulary moves from doc to implementation → port the
build/spec subsystem to Python FIRST, then build the new grammar on a typed Pane record
(port-then-build, not build-then-port). T3 second per-subcommand flag → argparse-class
pressure. T4 second box / real releases → compiled option overtakes. T5 a second mux
concretely evaluated → only then the daemon, after explicitly re-accepting the security
downgrade. If none fire, the hardened status quo is correct indefinitely.

## 6. Residual bias statement (what the debiasing cannot remove)

(1) The "compiled languages are the principled choice" meme masquerades as a fitness
argument and pulls toward Rust specifically — though on this workload's own conceded
facts (zero concurrency, zero perf pressure, fast dogfood loop) Rust is arguably the
worst member of its own class; any Rust-shaped pull is meme, not evidence. (2) Its
mirror, "600+ lines of bash is a code smell," pulls toward any rewrite with equal force
and equally little grounding in the observed defect record (the one real outage was
environmental; no type system flags absolute-path-vs-PATH). (3) The judging criterion —
observable fitness — structurally favors the incumbent, whose evidence is realized while
every challenger's is counterfactual; the #1 ranking partially measures that asymmetry.
(4) The familiarity ban cuts the other way: for a solo author, mid-incident fluency is a
real operational input, so the ranking systematically underweights whatever you can
actually fix at 2am. All error-handling reasoning also anchors on the single 2026-06-10
PATH outage — an N=1 recency anchor.

## 7. Bottom line

Friction is moderate overall but sharply asymmetric. The agent axis is cheap and leaking
today — cut it now (kind table slice, session-ID markers, hardenings). The mux axis is
expensive and not leaking — leave kitty alone until persistence earns its rewrite, and
when it does, the seams cut now (plus emitters and state, cut at their triggers) are
what keep that migration tractable. The biggest myth is that the friction lives where
the names are visible: "mostly Python wrapped around the Claude CLI" is wrong on both
counts — both visible dependencies are near-illusions, and the genuinely deep couplings
(kitty's fused roles, the watcher's irreplaceable role, the KDE introspection) are the
ones with the least code and the least visibility.
