# Bytefray-Spectator — P0-C checkpoint report (01)

> Spectator commit IDs in this publication copy identify equivalent stages in the sanitized public history. Original dates and test outcomes remain historical; frozen declarations and checksum-bound evidence are unchanged.

For: Project Lead. Responds to "Bytefray-Spectator — P0-C Conditional
Authorization" (2026-10-12). All commits are local. Nothing was pushed, no
remote was created and nothing was released. E9 remains **LOCKED**;
Requirement C remains **NOT ESTABLISHED**.

## 1. Checkpoint scope

Repository maintenance unrelated to Spectator is omitted from this public
checkpoint. The Spectator implementation and evaluation results below are
retained.

## 2. P0-B independent review verdict

**ACCEPT WITH FINDINGS — all material findings corrected** (Spectator
`b3f3e06`; record `docs/P0B_INDEPENDENT_REVIEW_01.md`). Each finding was
reproduced before it was fixed.

- **F1 HIGH.** The match outcome was not verified. A rewritten
  `result.json` (winner A, B dead) was accepted once the unsigned demo
  sidecar was re-bound. Now the outcome is re-derived from the reconstructed
  final state with the engine's rule and checked against the replay's
  digest-bound terminal record, and any disagreement is refused.
- **F2 MEDIUM.** The Agent A label and timeline revealed when the match
  ends. Reproduced on `2f32c23`: `Tick 0 / 1 … frame 1 / 18`. Now only the
  public tick limit is shown.
- **F3 LOW.** The tamper test accepted any exception. Now each refusal is
  tested against its specific reason.
- **F4 LOW.** Cached `.pyc` files could bypass the pin check. Now all
  bytecode is compiled from the verified sources.

Confirmed correct:

- deterministic serialization and provenance;
- the exact 142-file pin;
- Agent A isolation (entrant-local frames, delivery-time samples, statuses
  that depend only on the agent's own state);
- tick-boundary switching;
- per-tick playback pacing;
- no hidden-data-dependent animation.

## 3. Differential knowledge-isolation results

`exporter/tests/test_knowledge_isolation.py`: 12 tests, all pass. Agent A is
the unchanged official Window Scout starter, against test-only opponents.

- **Unobserved changes.** Three opponents differ only in activity A never
  observes:
  - two co-located processes reading, writing their own core and sensing
    elsewhere;
  - a decoy that keeps acting while A disrupts the anchor, which gives
    **different hidden decisions per tick** (3,961 vs 3,949 omniscient
    frames).

  They produce **byte-identical `agent_a.json`** and an **identical Agent A
  viewer trace**. The trace records title, caption, side panel, label,
  timeline and ring state after every step, tick-step, seek, timeline drag,
  fixed-rate playback frame and switch from every broadcast frame.
- **Positive control.** An opponent that relocates into A's scans changes
  both the export and the trace.
- **Decisive match.** In a match that ends at tick 1 of 120, no Agent A
  label or timeline ever reveals the end.

## 4. Showcase agents and frozen source digests

Frozen at Spectator `1229630` (`agents/`; not Bytefray starters):

| Agent | Design | Tree SHA-256 |
| --- | --- | --- |
| `spectator_harrier` | hunter (reach 96) sweeps SENSE windows, remembers contacts, finds a core as eight consecutive opponent-owned cells, raids it and disrupts guards; keeper (reach 16) rewrites its own core in shuffled rounds and hops at random between four spots | `3c36e94f80e36eb59ff90c6ea8dfd127252b587cad2c414fec7a0957429050ae` |
| `spectator_bastion` | warden (reach 56) repairs its core, watches it with SENSE windows, disrupts fresh intruders and hops after every hit; raider (reach 112) claims territory, scans, and raids a core it identifies by ownership | `0958201159a35ccb34481015151280824af4908a5f1b534f176525e814272e75` |

- Legal Agent API v2 only. A static test checks there are no seed, hidden
  fields, I/O or address literals.
- Live checks: across 118,102 development decisions, all were `APPLIED`,
  with 0 diagnostics, and every elimination was a `core_captured`.
- The agents were developed only on development seeds 900001–900024.

**GAMEPLAY FINDINGS** (for Bytefray; nothing was changed):

1. Reach costs nothing in alpha1, up to arena − 1, so a full-reach agent
   could decide most matches within a few ticks. The showcase agents
   deliberately use bounded reach.
2. Rewriting a core with any byte erases its `0xCE` beacon, and from then on
   only ownership, revealed by a READ, locates a core.

## 5. Frozen selection protocol

**`spectator-p0c-showcase-selection-v1`**: `docs/P0_SHOWCASE_SELECTION_PROTOCOL.md`
(SHA-256 `e3ceccf489fd0bc728080e6bab14c792706ff8f3d44ac63a1db6481bfe65ce08`).
It was frozen with `exporter/showcase_search.py` (`f7147c8c…41f8`) in
Spectator `4eceb88`, before any candidate seed was run.

The configuration is alpha1, arena 512, budget 8, 1000 ticks, seeded
placement, P1 and P2 seat orders, and public seeds 1–500 each.

Hard filters:

- a decisive `last_agent_standing` finish;
- a length of 300–800 ticks;
- both sides write on the other's core;
- observable sensing;
- legal play, with the loser `core_captured`;
- verified, byte-identical export.

Weighted criteria are contest, swings, sensing balance, disruption balance,
length and close finish. The protocol also fixes the tie-breaks, the
examination rule (it may disqualify only for objective defects), and the
narrow seed-governance exception.

## 6. Seed-search outcome and ranking

- 1,000 candidates ran and **0 failed**. Integrity before and after the run
  was unchanged, and all 1,000 run records bind the frozen agents, runner,
  pin and seeded placement.
- Outcomes:
  - Harrier won 898.
  - Bastion won 57.
  - 21 ended `all_agents_dead`.
  - 24 reached the tick limit.
- The median length is about 77 ticks.
- **77 qualified.** Filter failures: length 923, decisive finish 45, both
  sides attack 11.

Top three:

| Rank | Candidate | Ticks | Outcome | Score |
| --- | --- | --- | --- | --- |
| 1 | P1/427 | 477 | Bastion wins | 81.74 |
| 2 | P2/294 | 404 | Harrier wins | 79.07 |
| 3 | P1/421 | 526 | Harrier wins | 77.70 |

The full ranking is in `fixtures/showcase/selection/ranking.json`
(`885161da…213d`). Rank 1 passed validation at the first attempt, and ranks
1–3 passed the viewer examination with no disqualification. Details are in
`docs/P0C_SHOWCASE_SELECTION_01.md`.

## 7. Selected fixture and reproduction

**P1, seed 427**: Harrier (seat A, start 246) against Bastion (seat B, start
168). Bastion captures Harrier's core at **tick 477** with 2/8 core cells
left.

- Both cores were under pressure for 425 ticks each.
- There were 85 lead swings.
- The core writes were 995 vs 930.
- SENSE results with contacts: Harrier 239, Bastion 334.
- Disruptions caused: Harrier 170, Bastion 236.

It is an **upset**: Bastion wins only 4 of the 77 qualifying matches, so the
fixture is not representative of typical results.

Artifacts are in `fixtures/showcase/` (Spectator `d3965d8`):

| File | SHA-256 |
| --- | --- |
| replay | `cd4a9ed6654faf46efec323cddb0ddf627e07e238bca09db14e6a863abf1cd28` |
| manifest | `526b26cf2b451ac0ebd0ad0fb68b247eb2a3ec50e1292db22d97326e247e546c` |
| broadcast | `99045a05…fe` (15,310 frames) |
| agent_a | `111b83a3…af` (7,754 frames) |

**Reproduction.** Running `run_match.py` with Harrier, Bastion and seed 427
re-creates a byte-identical replay. The trace is identical without
`wall_time_ms`, and the result differs only in `completed_at` and
`occurrence_id`. The repeat export is byte-identical.

## 8. Godot playback test results

| Check | Result |
| --- | --- |
| `fixture_check.gd` on the showcase | **21 checks, 0 failures** |
| `agent_view_trace` on ranks 1–3 | 11,358 / 10,149 / 12,412 observations; every label shows only "(limit 1000)"; no result or elimination text |
| Dev smoke test | 29 checks, 0 failures |
| Spectator pytest | **35 passed** (exporter 11, isolation 12, agents 6, showcase 6), 0 skipped |

The 21 showcase checks cover:

- verified load;
- every frame of both perspectives;
- the final alive set `["B"]`, the loser shown eliminated with core 0/8,
  and "Result: B";
- no result before the end;
- Agent A state free of broadcast data, showing only the public tick limit;
- tick-boundary switches;
- fixed-rate playback stopping at the end.

Real-renderer screenshots were inspected and four are kept in
`docs/screenshots/p0c_showcase/`.

## 9. Recommendation for P0-D

**Proceed to P0-D human presentation evaluation with `fixtures/showcase`.**
Suggested points to evaluate:

- whether the Agent A perspective (which follows the losing side) reads
  clearly next to the broadcast;
- the default playback speed: 477 ticks take about 95 s at 5 ticks/s;
- whether the viewer should open the showcase by default (it still opens the
  dev fixture);
- the presentation NOTE that an eliminated entrant's process markers are not
  dimmed.

Carried forward for the Bytefray lead:

- the two gameplay findings in section 4;
- the strong imbalance between the agents (Harrier wins about 90%), which
  any public description of the fixture should state;
- the Spectator exporter's ~1-minute export time, which is a cost of the
  pinned `SensingCursor`.

Not done here, by scope:

- no Bytefray full-suite run;
- no E8/E9 research tests;
- no fix to the six Designer-option tests;
