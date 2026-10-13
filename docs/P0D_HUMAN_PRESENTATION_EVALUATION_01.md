# Bytefray-Spectator — P0-D human presentation evaluation (01)

For: Project Lead. Responds to "Bytefray-Spectator — P0-D Human Presentation
Evaluation" (2026-10-12).

All commits are local. Nothing was pushed, no remote was created and nothing
was released. No Bytefray research artifact, gameplay rule or official
starter agent was changed. E9 remains **LOCKED**; Requirement C remains
**NOT ESTABLISHED**.

**Independence notice.** No independent human reviewers took part. The scores
in §6 are the **developer's assessment**. They are not independent user
validation and are not presented as such. A blank table for the Project
Lead's own assessment is in §6.4, and a reviewer protocol with an answer key
is in Appendix A, so independent viewers can be added later.

## 1. Identifiers

| Item | Value |
| --- | --- |
| Spectator commits (P0-D) | `f95f9ae` D1 presentation readiness · `b691ae2` D2 comparison evidence · this report (the commit that adds this file) |
| Spectator base | `c616fa2` (P0-C checkpoint) |
| Bytefray pin used by the exporter and the V6 baseline | `9c81718` (142 files verified on every export and capture) |
| Bytefray checkout | `v6-research` HEAD `2fc3c82`, unchanged by P0-D |
| Fixture | `fixtures/showcase`, P1 seed 427: `spectator_harrier` (A) vs `spectator_bastion` (B); Bastion captures Harrier's core at tick 477 |
| Fixture digests (unchanged) | replay `cd4a9ed6…1cd28`, manifest `526b26cf…546c`, broadcast `99045a05…72fe` (15,310 frames), agent_a `111b83a3…e5af` (7,754 frames), declaration `afc15724…6885` |
| Frozen inputs (unchanged) | agents Harrier `3c36e94f…50ae` and Bastion `09582011…2e75`; protocol `spectator-p0c-showcase-selection-v1` (`e3ceccf4…ce08`) |
| Evidence | `docs/p0d/` (44 files, `SHA256SUMS` digest `0ac20ca1088529e176c7075a059a14d55f97585f7f95f727b753f6fcdb4b81b7`) |

Nothing under `fixtures/`, `agents/`, the protocol or the selection evidence
was modified. `exporter/tests/test_showcase_fixture.py` re-checks every
digest, the frozen agent trees, a byte-identical re-export and the re-run
reproduction, and it passes. The seed search was not re-run.

## 2. Phase D1: presentation readiness (commit `f95f9ae`)

Only the listed usability items were changed. There was no visual redesign.

| D1 item | Change |
| --- | --- |
| Clear, repeatable launch | The viewer now opens the verified showcase fixture by default. `launch_showcase.ps1` opens it with `-Perspective`, `-Tick`, `-Speed` and `-Play`. The same options can be passed straight to Godot after `--`, with aliases `--fixture=showcase\|dev\|<dir>`. Unrecognised options are reported and ignored. The same options always produce the same starting view. |
| Eliminated processes (broadcast) | An entrant missing from the frame's `alive` set has its process markers dimmed and crossed out. The tick-end caption names the entrant eliminated in that tick: "Tick 477 ends - A spectator_harrier eliminated (core 0/8)". This resolves the P0-C NOTE about undimmed markers. |
| Eliminated processes (Agent A) | **Deliberately not shown.** The receipt-only `SensingView` has no alive or elimination field, and Harrier gets no callback after its core falls, so Agent A is never told it was eliminated. |
| Final capture and winner understandable | The result line now reads "Result: B spectator_bastion wins (last agent standing, tick 477)" instead of "Result: B (last_agent_standing, 477 ticks)". A ring banner, "B SPECTATOR_BASTION WINS", appears only on the final verified frame. |
| Broadcast truth vs Agent A knowledge | A static note in Agent A's panel says the agent is never told the outcome and points to Broadcast (Tab). The note is identical at every position, so it reveals nothing. The agent's own core was drawn as a solid band in the agent's colour, which is exactly the broadcast's "core held" style. At tick 477 it therefore looked intact when it had been captured (finding M-1, §8). It is now drawn as an outline and labelled "Own core location … (ownership not shown)". |
| Integrity and determinism | Unchanged code paths: manifest verification before rendering, separate perspective models, and switching on tick boundaries. New checks are listed in §3. |

## 3. Test results after the viewer changes

| Check | Before (P0-C) | After (P0-D) |
| --- | --- | --- |
| Spectator pytest (exporter, isolation, agents, showcase, V6 capture) | 35 passed | **36 passed**, 0 skipped (3 min 59 s, on the code committed as `f95f9ae` + `b691ae2`) |
| `smoke_test.gd` (dev fixture, default fixture, launch options, tamper) | 29 / 29 | **35 / 35** |
| `fixture_check.gd` on the showcase | 21 / 21 | **26 / 26** |
| `fixture_check.gd` on the dev fixture | not reported | **20 / 20** (it ends at the tick limit, so the decisive-match checks do not apply) |
| Agent A trace of the showcase (`agent_view_trace.gd`) | 11,358 observations, clean | **11,358 observations, 0 problems.** Every label is `Tick n (limit 1000) PHASE step n`, every timeline ends `/1000`, and no observation has a banner or contains "Result", "eliminated", "wins" or the opponent's name. |
| `ruff check` / `ruff format --check` | clean | clean for all P0-D files. `exporter/make_dev_fixture.py` has formatter drift from P0-B, which was left untouched. |

New checks added to `fixture_check.gd` (they run on every frame of the
fixture):

- markers are styled "eliminated" exactly when their entrant is absent from
  `alive`;
- the banner appears only on the final frame and never in Agent A;
- the final caption names the eliminated entrant with "core 0/8";
- the banner names the winner;
- Agent A's caption never contains "eliminated", and its panel starts with the
  static note.

The differential knowledge-isolation tests now also record the banner.

**Determinism**

- Two independent Godot recordings of the broadcast segment produced
  byte-identical MP4s (`6df8b32a…94b1`).
- Two V6-viewer captures are byte-identical, checked by
  `test_capture_v6_viewer`.
- A repeat export of the fixture is byte-identical, checked by
  `test_showcase_fixture`.

**Bytefray integrity**

- Bytefray checkout HEAD remained `2fc3c82`; `engine/` and `client/`
  were unchanged by the Spectator evaluation.

## 4. Phase D2: same-match comparison

**Method.**

- **Inputs.** All three views play the same verified match source:
  `fixtures/showcase/source` and its presentation export.
- **A, the V6 baseline.** Rendered by `exporter/capture_v6_viewer.py`, which
  verifies the pin and then calls Bytefray's unmodified
  `SensingReplayRenderer.draw` offscreen at its default 1100×750 window.
- **B and C, Godot.** Rendered by `tests/capture_frames.gd` with the real
  OpenGL renderer at 1280×800.
- **Comparison ticks.** Derived from the data by `docs/p0d/moments.py`
  (output in `docs/p0d/moments.json`), not chosen by eye.
- **V4 renderer.** Consulted only for design ideas (§8). It is not a
  baseline.

| Tick | Why this tick (from `moments.json`) | Side by side (`docs/p0d/side_by_side/`) |
| --- | --- | --- |
| 1 | Opening: both sides sense at once; Agent A's first contact | `tick-0001.png` |
| 9 | Agent A's first stale contact (cell 184, "absent in a newer sample") | `tick-0009.png` |
| 12 | First disruption of Harrier's hunter; cores A 6/8, B 4/8 | `tick-0012.png` |
| 320 | Bastion's lowest point, 1/8 core cells: Harrier's near miss | `tick-0320.png` |
| 461 | Harrier's hunter makes its only move of the match (−63 cells, 246 → 183) | `tick-0461.png` |
| 476 | Both cores at 2/8 | `tick-0476.png` |
| 477 | Capture: A 0/8, B wins | `tick-0477.png` |

In each composite, the top row is V6 omniscient beside Godot Broadcast and the
bottom row is V6 Agent A beside Godot Agent A. The raw screenshots are in
`docs/p0d/screenshots/{v6,godot}/`. The V6 capture record (`capture.json`)
also stores the side-panel text shown at each capture.

**Recordings of ticks 440 → 477** (`docs/p0d/recordings/`, metadata and
commands in `recordings.json`):

| File | Viewer, perspective, speed | Length |
| --- | --- | --- |
| `godot-broadcast-440-477-5tps.mp4` | Godot Broadcast, 5 ticks/s (default) | 8.5 s |
| `godot-agent_a-440-477-5tps.mp4` | Godot Agent A, 5 ticks/s | 8.5 s |
| `v6-omniscient-440-477-x1.mp4` | V6 omniscient, 1x (default) | 58.5 s |
| `v6-omniscient-440-477-x8.mp4` | V6 omniscient, 8x (maximum) | 8.2 s |
| `v6-agent_a-440-477-x8.mp4` | V6 Agent A, 8x | 4.5 s |

Each recording also holds the final frame for about 1 s. To replay any
moment interactively, run `./launch_showcase.ps1 -Perspective
broadcast|agent_a -Tick <n>`.

### 4.1 Side-by-side comparison by subject

| Subject | A. V6 sensing viewer | B. Godot Broadcast | C. Godot Agent A |
| --- | --- | --- | --- |
| Movement | Omniscient: anchor circles jump between grid squares. Agent A: an arrow for its own last MOVE. On the 32-column grid, the 15-cell keeper hop at tick 9 is drawn as a long diagonal across two rows. | Process triangles on the ring jump with no trail. The hunter's single 63-cell move at tick 461 has no cue. | Own process triangles and reach arcs; no move arrow. |
| Actions | Every phase position (15,310) is played; no per-action caption in omniscient. | Per-action captions ("B/raider WRITE 250 -> APPLIED") when stepping. Playback advances tick to tick and shows only "Tick n ends". | Own events in the side panel, about half of them "observation / Delivered observation" lines. |
| Sensing | Omniscient: none. Agent A: a pending SENSE ring, receipt cross, labelled diamonds for samples, and full callback-level text. | **None drawn.** SENSE appears only in step captions ("(sample taken; delivered next callback)"). | Latest sample as an arc coloured by status, remembered contacts as triangles, and a contact list with ages. |
| Stale contacts | Agent A: grey vs gold diamonds plus "absent in newer scan" text. Labels overlap: "sample 180sample 184" at ticks 320 and 477. | not applicable | Stale contacts grey, fresh ones gold and fading with age; the list says "(absent in a newer sample)". |
| Territory | Coloured squares, green = A and magenta = B. Owned cells stay between 16 and 24 of 512 all match, so the grid looks almost empty. | Ownership arcs on a 512-cell ring. The same 16–24 cells cluster in one roughly 90-cell arc, so most of the ring is unused. | Not delivered, so not shown. Correct. |
| Core integrity | **Not shown**: no core outline and no count. | Core arcs, dimmed per lost cell, plus "core n/8" per entrant. The 1/8 low at tick 320 is clear in the text but hard to see on the ring. | Location only, as an outline (D1). |
| Elimination | Not indicated: Harrier's processes look the same at tick 477. | Crossed-out markers, the tick-477 caption, "eliminated core 0/8" in the panel (D1). | Not shown, because it is never delivered. |
| Final victory | One text line: "Recorded end: winner B; last_agent_standing". | Banner, result line and caption (D1). | None. The static note points to Broadcast. |
| Information boundary in Agent A | **Leaks** (see OF-1 and OF-2 in §5). | not applicable | Clean (§3). |
| Full-match playback at default speed | 765.5 s omniscient / 387.7 s Agent A at 1x; 95.7 s / 48.5 s at the 8x maximum | 95.4 s at 5 ticks/s (1–200 available) | 95.4 s, paced by tick, the same as broadcast |

## 5. Objective functional findings

These are facts verified from code, data or captures. They are kept separate
from the opinions in §6.

| ID | Finding | Evidence |
| --- | --- | --- |
| OF-1 | **V6 baseline:** the Agent A perspective shows "Recorded end: winner B; last_agent_standing" at the end of its record. `draw()` prints `terminal_text` whatever perspective is active. | `capture.json`, agent_a tick 477; composite `tick-0477.png` |
| OF-2 | **V6 baseline:** the Agent A timeline playhead sits at index ÷ (record length − 1), so its position shows how far through the record the agent is. At tick 320 it is about two-thirds along, which reveals that the record ends around tick 480. This is the same class of disclosure as P0-B finding F2, which was fixed in Godot. | `screenshots/v6/v6-agent_a-tick-0320.png` |
| OF-3 | **Godot:** in Agent A, a seek past the end of the agent's own record (tick 477) is clamped to that tick. This reveals where the record ends only when the user explicitly asks for a later tick. Nothing reveals it passively, and the record's extent comes from Agent A's own file, not from broadcast data. It is recorded as a known limitation. | `agent_view_trace` "seek" and "slider" lines |
| OF-4 | Playback cost: the V6 viewer steps one phase position every 0.05 s at 1x, so a full match takes 12.8 min (omniscient). Godot takes 95.4 s at its default. Godot's two perspectives advance at the same per-tick rate. V6's Agent A rate depends on the agent's own callback count. | `capture.json` pacing; recordings |
| OF-5 | Neither omniscient view (V6 or Godot Broadcast) draws sensing. V6's distinctive mechanic is visible only in an entrant perspective, or in Godot's step captions. | screenshots at ticks 1, 12 and 320 |
| OF-6 | Godot playback shows tick-end frames only. The 15,310 action-level frames are reached only by stepping. | `main.gd` `_process` |
| OF-7 | Godot's ring keeps circular adjacency. V6's row-major grid breaks it at every 32-cell row, which distorts move arrows and wraparound. | tick 9 composite |
| OF-8 | V6 labels overlap: "sample 180sample 184" and "B/wardeA/hunter". | ticks 320 and 477 |
| OF-9 | Territory is very small: 16–24 owned cells of 512 throughout, concentrated around the two cores (168–175 and 246–253). | `moments.json` |
| OF-10 | Harrier's hunter (reach 96) moved once in 477 ticks. Nearly all action is remote writes. Movement is therefore a weak signal in this match in every viewer. This is a presentation consequence of cost-free reach (G-1, §9). | `moments.json` first events |
| OF-11 | Godot elimination styling matches the `alive` set on every broadcast frame, and the banner appears only at the recorded end. | `fixture_check` 26/26 |

## 6. Phase D3: presentation assessment

### 6.1 Scale

| Score | Meaning |
| --- | --- |
| 1 | Absent, or misleading |
| 2 | Present but hard to interpret without outside explanation |
| 3 | Understandable with some effort or a short explanation |
| 4 | Clear, with minor gaps |
| 5 | Immediately clear to a first-time viewer, no explanation needed |

### 6.2 Developer assessment (not independent validation)

These are subjective judgments by the developer, who built the Godot viewer.
They are informed by the objective findings in §5, which are not opinions.

| # | Category | A. V6 viewer | B. Godot Broadcast | C. Godot Agent A |
| --- | --- | --- | --- | --- |
| 1 | Competitor identification and distinction | 2 | 4 | 4 |
| 2 | Movement and actions | 2 | 2 | 3 |
| 3 | Sensing and uncertainty | 3 (Agent A) / 1 (omniscient) | 2 | 4 |
| 4 | Territory and core ownership | 2 | 3 | 3 |
| 5 | Meaningful tactical events | 2 | 2 | 3 |
| 6 | Pacing and visual engagement | 2 | 3 | 3 |
| 7 | Clarity of the decisive ending | 2 | 4 | 3 |
| 8 | Playback controls and perspective switching | 3 | 4 | 4 |

Supporting observations:

1. **Competitors.**
   - V6 shows ids only ("A/keeper"), no agent names, and colours that differ
     between views (green/magenta in omniscient, gold in Agent A).
   - Godot uses consistent blue and orange, names with coloured ids, and
     names Agent A in the title. The opponent stays anonymous in Agent A,
     which is correct.
2. **Movement and actions.**
   - In Godot playback, actions are invisible beyond ownership flicker
     (OF-6), and the tick-461 move has no cue.
   - Godot step mode has precise captions.
   - V6 Agent A's move arrow is a real strength, despite the grid distortion
     (OF-7).
3. **Sensing.**
   - Godot Agent A is the strongest view. At **tick 9**, three contacts appear
     on the ring: two fresh in gold and one stale in grey, matched by the list
     "cell 184 … (absent in a newer sample)". V6 conveys the same facts as
     callback-level text with overlapping labels (OF-8).
   - Godot Broadcast does not show the sensing contest at all (OF-5), which
     is its biggest gap.
4. **Cores and territory.**
   - Godot Broadcast states core integrity ("core 4/8", "core 1/8"), but the
     ring does not make it stand out. At **tick 320**, Bastion is one cell
     from elimination and nothing on the ring signals it.
   - V6 does not show cores at all.
   - Territory is tiny in this match (OF-9) for both viewers.
5. **Tactical events.**
   - In Godot, disruption is shown only as a hollow marker, with no legend.
   - Near-captures (tick 320, tick 447 at 1/8, tick 467 at A 2/8) pass in
     0.2 s at 5 ticks/s with no emphasis.
6. **Pacing.**
   - Godot's 95 s is watchable.
   - V6's 12.8 min default is not a viewing experience, and even its 8x
     maximum passes through sub-tick phases.
   - In Godot, long stretches look alike: both cores are under pressure for
     89% of ticks, with small visual change.
7. **Ending.**
   - Godot Broadcast at **tick 477** has the banner, caption, crossed markers
     and result line, so the outcome is unambiguous.
   - The capture itself comes abruptly: at tick 476 both cores are at 2/8,
     and the decisive change is a single frame in playback.
   - Godot Agent A simply stops, by design, with the static note.
   - V6 shows one text line.
8. **Controls.**
   - Godot has both buttons and keys, a speed menu, perspective switching by
     dropdown or Tab, and a tick slider. It has no End/jump-to-end key and no
     on-screen key help.
   - V6 is keyboard-first, with on-screen help, clickable perspective boxes
     and an End key.

### 6.3 Strong and weak moments

| Tick | View | Strong / weak | Observation |
| --- | --- | --- | --- |
| 9 | Godot Agent A | Strong | Fresh vs stale contacts are readable at a glance and match the list. |
| 9 | V6 Agent A | Strong / weak | The own MOVE arrow is good, but drawn as a long diagonal across grid rows for a 15-cell hop. |
| 12 | Godot Broadcast | Weak | Hunter disruption appears only as a hollow triangle, unexplained. |
| 320 | Godot Broadcast | Weak | Bastion at 1/8 (closest to losing) is visible only in the side text. |
| 320 | V6 Agent A | Weak | Overlapping sample labels, and the playhead reveals the record length (OF-2). |
| 461 | All views | Weak | The hunter's only move has no visual emphasis, and only V6 Agent A draws an arrow. |
| 476→477 | Godot Broadcast | Strong / weak | The end state is clear (banner, caption, crosses), but the decisive write sequence is visible only by stepping. |
| 477 | V6 Agent A | Weak (leak) | The result is printed in the agent perspective (OF-1). |
| 477 | Godot Agent A | Strong (correctness) | Nothing reveals the outcome. The own core is an outline, not "held". |

### 6.4 Project Lead assessment (to be completed by the Project Lead)

Please score using the same scale, after watching `./launch_showcase.ps1` in
both perspectives and the V6 recordings or a live V6 run. The developer
scores above are not intended to influence these.

| # | Category | A. V6 | B. Godot Broadcast | C. Godot Agent A | Notes |
| --- | --- | --- | --- | --- | --- |
| 1 | Competitor identification | | | | |
| 2 | Movement and actions | | | | |
| 3 | Sensing and uncertainty | | | | |
| 4 | Territory and core ownership | | | | |
| 5 | Tactical events | | | | |
| 6 | Pacing and engagement | | | | |
| 7 | Decisive ending | | | | |
| 8 | Controls and switching | | | | |

## 7. Known limitations

- There is no independent human evaluation. All scores are the developer's
  own (§6.2).
- **One fixture only.** It is an upset (Bastion wins 4 of the 77 qualifying
  matches), and Agent A follows the loser. Findings about pacing and
  territory may not generalise.
- The evidence is seven ticks and five 4–58 s recordings of the final
  segment, not complete viewing sessions.
- **Different rendering paths.** V6 frames were rendered offscreen (SDL dummy
  driver) at its default window size. Godot frames used one GPU at 1280×800.
  Font rendering may differ from an interactive V6 window.
- **Only Agent A.** The Spectator exports only the Agent A perspective, so
  Bastion's knowledge cannot be viewed.
- **Seeking past the record end (OF-3).** In Agent A, a seek past the
  agent's own record clamps to its last tick.
- **Baseline leaks recorded, not fixed.** The V6 baseline's Agent A leaks
  (OF-1, OF-2) are recorded but not fixed, because Bytefray is outside P0-D
  scope.

## 8. Phase D4: recommendations

### Must fix (misleading presentation, incorrect results, leakage, serious usability defects)

| ID | Item | Status |
| --- | --- | --- |
| M-1 | Godot Agent A drew its own core in the broadcast's solid "held" style, so a captured core looked intact. | **Fixed in D1** (`f95f9ae`): outline style and "ownership not shown" label. |
| M-2 | Godot Broadcast drew an eliminated entrant's processes at full colour (P0-C NOTE). | **Fixed in D1**: dimmed and crossed out, tested on every frame. |
| M-3 | *Bytefray V6 viewer, not this repository:* the Agent A perspective shows the recorded result (OF-1), and its timeline reveals the record length (OF-2). | **Not fixed** (Bytefray is out of scope). Reported for the Bytefray lead's decision. |

No must-fix item is open in the Godot viewer.

### Should improve (ranked)

| Rank | Item | Notes |
| --- | --- | --- |
| S1 | **Show sensing in Broadcast.** Draw each side's SENSE windows (and READs) when they happen, in the entrant's colour. | `broadcast.json` already records `kind`, `address` and `sensed` per frame, so no export change is needed. This is V6's defining mechanic and is currently invisible to an omniscient viewer. |
| S2 | **Make actions visible during playback.** Show brief per-tick write and disruption flashes at target cells, and an optional one-line summary of the tick. | V4 used transient write flashes, cleared on non-linear seeks so they never imply future activity. |
| S3 | **Give core integrity visual priority.** Add per-entrant core gauges, with emphasis when a core falls to 1–2 cells (ticks 320, 447, 467, 476). | V4 had per-entrant status cards and a core-destruction effect. Use broadcast data only. |
| S4 | **Add a legend** for the ring encodings in both perspectives: ownership band, core band or outline, filled/hollow/crossed markers, sample arc, contact triangles. | |
| S5 | **Pacing and navigation.** Add End/jump-to-end, jump-to-tick, and an on-screen key hint line. Consider a 10 ticks/s option. | |
| S6 | **Elimination moment.** Mark the capture tick itself, for example with a brief emphasis on the falling core, so the end does not arrive in a single unmarked frame. | |
| S7 | **Agent A panel noise.** Fold "observation / Delivered observation" lines into one, and mark the agent's own write targets and moves on the ring (V6 already draws move arrows). | Agent data only. |
| S8 | **Use of space.** The action occupies about 90 of 512 cells. Consider an optional zoom on the active arc. | |
| S9 | **Ring texture.** The per-cell arcs produce a visible moiré pattern in the unowned band. | |

### Future possibilities (outside P0)

- organic territory visualisation;
- camera follow and zoom;
- a cinematic mode that slows down near swings and near-captures (computed
  from broadcast data only, and never shown in Agent A);
- audio cues for disruption and capture;
- a core-pressure timeline heatmap (V4 had a territory-history graph);
- split-screen Broadcast and Agent A;
- an Agent B perspective (needs an exporter change);
- a narrated event log built from verified facts.

## 9. Gameplay observations for future M2 consideration (not changed here)

| ID | Observation | Effect on presentation observed in P0-D |
| --- | --- | --- |
| G-1 | **Reach costs nothing in alpha1** (any reach in [1, arena−1]). A full-reach agent could decide most matches within a few ticks. The showcase agents deliberately use bounded reach. | Even with bounded reach, Harrier's hunter (reach 96) moved once in 477 ticks (OF-10). Remote writes replace movement, so "movement" is barely visible in any viewer. |
| G-2 | **Rewriting a core removes its `0xCE` beacon.** Any write erases the beacon, after which only ownership, learned through READ, locates a core. | Core identification depends on ownership rather than a visible marker, which reinforces why the viewer must present ownership and core integrity clearly (S3). |

Neither behaviour was changed.

## 10. Phase D5: GO / NO-GO

**Developer recommendation: GO for further Godot investment.** This is
conditional on the Project Lead's own assessment (§6.4), and it is not
independently validated.

**Objective grounds**

- Replay correctness was preserved, and integrity validation still runs before
  anything is displayed.
- Playback is deterministic: recordings, captures and re-exports are
  byte-identical.
- The Agent A perspective holds the information boundary better than the V6
  baseline. Godot does not have OF-1 or OF-2.
- Default full-match playback is 95 s instead of 12.8 min.
- The decisive ending is now explicit in Broadcast and is tested on every
  frame.
- Godot's ring keeps circular adjacency (OF-7).

**Developer judgment**

- Competitor distinction, sensing uncertainty (in Agent A), the ending, and
  the controls are clearer than the baseline.
- Broadcast does not yet show the sensing contest (OF-5) or the action within
  a tick (OF-6). Until S1–S3 are done, Godot's advantage is presentation of
  outcome and state rather than of play.

**What would change this to NO-GO:** an independent reviewer study (Appendix
A) in which viewers cannot answer the comprehension questions better with
Godot than with the V6 viewer.

## 11. Proposed next milestone: P1 "Readable broadcast"

| Element | Proposal |
| --- | --- |
| Scope | S1–S5 and S7, on the existing `fixtures/showcase`, with no change to the export schema, the fixture or the agents. |
| Constraints | Broadcast-only effects must be computed from `broadcast.json` and never reach the Agent A model. Transient effects are cleared on non-linear seeks. The tick-boundary switching rule stays. |
| Acceptance | All P0-D tests still pass. New per-frame checks cover each overlay, for example: SENSE windows drawn exactly on frames where the broadcast records a sense. The differential isolation tests and the Agent A trace stay clean. Byte-identical recordings of the same segment. |
| Evaluation | At least three viewers not involved in development follow Appendix A on V6 and Godot, in counterbalanced order, scored against the answer key, plus the 1–5 scale. The Project Lead's scores are recorded separately. |
| Out of scope | Gameplay changes (G-1, G-2), the Bytefray V6 viewer (M-3), new agents or seeds, and organic or cinematic rendering. |

## Appendix A: reviewer protocol and answer key

Show each moment with `./launch_showcase.ps1 -Perspective <p> -Tick <t>`, or
the equivalent V6 position. Ask the questions without hints. The answers are
verified facts from the fixture (`moments.json` and the presentation files).

| # | Perspective, tick | Question | Answer |
| --- | --- | --- | --- |
| Q1 | Broadcast, 12 | Whose core is in more danger? | Bastion's (B): 4/8 cells held vs Harrier's 6/8 |
| Q2 | Broadcast, 320 | How close is either side to losing? | Bastion holds only 1 of 8 core cells |
| Q3 | Agent A, 9 | How many opponent contacts does Agent A remember, and which is out of date? | 3; cell 184 (absent in a newer sample) |
| Q4 | Broadcast, 460 → 461 | Which process moved, and how far? | Harrier's hunter, 63 cells (246 → 183) |
| Q5 | Broadcast, 477 | Who won, and how? | Bastion (B), by capturing Harrier's core (0/8); Bastion held 2/8 |
| Q6 | Agent A, 477 | Does Agent A know it has lost? | No. The result is never delivered to the agent. |
| Q7 | Agent A, 320 | Where did Agent A most recently detect the opponent? | Cells 168 and 180, sampled at tick 320 |
| Q8 | Either, any | Switch perspective and return. Did the tick change? | Only to the last completed tick boundary |

Record per viewer: the viewer, answers, time taken, and the 1–5 scores from
§6.1. Keep developer and Project Lead scores separate from independent
viewers' scores.

## Appendix B: reproduction

```powershell
$py = "D:\Projects\BATTLE2\.venv\Scripts\python.exe"
$godot = "C:\Program Files\Godot\Godot_v4.7.2-stable_win64_console.exe"
& $py docs/p0d/moments.py                                   # comparison ticks
& $py exporter/capture_v6_viewer.py --bytefray-root D:\Projects\BATTLE2 --source fixtures/showcase/source --out <dir> --ticks 1,9,12,320,461,476,477
& $godot --path . --script res://tests/capture_frames.gd -- --fixture=showcase --out=<dir> --ticks=1,9,12,320,461,476,477
& $godot --path . --write-movie <file.avi> --fixed-fps 30 --quit-after 256 -- --fixture=showcase --perspective=broadcast --tick=440 --speed=5 --play
& $py exporter/capture_v6_viewer.py --bytefray-root D:\Projects\BATTLE2 --source fixtures/showcase/source --out <file.mp4> --record omniscient --start 440 --speed 8
& $py -m pytest --basetemp=D:\Projects\Bytefray-Spectator-work\<new dir>
& $godot --headless --path . --script res://tests/smoke_test.gd
& $godot --headless --path . --script res://tests/fixture_check.gd -- --fixture=showcase
```
