---
title: "Agent-session wiring — push ring/status from the hosted agents"
trigger_condition: "Once the v0.2 composition phase lands (the exchange can spawn boards/lines live)"
planted_date: "2026-06-13"
status: dormant
---

# Agent-session wiring

## The idea

The deferred "afterward" half of the v0.2 conversation. Once SwitchTail can
**compose** the exchange (spawn the lines), the next leverage is making those
hosted agent sessions **drive the board themselves** — ring/status flowing
*from* the agents into the switchboard automatically, so the call log lights up
and triage states change without the operator pressing `R` by hand.

This is what turns the switchboard from something you watch into something the
agents talk back to: a line that finishes a task rings itself; a blocked agent
reports `blocked`; the overview stays live without manual polling.

## Why it's a seed, not a phase yet

- It depends on the composition front door existing first (operator's explicit
  sequencing: launch/compose first, wire the sessions afterward).
- The **wiring mechanism is itself an open question** — do NOT assume Claude
  Code hooks. Standing owner feedback is "too hook heavy"; new Claude Code
  hooks should not be the default answer. The pipe protocol already exists
  (`ring`/`status`/`register` ops over `zellij pipe -n switchtail`), so an
  agent could push state via a lightweight wrapper/notify command rather than a
  hook. Weigh the options (pipe-from-agent wrapper, a thin notify shim, hooks
  only if they clearly win) when this is promoted — that comparison is part of
  the work, not a settled input.

## Open questions to resolve at promotion

- What's the lightest mechanism for an agent to emit ring/status? (pipe wrapper
  vs. notify shim vs. hooks — bias away from hooks per standing feedback)
- Does this pull **cwd** back into scope (v0.2 deferred it)? An agent reporting
  "where it is" is adjacent to per-line working directory.
- Mapping: how does an emitted event find its **line ID**? (the pipe protocol
  resolves by line ref today — does a hosted agent know its own line id, or
  does SwitchTail infer it from the pane it spawned?)

## Related

- v0.1 pipe protocol: `ring` / `status` / `register` ops (already built).
- Note: [[v0.2-composing-the-exchange]] — the front-door phase this follows.
- Was the "Claude Code hook wiring for ring/status" v0.2 candidate; reframed
  here as mechanism-agnostic agent-session wiring.
