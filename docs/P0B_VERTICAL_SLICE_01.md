# P0-B — first Godot vertical slice (record 01)

Authorization: Project Lead, "Bytefray-Spectator — P0-A Closure and P0-B
Authorization", Step 4 (2026-10-12). Local repository with local commits
only. There is no remote and nothing has been pushed. No showcase agents were
built and no competitive seed search was done.

## Scope delivered

| Requirement | Implementation |
| --- | --- |
| Godot 4 + GDScript | Godot 4.7.2; `project.godot`, `scenes/main.tscn`, `scripts/*.gd` |
| Read-only Python exporter pinned to the corrected Bytefray commit | `exporter/spectator_export.py`. Pin: `bytefray.pin.json` → `9c81718d057c8cd021f6d1cc7938ea19881b78e1` (the P0-A fix). The exporter refuses to run unless all 142 files under `engine/src/battle_engine` and `client/src/battle_client` equal that commit's tree. It writes no bytecode into the checkout. |
| Separate broadcast and Agent A presentation files | `broadcast.json` (omniscient `SensingCursor`) and `agent_a.json` (receipt-only `SensingView` only, key allowlist enforced) |
| Manifest with provenance and SHA-256 digests | `manifest.json`: pin record, exporter source digest, match identity, source-artifact digests, the verification outcome, and the digest, size and frame count of each presentation file |
| Ring arena, process markers, ownership, core visualization | `scripts/ring_view.gd`: 512 ring segments coloured by owner, core arcs (dimmed when lost), process markers (hollow when disrupted) |
| Playback controls, perspective switching | Play/pause at 1–200 ticks/s, phase-frame and tick stepping, restart, timeline seek, Broadcast ↔ Agent A switching on tick boundaries |
| Basic sensing visualization without omniscient leakage | Agent view shows: unknown cells, own core, own process and reach, the latest delivered sample window (coloured by status), and historical contacts that fade with age and are marked when stale. It holds no broadcast data. |
| Deterministic, verified dev fixture at arena 512 | `fixtures/dev`: Bytefray's M1-2 teaching demo at the declared seed 0 |
| Headless playback smoke test | `tests/smoke_test.gd` |

## Development fixture

| Field | Value |
| --- | --- |
| Generator | `battle_engine.sensing_demo.run_sensing_demo` at pinned `9c81718` |
| Seed | **0**, declared as the demo's published `DEFAULT_SEED`. It was not searched, compared or selected. |
| Config | arena 512, action budget 8, tick limit 1000 |
| Entrants | A `v6_window_scout` (start 0) vs B `v6_stationary_opponent` (start 91) |
| Outcome | **tie, `tick_limit`, 1000 ticks**. Non-decisive, so this is a development fixture only. |
| Verification | artifact pair consistent; exchange reconstructed; all 7 teaching steps VERIFIED; 1001 tick-end boundaries checked against the replay |
| Replay SHA-256 | `dbe67aa534e23f055c0a43287bbed5fae9878b5c2139bd1df207d4a3dbfbf80f` (identical across 3 independent runs and in the regeneration test) |
| Nondeterminism | trace `wall_time_ms`; result `completed_at`, `occurrence_id`; and the demo digests that follow from those. Presentation files are byte-reproducible. |
| Presentation | `broadcast.json` `fa6093c3…9fd6` (32,989 frames); `agent_a.json` `99b54a77…eb7c` (17,001 frames) |

## Test results (final tree, 2026-10-12)

**Exporter (pytest, Bytefray's Python 3.13 environment, system-temp
basetemp): 8 passed, 137.6 s.**

- `test_manifest_vouches_for_committed_files`
- `test_reexport_is_byte_identical_and_writes_nothing_into_bytefray`
- `test_fixture_regenerates_deterministically`
- `test_agent_view_carries_only_delivered_knowledge`: allowlist; no
  omniscient keys; only own processes; every contact was delivered by a
  sample.
- `test_broadcast_final_board_and_alive_set_match_the_replay`
- `test_export_refuses_a_tampered_source`: the stale manifest is removed and
  nothing is vouched for.
- `test_pin_refuses_a_checkout_that_differs_from_the_pinned_commit`: covers
  modified and extra files.
- `test_canonical_json_is_stable`

**Godot headless smoke test: 26 checks, 0 failures**, with no script errors.
It covers:

- manifest and digest verification;
- full traversal of all 32,989 broadcast frames and all 17,001 Agent A
  frames;
- that agent-mode state never holds broadcast data and shows only the agent's
  own process, and that the result is hidden from the agent view;
- a perspective round trip at a tick boundary and from mid-tick;
- timed playback and stop-at-end;
- that a one-byte tamper of `agent_a.json` is rejected and nothing from it is
  kept or drawn.

Mutation checks confirmed the smoke test fails when they are introduced:

- agent view keeping broadcast entrants: 1 failure;
- perspective switch by frame index instead of tick boundary: 2 failures.

Lint: `ruff check exporter` passes.

During development the exporter's own allowlist failed closed once, on a
false positive (the `phase_codes` map keys). That was fixed by allowing the
three phase names.

The smoke test caught two real defects before the final run:

- a sequential-cache bug at frame 0 in the board model;
- a harness ordering issue in which `_ready` had not run during
  `SceneTree._initialize`.

Both are fixed.

The Bytefray checkout was snapshotted (paths, sizes, mtimes, ignored status)
before and after fixture generation and export, and the two snapshots were
identical.

## Known limitations (next work, not done here)

- The fixture shows little action: Window Scout reads and senses, and only
  one ownership change occurs. A decisive fixture (core capture or last agent
  standing) is needed for showcase work. That depends on the separately
  authorized showcase-agent and seed steps.
- The non-interference evidence for `agent_a.json` rests on three things:
  Bytefray's AC5-tested `SensingCursor`, the exporter's key allowlist, and
  the delivered-contact test. A differential test comparing hidden-opponent
  variants at the Spectator level is not yet implemented.
- Only Agent A has a perspective file. Agent B and multi-process agents are
  untested in the viewer.
- Re-export takes about 2 minutes, because `SensingView` rebuilds its prefix
  on every step.
- The viewer is not packaged or exported yet. Fixture files are read from
  `res://`.
