# Carried-over learnings from the kitty era (2026-06)

Distilled from the retired kitty-based SwitchTail (tag `kitty-era-final`,
archive `~/JangLabs/.archive/switchtail-kitty-era/`). These are the lessons
that shape the Zellij-era design; the code itself is not a reference
implementation anymore.

## Design DNA that survives

- **The vocabulary** (board/line/trunk/patch/hold/exchange + deck/seat/
  operator) — proven daily-driver UX language; now the domain model itself.
- **Agent-kind table thinking**: agent argv + per-kind policy flags
  (holdable/stylable) must live in ONE table; scattering kind literals across
  components caused real drift (`'claude'` duplicated into 2 of 3 kittens).
  When kinds return (post-v0.1), they enter as one core table.
- **Per-pane session identity**: hold/resume only works fleet-safely with
  per-pane session-ID markers consumed atomically (`hold/<lab>/<sid>`);
  content-free one-shot flags collapse N parked lines into one resume.
  `claude --resume <id>` is mux-independent — the protocol ports cleanly.
- **`--continue` is cwd-scoped** — the silent safety invariant. A
  globally-scoped continue would cross-wire labs. Never add a foreign agent
  kind without empirically verifying its continue scoping.
- **JSON contract for scripting**: external consumers bind to a stable JSON
  surface, not to implementation. Zellij era: the `switchtail` pipe's
  `list`/`log` JSON answers play that role.

## Incident-bought operational lessons

- **Watcher safety must be structural, not disciplined.** A stray
  window-close from a watcher once killed a live board. Kitty offered only
  discipline; Zellij offers declared permissions + a no-kill test on the
  adapter. Keep both.
- **Boot-timing keystrokes are dangerous.** Typing into an agent TUI before
  it finishes booting lands keystrokes as prompt input. The kitty tail
  watcher needed delays + idempotency marks. Zellij era: prefer native
  `rename_pane_with_id`/`set_pane_color` (no typing at all); any future
  type-into-TUI behavior needs the same once-only marker discipline.
- **GUI-spawned processes lack `~/.local/bin` on PATH** (plasmashell,
  systemd user units). The one real outage was environmental. Anything
  spawned by launchers/units must use absolute paths.
- **PID liveness needs a reuse guard**: `/proc/<pid>` existence + start-time
  match, never bare PID checks. (Zellij-era equivalent: trust the host's
  PaneUpdate stream instead of owning liveness at all.)
- **Idempotency markers beat event dedup**: mark-then-act (set the styled/
  scheduled flag BEFORE acting) so races re-check the mark, not the action.

## Process lessons

- **Verify APIs from source, not summaries.** Web/doc paraphrases of the
  zellij-tile API were wrong on several signatures; vendored crate source
  (`~/.cargo/registry/src/`) is ground truth on this box.
- **State seams before migrations**: owning your state (vs deriving it from
  the host's window system) is what made the kitty system portable at all.
  Zellij era: the core model owns everything; the host stream is input, not
  truth.
- The 147→208-assertion regression suite was what made live surgery on a
  daily driver safe. Keep the same bar: every behavior that matters gets a
  test that fails when it breaks.
