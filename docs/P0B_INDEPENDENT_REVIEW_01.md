# P0-B — independent qualification review (record 01)

> Spectator commit IDs in this publication copy identify equivalent stages in the sanitized public history. Original dates and test outcomes remain historical; frozen declarations and checksum-bound evidence are unchanged.

Authorization: Project Lead, "Bytefray-Spectator — P0-C Conditional
Authorization", Phase 2 (2026-10-12). Local repository only; nothing pushed.

Reviewed: local commit `2f32c23` ("first Godot vertical slice"), every tracked
source file (exporter, fixture generator, tests, Godot scripts, scene, project,
pin, fixture declaration and manifest), against the pinned Bytefray
`9c81718` (`battle_client/sensing.py`, `battle_engine/sensing_playback.py`,
`process_runtime.py`, `match_service.py`, `agent_api.py`). The reviewer had no
part in writing P0-B. Every finding below was reproduced before it was fixed.

## Verdict

**ACCEPT WITH FINDINGS — all material findings corrected.** P0-B's
architecture holds: the Agent A file is serialized only from Bytefray's
receipt-only `SensingView`, switching is tick-boundary based, and playback
pacing is per tick. Two material defects (F1 HIGH, F2 MEDIUM) and two LOW
issues were found and fixed. P0-C continued only after the fixes and the new
differential tests passed.

## Findings

| ID | Severity | Finding | Reproduction | Correction |
| --- | --- | --- | --- | --- |
| F1 | HIGH | The match outcome was never verified. `result.json`'s `winner`, `termination_reason` and per-entrant `alive` were copied into `broadcast.json` and `manifest.json` and shown in the viewer. Bytefray binds `result.json` only through the replay digest and the unsigned `demo.json` sidecar. | Rewrite the dev fixture's result to `winner: A, core_captured, B dead` and re-bind `demo.json`'s result digest: export **accepted** it, and the viewer would have shown "Result: A" over a replay where both entrants survive to the tick limit. | `verify_outcome` re-derives the outcome from the reconstructed final world state (alive set, last tick) with the engine's rule (`process_runtime`: one survivor → `last_agent_standing`; none → tie `all_agents_dead`; otherwise `tick_limit` with the unique top score), checks it against the replay's digest-bound terminal result record, and requires `result.json` to agree with both (outcome, ticks, tick limit, identity, score, alive flags). The displayed result now comes from the verified outcome. The same attack is now refused: "match outcome does not verify: result.json outcome equals the replay, alive flags". |
| F2 | MEDIUM | In the Agent A perspective the position label (`Tick t / <last tick>`, `frame i / <total>`) and the timeline range came from the recorded match length, which reveals *when the match ends* (for example, a capture at tick 412), before Agent A could know it. The dev fixture hid this because it ends exactly at its 1000-tick limit. | A 120-tick-limit match ending by capture at tick 1 (test raider), loaded in a `2f32c23` worktree (manifest flag patched for its teaching-only loader): at tick 0 the agent label read `Tick 0 / 1   TICK_END   frame 1 / 18`, timeline max 1. | The manifest records the public `tick_limit`. In the agent perspective the label is `Tick t (limit L)   PHASE   step i`, with no totals, and the timeline spans the tick limit. Broadcast keeps its full-length display. |
| F3 | LOW | `test_export_refuses_a_tampered_source` accepted *any* exception, so a JSON parse error from a flipped byte counted as a refusal. | — | Replaced by per-source tamper tests with expected reasons (result digest, replay digest with valid JSON, demo config, rewritten outcome with re-bound sidecar), plus match-record tamper tests. |
| F4 | LOW | The pin check verifies `.py` sources but skips `__pycache__`, and Python would execute a matching cached `.pyc` from there: bytecode the pin never verified. | — | `sys.pycache_prefix` points at a directory that is never created, so every module compiles from its verified source (and nothing is written). |

Notes (no change needed in P0):

- The manifest is the viewer's root of trust and is not signed. The viewer
  checks every presentation file against it, and the exporter tests check the
  manifest against the sources. Signing is out of P0 scope.
- Godot parses JSON numbers as doubles. Seeds above 2^53 would display
  imprecisely in the footer. P0 seeds are small.
- Exporting a 1000-tick match takes about 150 s, because the pinned
  `SensingCursor.current_view` rebuilds each view from its full prefix. This
  is a Bytefray-side cost and was left unchanged.
- On this machine the OS-default pytest temp root is not readable (the
  documented stale-ACL issue), so tests are run with an explicit disposable
  `--basetemp`.

## Confirmed correct

- **Exporter provenance and deterministic serialization.** Canonical JSON
  (sorted keys, ASCII, LF). The manifest binds the pin record, the exporter's
  own digest, every source digest and every presentation digest. Re-export is
  byte-identical, and the dev fixture's `broadcast.json`/`agent_a.json` are
  unchanged by every fix here.
- **Exact pinned dependency.** All 142 files under the two pinned packages are
  compared to the pinned tree (missing, extra and modified files are all
  refused), and the imported modules must come from the checkout.
- **Agent A knowledge isolation.** Entrant frames come only from facts whose
  actor is A or none (tick ends). Callback ordinals are entrant-local. Samples
  and reads appear only at delivery. Every action status the engine can emit
  (`APPLIED`, `REJECTED_OUT_OF_REACH`, `REJECTED_INVALID`, `EXCEPTION`)
  depends only on the agent's own anchor, reach and action. The read owner is
  part of `ObservationV2`. The key allowlist is enforced.
- **Tick-boundary switching.** Both directions land on the last completed
  tick boundary, a function of the tick alone.
- **Playback timing and rendering.** Playback advances one tick boundary per
  1/rate seconds in both perspectives. Agent-mode drawing uses only agent
  state: own core, own processes and reach, latest delivered sample,
  contacts. There are no tweens or animations whose duration could depend on
  hidden data.

## Differential knowledge-isolation tests

`exporter/tests/test_knowledge_isolation.py`. Agent A is the unchanged
official Window Scout starter. Each match is 120 ticks at the teaching layout
(starts 0 and 91), against test-only opponents in `exporter/tests/agents/`:

| Opponent | Hidden difference from `quiet` | Agent A export | Agent A viewer trace |
| --- | --- | --- | --- |
| `quiet` | (reference: one stationary process reading its core) | `9afd4b04…` | reference |
| `busy` | two processes on one anchor; reads, writes its own core, senses away; different ownership | identical bytes | identical |
| `split` | a decoy parked where A never scans keeps acting while A disrupts the anchor, so the opponent takes a **different number of decisions per tick** (broadcast 3,961 vs 3,949 frames) | identical bytes | identical |
| `relocating` (positive control) | moves once onto a cell A scans | **differs** (samples differ) | **differs** |

The viewer trace (`tests/agent_view_trace.gd`) records everything the Agent A
perspective displays after each operation:

- stepping through every frame;
- stepping back tick by tick;
- seeking every tick up to the limit;
- dragging the timeline;
- playback at a fixed frame rate;
- switching in from every broadcast frame (run-length collapsed).

Each record holds the title, caption, side panel, position label, timeline
value and range, footer and ring-view state. A decisive raider match (ends at
tick 1 of 120) checks that no agent-mode label or timeline ever reveals the
end.

## Test results after the fixes

- Exporter and isolation tests: **23 passed** (11 exporter, 12 isolation;
  about 3 min 15 s; Godot available, so nothing was skipped).
- Godot headless smoke test: **29 checks, 0 failures** (3 new: agent label,
  agent timeline range, broadcast timeline range).
- Bytefray `engine/src` and `client/src`: no changes (`git status` clean).
