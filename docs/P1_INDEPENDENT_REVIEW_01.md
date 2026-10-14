# P1 — independent code review (record 01)

> Spectator commit IDs in this publication copy identify equivalent stages in the sanitized public history. Original dates and test outcomes remain historical; frozen declarations and checksum-bound evidence are unchanged.

Authorization: Project Lead, "Bytefray-Spectator — P1 Readable Broadcast
Authorization", P1-5 ("Arrange independent code review for changes affecting
event timing, seeking or information isolation"). Local repository only;
nothing pushed.

**Reviewer.** An AI agent (Claude) that the developer session started for
this review. It had no part in writing P1. **It is not a human reviewer.** It
worked read-only against a separate worktree of commit `d46ebdb`, the P1
implementation, against the P1-0 baseline `2701485`. It was not allowed to
run pytest, because the qualification run was in progress. It ran the Godot
checks and its own probe scripts in that worktree, and used the pinned
Bytefray (`9c81718`) as a read-only reference. Its probes are kept outside
the repository, under `Bytefray-Spectator-work/p1/review-scratch/`.

The developer reproduced every finding before fixing it (F1 and F2 with
their own probe). The fixes are in commit `b6e3124`.

## Verdict

**ACCEPT WITH FINDINGS.** There was no BLOCKER and no HIGH finding.

- F1 (MEDIUM) was a real effects defect, and the test meant to catch it
  copied the same defect.
- F2–F5 are LOW, F6 is a NOTE, and T1 is a test gap.

Every finding was corrected. Each correction has a test, and each test was
shown to fail when the defect is reintroduced (mutations M9–M12 below).

## Findings and dispositions

| ID | Severity | Finding | Reproduction | Correction |
| --- | --- | --- | --- | --- |
| F1 | MEDIUM | **Delivered SENSE samples disappeared early.** The lookup started at `index − _sense_span`, but a delivered sample stays visible for 3 ticks after its delivery. So samples dropped out mid-tick, before their fade ended. Because `_sense_span` comes from the whole record, the shown set could also depend on later frames. `fixture_check` built its expected list with the same bound, so it passed. | Showcase index 65 shows the frame-2 sample delivered (age 1). Index 66, in the same tick, does not. Reproduced by the developer: `at(65)` senses `[[2,delivered,1],[8,…],[30,…],[51,…]]`, `at(66)` without frame 2. In the dev fixture every delivered sample was visible for one frame only. | The search now starts at `window start − _sense_span`. That bound is sound: a sample shown in the window was either delivered in the window or is still pending. The test uses the same sound bound, and every 97th frame it scans the whole record from frame 0 instead. Reintroducing the old bound now fails (M9). |
| F2 | LOW | Switching perspective during playback did not reset the playback sync. When the new perspective's boundary index equalled the old playback index, which happens only at ticks 0–1, the other perspective's progress through the tick was carried over. That carry-over could put Agent A's pacing under 1/33 of a tick off, based on broadcast frame counts. | Agent A playing at index 33 (tick 2, progress 0.941). After switching to broadcast it was at index 33. One step of 1/240 s later it was at **64**, not 33. Reproduced by the developer. | Every navigation (switch, restart, step, seek, load) resets the sync, so playback resumes from the new position. New check: for every mid-tick frame of the first 400 frames, in both directions, switching while playing resumes at the boundary. Random navigation now also switches while playing. The Agent A differential trace switches in from a playing broadcast. Removing the reset fails (M10). |
| F3 | LOW | The decisive-capture mark looked ahead. It was shown on the WRITE frame (15308), but the elimination is recorded only at the next TICK_END frame (15309). | The caption at 15308 read "…A core cell lost, DECISIVE CAPTURE" with no banner. | The WRITE is marked decisive only from the recorded elimination frame onward, which is the frame where the banner appears, so it is still drawn alongside the result. At the WRITE frame itself it is shown as "A core cell lost", and the gauge already reads 0/8. The elimination caption names it: "decisive capture: B/raider WRITE 250". A per-frame check covers this. Showing it early fails (M11). |
| F4 | LOW | The legend said "hollow = hit by an opponent WRITE **this tick**". The recorded `disrupted` set changes only at TICK_END, so mid-tick the hollow marker means a hit in the previous tick. | Index 199 (tick 7, OBSERVATION): B/raider and B/warden drawn hollow for hits recorded at tick 6. | The legend now reads "hollow = hit by an opponent WRITE last tick". At a TICK_END frame the set is the hits of the tick that has just completed. |
| F5 | LOW | The help and README said playback "passes through every recorded frame". That holds only at slow speeds. At 5 ticks/s and 60 fps, about 60 of 165 broadcast frames are actually displayed. | Reviewer probe: 60 steps of 1/60 s at 5 ticks/s. | The wording is corrected. Every frame gets an equal, in-order share of the tick's time. At 1 tick/s each action of a tick appears in turn (the first fix said "1–2 ticks/s", corrected in `c0af3d1` after re-verification). At higher speeds the 3-tick effects carry the actions. There is no code change. |
| F6 | NOTE | Pending SENSE records handed to the ring carried their future `delivered` frame and `receiver` anchor. Nothing drew them, but they would leak a later frame if a later change used them. | Index 2: the pending sample from frame 2 carried `delivered=9, receiver=246`. | These fields are blanked (−1) while the sample is pending. Shown actions no longer carry the decisive frame either. A per-frame check covers both. Not blanking them fails (M12). |
| T1 | LOW (test gap) | Neither random navigation nor the differential trace switched perspective while playing. Separately, the F1 test expectation copied the implementation's bound. | — | Covered under F1 and F2. |

## Mutation checks

`fixture_check` (showcase) was run with each of these defects deliberately
injected. Every defect was caught, and every mutated file was restored
byte-for-byte afterwards.

| Mutation | Result |
| --- | --- |
| M1 an action from a later frame is shown | caught |
| M2 a sample is shown as delivered before its recorded delivery | caught |
| M3 effects are kept across seeks | caught |
| M4 Agent A indicators are kept for 4 ticks instead of 3 | caught |
| M5 broadcast effects are left in the ring in Agent A | caught |
| M6 the core delta is measured against the current tick | caught |
| M7 the decisive capture is not marked | caught |
| M8 playback skips the frames inside a tick | caught |
| M9 F1 regression (search from `index − span`) | caught: frame 66 is missing the frame-2 sample |
| M10 F2 regression (no reset on a switch) | caught: "agent_a index 33 -> broadcast: resumed at 64, not the boundary 33" |
| M11 F3 regression (decisive from the WRITE frame) | caught: 3 checks fail |
| M12 F6 regression (pending sample carries its delivery) | caught |

M1–M8 were first run against `d46ebdb`, before the review, and all were
caught. All twelve were re-run against the corrected code.

## What the reviewer confirmed

- Effects are a pure function of the frame index, and the ring keeps no
  history. `show_agent` clears effects and core gauges. 400 random
  navigation operations pass. F1 and F3 were the only dependences on later
  frames.
- Each SENSE stays pending until the recorded delivery and is never shown
  delivered early:
  - every pairing is correct (1,166 showcase and 2,000 dev deliveries);
  - the one undelivered SENSE (B/warden, frame 15300) stays pending at the
    end;
  - Agent A's pending requests are keyed from `agent_a.json` only.
- Disruptions come from the recorded tick-end sets. The WRITE hit rule
  matches Bytefray's rule (the target must be an anchor of an alive
  opponent).
- The core gauges equal `source/replay.jsonl` at all 478 ticks, both held
  counts and alive state, with 0 mismatches. The reviewer reproduced this
  independently.
- The decisive capture is B/raider WRITE 250 at frame 15308. It is the only
  one, and it is drawn with the banner.
- Sub-tick pacing gives each frame an equal share, using the current
  perspective's frames only (subject to F2, now fixed).
- Agent A's own MOVE/WRITE/pending-SENSE indicators come only from
  `agent_a.json`. Its WRITE targets are drawn as outlines. The legend, hint
  and help are static. The timeline maximum is the public tick limit.
- **P1 adds no new passive disclosure of the match length.** End and the
  tick box are explicit navigation, of the same kind as the documented
  slider and seek clamp. Playback stops at Agent A's record end, as before.
- Switching lands on the last completed tick boundary.

## Re-verification of the fixes

The same reviewer re-checked `b6e3124` under the same constraints: read-only,
in its worktree, with no pytest. On the unmodified code, `fixture_check`
gave 45/45 (showcase) and 31/31 (dev), and `smoke_test` gave 55/55.

| Finding | Status | Evidence |
| --- | --- | --- |
| F1 | VERIFIED FIXED | Every frame's drawn samples were compared with the 3-tick rule built from `broadcast.json`: 0 of 15,310 showcase frames and 0 of 32,989 dev frames differ, and the oldest delivered sample drawn is age 2. Building `at()`, the gauges, summaries and captions from a record cut at each of 99 sampled frames gave 0 differences, so nothing depends on later frames. |
| F2 | VERIFIED FIXED | Agent A at index 33 switched to Broadcast stays at 33 (dev: 21). Broadcast at index 0 with progress 0.02 switched to Agent A carries no progress. Every navigation path resets the sync. |
| F3 | VERIFIED FIXED | Nothing is drawn as decisive at 15307 or 15308; the 15308 caption reads "…took the cell, A core cell lost". At 15309 there is one decisive mark, the banner, and "decisive capture: B/raider WRITE 250". |
| F4 | VERIFIED FIXED | The legend matches the recorded semantics. |
| F5 | FIXED, residual wording | "At 1–2 ticks/s" was still slightly too strong: at 2 ticks/s and 60 fps a 33-frame broadcast tick gets only 30 display frames. Corrected to "at 1 tick/s" in `c0af3d1`. |
| F6 | VERIFIED FIXED | 0 pending samples carry delivery data on any frame of either fixture, and no shown action carries `decisive_from`. |
| T1 | VERIFIED FIXED, one gap | Reverting the F1, F2 and F3 fixes makes `fixture_check` fail on each. The switch check skipped tick-end frames, so the tick-0 Broadcast→Agent A case was not covered. `c0af3d1` adds it, asserting on the carried progress; it fails with the F2 fix reverted ("progress 0.020100 carried over"). |
| New issues | NONE material | `decisive_at` scans all actions on tick-end captions, which is negligible. The longer elimination caption is cut off with an ellipsis at narrow widths, like other long captions. |

## What the reviewer did not verify

- **pytest.** It was not allowed to run it. The developer's qualification
  run covers it (see the P1 review report).
- **The capture and record scripts.** They need a real renderer, so the
  reviewer verified their determinism by reading the code. The developer
  verified it by running them (byte-identical repeat recordings).
- **Refused actions** (an out-of-reach SENSE or WRITE). Neither fixture
  contains one, because every recorded action is APPLIED, so these drawing
  and caption paths are not exercised by the fixtures.
