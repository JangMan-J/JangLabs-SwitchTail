# Context (from DOCs)

_Synthesized 2026-06-11 from .planning/intel/classifications/ (mode: new)._

## Topic: System shape and scale

source: docs/direction-report-2026-06.md (§1, §2)

- SwitchTail is a personal agent-cockpit system: each lab (git submodule under
  `~/JangLabs`) becomes a tiled kitty window of Claude Code panes, with a numpad
  "deck" for focus control, a Plasma 6 widget as launcher/introspector, and a
  deliberate park-to-resume lifecycle.
- ~1,560 source lines in five layers: 618-line bash spine (`bin/stail`), three
  Python kittens (261 lines) inside kitty's embedded interpreter, declarative
  kitty config, systemd regen units, 530-line QML widget that talks to the system
  exclusively through `stail`'s `--json` contract.
- Running-state detection is kdotool/KWin window-class search — a KDE coupling
  independent of kitty.
- Two days past v1, daily dogfooded by a single author on one CachyOS/KDE/Wayland
  box, 147-assertion suite green.
- Premise correction: it is NOT "mostly Python". Real shape is bash 618 > QML 530
  > Python 261, and the Python runs inside kitty's embedded interpreter — kitty
  chose the language, and it evaporates if kitty goes. "Should this stay Python?"
  reduces entirely to "should this stay kitty?". The only owned language decision
  is the bash spine.

## Topic: Friction matrix (adversarially corrected)

source: docs/direction-report-2026-06.md (§3)

Scores 1 = trivial, 5 = load-bearing rewrite (Extract / Replace / Parity / Exceed):

- claude CLI (agent payload): moderate depth — 2 / 2 / 3 / 3
- kitty (mux + window model + watcher + GUI host): deep — 3 / 4 / 3 / 2
- Python (the 3 kittens): shallow, phantom axis — 2 / 3 / 4 / 3
- kitty watcher (cockpit_monitor.py): deep — 2 / 4 / 3 / 3

Governing law: coupling depth is inversely proportional to how loudly the
dependency announces itself. The visible dependencies are near-illusions; the
deep ones are quiet:

- `claude` the binary appears in exactly one file (`bin/stail` cmd_cockpit, two
  exec lines); the chassis is agent-blind. Real Claude coupling hides in (a) the
  watcher's typed `/rename`+`/color` payload (client-side slash commands typed
  into the running TUI — the cockpit outsources labeling intelligence to the
  agent) and (b) the marker protocol's silent invariant that the resume argv is
  cwd-scoped like `--continue` (a globally-scoped continue would cross-wire labs).
- The generic-kind seam leaks today: the `'claude'` literal is duplicated into 2
  of 3 kittens (`cockpit_park.py:26`, `cockpit_monitor.py:39` `_STYLE_KINDS`).
  Swap trap is double-edged: a `kind=cmd:opencode` pane silently loses
  park/resume/styling; swapping the exec argv while keeping `kind=claude` gains
  hostile behavior (Claude slash-commands typed into a foreign agent's REPL).
- kitty is load-bearing in three-to-four fused roles: mux/session grammar,
  scriptable window model, in-process watcher host, plus hidden GUI-host role
  (rendering, `os_window_class` stamping, `.desktop` ownership, beyond-PATH
  binary resolution). The interaction layer (~28% of source: kittens + deck.conf)
  is a per-backend paradigm rewrite, not an adapter. Coverage: WezTerm is the only
  single tool covering all four roles; tmux covers mux+window-model but degrades
  the watcher to shell-forked hooks+polling and leaves GUI-host unfilled; Zellij
  needs a Rust/WASM plugin; Warp covers none. kitty+tmux hybrid is the cheap
  increment.
- The session grammar regenerates from THREE emitters, not one (`cmd_generate`,
  `cmd_fleet`, `cmd_build` heredocs) — "one emitter" was a verifier-corrected
  myth. No mux output seam exists yet.
- kdotool/KWin window-class introspection survives any kitty swap — replacing
  kitty does not free SwitchTail from KDE.
- Fleet-park collapse (parking resumes one pane per lab, nondeterministically
  under concurrency) is a property of the content-free one-shot marker file
  (`bin/stail:264-265`, consumed `:345`), not of any agent — `claude --resume
  <id>` already exists. Partly a documented contract, so the fix is also a
  contract upgrade.
- "Structurally cannot kill a pane" is discipline, not enforcement — the watcher
  has the full Boss API in scope. Only Zellij permissions or a kitty
  `remote_control_password` send-text allowlist make it structural.
- Carry tax: routine kitty upgrades on a rolling-release box can break the
  kittens' private-API usage (`boss._cockpit_bounce`, on_resize-as-creation,
  `fast_data_types.add_timer`) at any time.

## Topic: Timing verdict — SELECTIVE (cut agent seams now, gate the rest on triggers)

source: docs/direction-report-2026-06.md (§4)

Do NOW, while the codebase is at its lifetime minimum (1,560 lines, green suite,
design fresh, author as same-day failure detector):

1. Kind table, structural slice only (low effort): single-source kind →
   (fresh argv, continue argv, style payload|null) in `cmd_cockpit` for the three
   existing kinds; kittens gate on shared membership instead of duplicated
   `'claude'` literals. NO foreign-agent rows yet — the safety-critical
   "continue is cwd-scoped" column is unverifiable without running each agent,
   and a wrong row cross-wires labs (worse than no row).
2. Per-pane session-ID resume markers (low): atomic consume, `claude --resume
   <id>`, `--continue` fallback, schema = session id only. Fixes a present-tense
   defect (fleet-park collapse + concurrent marker-consume race).
3. Status-quo hardenings (low): shellcheck as a gate in `tests/run-all.sh`; the
   `jq -n --arg` rule for the two JSON emitters; quarantine `_build_resolve`
   behind a single serialized-record format. Optionally extract
   `switchtail_common.py` for the kittens (ends the park contract's bash/Python
   double-implementation skew; test the import path from plasmashell/systemd
   contexts — that seam is the verified outage genus).

Defer the rest behind observable triggers:

- Second agent CLI actually installed and launched in a pane, even once → write
  that agent's adapter row same day; empirically verify continue cwd-scoping first.
- Any recurrence of the styling incident class (boot-timing keystroke as prompt
  input, resume-path restyle, layout-churn refire) → push→pull styling inversion
  (seam 3).
- A claude update changes/removes `/rename` or `/color` → seam 3.
- A second in-use agent needs pane titling/coloring → seam 3 (designed against
  two real implementations, not zero).
- The naming-doc vocabulary refactor actually begins → unify the three emitters
  as that refactor's FIRST commit.
- One grammar change must be hand-edited in all three heredocs → emitter
  unification — dedupe before, not after.
- Non-KDE host targeted, or kdotool breaks on a Plasma update → move
  running-state to stail-owned state; kdotool shrinks to raise/focus.
- A mux migration is scheduled → state seam first, then emitters — before, not
  during.
- Demonstrated persistence need (live session lost to logout/crash and genuinely
  wanted back, more than once) → mux decision: kitty+tmux hybrid (de-risked) or
  WezTerm (single-tool).
- A kitty upgrade breaks kitten private APIs expensively → re-open the mux
  decision rather than rebuilding twice on private API.

## Topic: Spine-language guidance (familiarity prior structurally removed)

source: docs/direction-report-2026-06.md (§5)

Debiased ranking for the spine:

1. Status quo bash spine, hardened now — the verified workload (string emission,
   spawn/detach, glob discovery) is native to it; every external surface binds to
   the `--json` contract, not to bash; domain vocabulary still settling (a rewrite
   now freezes a half-formed model); no spine-language choice touches the
   kitty-bound ~28%.
2. stdlib-only Python consolidation — best rewrite if a trigger fires: only
   option that dissolves the verified park-contract duplication, shares the
   interpreter kitty embeds, cheapest to reverse.
3. Compiled single-binary (Rust/Go/Zig as a class) — real wins concentrate in
   ~200 of 618 lines and price against futures; overtakes Python only if
   multi-box distribution / release artifacts become real.
4. Mux-agnostic helper daemon — last on timing: spends 300–500 lines on a second
   mux that doesn't exist and trades the incident-bought send-text-only property
   down to config policy.

Language trigger table: T1 first arbitrary-string field in `--json` → `jq` same
day; a second such field starts the Python port of active/list. T2 the
operator/line/trunk/fanout vocabulary moves from doc to implementation → port the
build/spec subsystem to Python FIRST, then build the new grammar on a typed Pane
record (port-then-build, not build-then-port). T3 second per-subcommand flag →
argparse-class pressure. T4 second box / real releases → compiled option
overtakes. T5 a second mux concretely evaluated → only then the daemon, after
explicitly re-accepting the security downgrade. If none fire, the hardened status
quo is correct indefinitely.

## Topic: Residual bias statement (caveats on the guidance itself)

source: docs/direction-report-2026-06.md (§6)

(1) "Compiled languages are the principled choice" is meme, not evidence, on this
workload (zero concurrency, zero perf pressure, fast dogfood loop) — Rust is
arguably the worst member of its own class here. (2) Its mirror, "600+ lines of
bash is a code smell," is equally ungrounded in the observed defect record (the
one real outage was environmental; no type system flags absolute-path-vs-PATH).
(3) The observable-fitness criterion structurally favors the incumbent (realized
vs counterfactual evidence); the #1 ranking partially measures that asymmetry.
(4) The familiarity ban underweights solo-author mid-incident fluency — a real
operational input. All error-handling reasoning anchors on a single 2026-06-10
PATH outage (N=1 recency anchor).

## Topic: Bottom line

source: docs/direction-report-2026-06.md (§7)

Friction is moderate overall but sharply asymmetric. The agent axis is cheap and
leaking today — cut it now (kind table slice, session-ID markers, hardenings).
The mux axis is expensive and not leaking — leave kitty alone until persistence
earns its rewrite; the seams cut now (plus emitters and state at their triggers)
are what keep a future migration tractable. Biggest myth: that friction lives
where the names are visible. "Mostly Python wrapped around the Claude CLI" is
wrong on both counts — both visible dependencies are near-illusions, and the
genuinely deep couplings (kitty's fused roles, the watcher's irreplaceable role,
the KDE introspection) have the least code and the least visibility.
