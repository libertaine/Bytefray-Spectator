# Bytefray-Spectator — P1 readable broadcast review (01)

> Spectator commit IDs in this publication copy identify equivalent stages in the sanitized public history. Original dates and test outcomes remain historical; frozen declarations and checksum-bound evidence are unchanged.

For: Project Lead. Responds to "Bytefray-Spectator — P1 Readable Broadcast
Authorization" (P0-D accepted, P1 authorized, 2026-10-12).

All commits are local. Nothing was pushed, no remote was created and nothing
was released. There were no gameplay changes, no new agents, no seed search
and no research execution. The frozen fixture, the agents, the selection
records and the presentation-v1 export format are unchanged. Bytefray was
not modified, and Spectator's pin is still `9c81718`. E9 remains **LOCKED**;
Requirement C remains **NOT ESTABLISHED**.

**Headline.** P1-0 to P1-5 are implemented and verified:

- The Broadcast now shows the sensing contest, the actions within each tick,
  each entrant's core integrity and the decisive capture, all derived from
  recorded frames.
- Agent A's information boundary holds.
- An independent code review (an AI agent, not a human) found one MEDIUM and
  five LOW issues, plus a test gap. All are fixed, each with a test that
  fails when the defect is reintroduced.

**P1-6 independent viewer results are pending.** No viewer session has been
run. The evaluation kit is ready (§6).

## 1. Exact local commits

| Commit | Content |
| --- | --- |
| `2701485` | P1-0 baseline: screenshots of the unchanged P0-D viewer at the 9 review ticks, with the fixture digests and baseline test results (`docs/p1/baseline/`) |
| `d46ebdb` | P1-1 to P1-5 implementation and tests |
| `f5c0333` | Separate Bytefray maintenance item: V6 Agent A disclosure correction proposal (`docs/BYTEFRAY_V6_AGENT_VIEW_DISCLOSURE_CORRECTION_01.md`) |
| `44d4a77` | P1-6 evaluation kit (`docs/p1/evaluation/`) |
| `402b0a6` | Test fix after the first qualification run (§4.1) |
| `b6e3124` | Fixes for the independent review findings F1–F6 and test gap T1 |
| `c0af3d1` | Residuals from the reviewer's re-verification: F5 wording and the tick-0 switch check |
| `80811dd`, `5dcf58e`, `a5d6ce3` | Evidence: after-screenshots, before/after composites, recordings, review-tick facts and `SHA256SUMS` (`docs/p1/`). The two follow-ups store `review_ticks.json` with LF and limit `SHA256SUMS` to tracked files, so it verifies on a fresh checkout. |
| this report | The commit that adds this file and the independent review record, `docs/P1_INDEPENDENT_REVIEW_01.md` |

The base was `da8000a` (P0-D report). The Bytefray checkout stayed at
`v6-research` HEAD `2fc3c82` throughout (§5.4).

## 2. Implemented capabilities

Every broadcast effect is computed by `scripts/broadcast_effects.gd` from the
recorded `broadcast.json` frames. Each one is a **pure function of the frame
index**: it shows only recorded facts at or before the current frame, and
only from the last 3 ticks. Seeking, restarting, jumping or switching
perspective therefore redraws the effects from the record, and the ring view
keeps no history.

Godot simulates nothing and reconstructs no knowledge:

- a sample's contents are the recorded `sensed` field of the SENSE action;
- its delivery is the recorded `sensed` field on the same process's next
  OBSERVATION frame;
- ownership changes are the recorded `owner_changes`;
- disruption is the recorded tick-end `disrupted` set;
- elimination is the recorded `alive` set.

The only rule constant is the ruleset's public SENSE half-width, 27, which a
test checks against the pinned Bytefray `RulesetPolicy.sensing_window`.

### P1-1 Broadcast sensing

- Each entrant's SENSE samples are drawn in **its own inner lane**, in that
  entrant's colour (A blue, B orange, the same colours used everywhere).
  Simultaneous or overlapping samples from both sides therefore stay
  visible. Both sides have a sample pending at the same time on 889 showcase
  frames.
- The sampled window (centre ± 27) is **dashed while the sample is taken but
  not yet delivered**. The anchors it caught are shown as hollow dots. A thin
  line runs from the process that asked.
- The window becomes **solid at the recorded delivery frame**, with the
  anchors filled and a line to the receiving process. It then fades over
  3 ticks.
- Captions: "B/raider SENSE 252 - sampled 2 anchors at 240, 246", and at
  delivery, "A/hunter receives its observation - SENSE sample from tick 1
  delivered (1 anchor at 168)".
- Order is preserved. A sample is never shown delivered before its recorded
  delivery frame. Delivery latency in the showcase is 0 ticks for 864
  samples, 1 tick for 284 and 2 ticks for 18.

### P1-2 Actions

- **WRITE.** The target cell is marked filled if the write took the cell, and
  as a ring if the owner was unchanged. A refused write is drawn as a cross,
  so attempts and applied effects are distinct. In the current tick a chord
  runs from the writing process to its target, which makes remote writes
  readable.
- **MOVE.** An arrow follows the ring from the recorded old anchor to the new
  one. Harrier's single 63-cell hunter move at tick 461 is now a large,
  obvious arc.
- **Disruption.** A burst marks each process in the recorded tick-end set. A
  test confirms that this set equals the opponent WRITEs on that process's
  anchor during the tick. The marker stays hollow while the hit is in effect.
- **Core ownership changes.** A red ring marks a core cell lost and a white
  ring a core cell regained.
- **Playback.** Each recorded frame of a tick gets an equal, in-order share of
  the tick's time. At 1 tick/s each action appears in turn. At higher
  speeds the 3-tick effects carry the actions.
- **Captions.** While playing, the caption holds the last completed tick's
  summary, for example "Tick 320 ends - A: 6 writes (took 4, 4 core, 2 hits),
  2 senses   B: 5 writes (1 hit), 1 sense". When paused or stepping, it
  describes the current recorded fact and its recorded outcome. The side
  panel shows "Tick n so far" counts and the last 6 actions.
- No cinematic animation was added.

### P1-3 Core status and critical events

- **Broadcast-only core cards.** Each card shows the entrant's eight core
  cells in core order (held or lost), "core n/8", and the change since the
  last tick boundary ("lost 4 this tick", "regained 1 this tick").
- **Levels.** CRITICAL (2 or fewer cells) gets a red card, and ELIMINATED is
  dimmed.
- **Validation against the authoritative tick states.** The gauges at all 478
  tick ends equal the core counts and alive state recomputed from
  `source/replay.jsonl` alone. The independent reviewer also reproduced this
  comparison.
- **Decisive capture.** B/raider WRITE 250 (frame 15308) takes A's last core
  cell. At that frame it is shown as "A core cell lost" and A's card reads
  0/8. From the recorded elimination frame (15309) it is marked **CORE
  CAPTURED**, drawn alongside the result banner, and named in the caption:
  "Tick 477 ends - A spectator_harrier eliminated (core 0/8) - decisive
  capture: B/raider WRITE 250".
- Agent A never receives core cards, effects or ownership (§5).

**Review ticks** (from `docs/p1/review_ticks.json`, and what the P1 cards
show):

| Tick | A core | B core | What P1 now shows |
| --- | --- | --- | --- |
| 12 | 6/8 (+1) | 4/8 (+2) | Both sides retaking core cells; 9 core cell changes this tick; A/hunter hit |
| 320 | 4/8 | **1/8 (−4)**, CRITICAL | Bastion loses 4 core cells in one tick; P0-D showed this only in the side text |
| 447 | 3/8 | **1/8 (−2)**, CRITICAL | The second near miss |
| 467 | **2/8 (−1)**, CRITICAL | 8/8 | Harrier under pressure |
| 476 | **2/8 (−3)**, CRITICAL | **2/8 (−1)**, CRITICAL | Both cards red |
| 477 | **0/8, ELIMINATED** | 2/8 | The decisive capture with the banner |

### P1-4 Controls and readability

- **New controls:**
  - End key and button;
  - jump to tick (G, or the Tick box with Enter or Go);
  - speeds 1, 2, 5, 10, 20, 60 and 200 ticks/s, with − and + keys (2 and 10
    are new);
  - an always-visible key hint line;
  - a help overlay (H, F1 or ?);
  - a concise per-perspective legend that draws each glyph (L toggles it).
    The legend is static, so it reveals nothing.
- **Agent A:**
  - "observation / Delivered observation" lines are folded away. Only
    observations that delivered a sample, and delivered READ results, are
    kept, each with its tick.
  - Agent A's own MOVE arrows, WRITE targets and pending SENSE requests come
    from `agent_a.json` alone. WRITE targets are drawn as outlines, because
    the outcome of a write is never delivered to the agent.
- **Review of Agent A seeking past its last observation:** see §5.2.
- The perspective export format was not modified.

## 3. Before/after evidence (same fixture)

All under `docs/p1/`. `SHA256SUMS` covers 62 tracked files, with digest
`9292357eed4e3d59f542b38ec6ebcdd6cf5793b693cdf2004ca682a201856c9d`. It
verifies on a fresh checkout.

| Evidence | Content |
| --- | --- |
| `baseline/` | P1-0: the unchanged P0-D viewer at ticks 1, 9, 12, 320, 447, 461, 467, 476 and 477, both perspectives |
| `after/` | The same ticks and perspectives rendered at `b6e3124`. Re-rendering at the final commit `c0af3d1` gives byte-identical images, since that commit changed only the hidden help text and a test. |
| `side_by_side/` | 18 composites, before (left) and after (right) |
| `recordings/` | Ticks 440→477 at 5 ticks/s, 30 fps, 256 frames: P1 and baseline, Broadcast and Agent A, with `recordings.json` |
| `review_ticks.py`, `.json` | The review-tick facts, derived read-only from `broadcast.json` |

**Rendering.** This machine's display is now 1080 px wide, so a 1280×800
window can no longer open at full size. `capture_frames.gd` and the new
`record_frames.gd` therefore render into a fixed 1280×800 SubViewport. To
show the before and after images are comparable, the new capture path was run
on the baseline code. It reproduced all 18 committed P1-0 screenshots
**byte-identically**.

**Determinism.** Two independent recordings of each P1 segment produced
identical PNG frames and identical H.264 files. This held at both `d46ebdb`
and `b6e3124`:

| Recording | MP4 at `d46ebdb` | MP4 at `b6e3124` |
| --- | --- | --- |
| Broadcast | `74011c03…cc308` | `c264b8a8…88e9` |
| Agent A | `b3cafc17…22b3` | `b3cafc17…22b3` (unchanged) |

Agent A is unchanged because the review fixes affect Broadcast only.

## 4. Tests and independent code review

### 4.1 Results

| Check | P1-0 baseline (`da8000a`) | P1 (`c0af3d1`) |
| --- | --- | --- |
| pytest (exporter, isolation, agents, showcase, V6 capture) | 36 passed (241 s) | **37 passed** (281 s) |
| `smoke_test.gd` | 35 / 35 | **55 / 55** |
| `fixture_check.gd` showcase | 26 / 26 | **45 / 45** |
| `fixture_check.gd` dev | 20 / 20 | **31 / 31** |
| Mutation checks (12 injected defects, at `b6e3124`) | — | **12 / 12 caught**, files restored byte-identically; the tick-0 switch case added in `c0af3d1` was also shown to fail with the F2 fix reverted |
| `ruff check`, `ruff format --check` | clean | clean for all P1 files |

**Qualification history.** Each run used a fresh `--basetemp` under
`Bytefray-Spectator-work/p1/` and ran against a committed tree, with HEAD,
status and digests recorded before and after. The runs were sequential.

- The first run at `44d4a77` gave **36 passed, 1 failed**. A new assertion
  located trace fields by index, but the footer and key hint contain the
  field separator, so the indexes were wrong. The viewer itself was correct,
  and the unobserved-variant equality checks in the same test had passed.
- After the fix (`402b0a6`) the suite passed 37/37.
- After the review fixes (`b6e3124`) it passed **37/37** again.
- After the re-verification residuals (`c0af3d1`) it passed **37/37**. This
  is the final qualified commit. HEAD, status and all critical digests were
  unchanged after each run.

**New coverage.** `fixture_check` builds its own references from the
presentation files and checks **every frame**:

- **Broadcast effects.** The broadcast shows exactly the recorded actions of
  the window up to the current frame, and nothing later. Their recorded
  fields and outcomes are checked: took or kept, core damage or recovery,
  hits, and MOVE from and to.
- **SENSE samples.** Each is pending until its recorded delivery and
  delivered afterwards. The reference uses a sound bound, plus a whole-record
  scan every 97th frame. Every recorded anchor lies inside the drawn window.
- **No later data.** No shown effect carries data from a later frame.
- **Disruptions and core gauges.**
  - Disruptions are the recorded sets, and WRITE hits equal them every tick.
  - The core gauges equal an independent count, with the correct delta and
    level.
- **Decisive capture.**
  - There is exactly one decisive capture, and it is the winner's WRITE on
    the loser's core.
  - Before the elimination it is shown as "core cell lost", and from the
    elimination on it is shown as decisive.
  - It is drawn with the banner.
- **Agent A.**
  - Its own indicators equal a reference built from `agent_a.json` alone.
  - The view holds no broadcast state, effects or core cards.
  - Its legend is static.
- **Navigation.** 400 random navigation operations are checked: seek,
  restart, steps, End, jump, slider, perspective switches, playback, and
  switches during playback. After each one, what is drawn equals what
  sequential stepping drew at that index.
- **Switching during playback.** From every mid-tick frame of the first 400,
  in both directions, playback resumes at the boundary.
- **Playback order.** At 1 tick/s, playback visits every frame of a tick in
  order.

**Other test additions:**

- **pytest:**
  - checks the SENSE half-width against the pinned ruleset and against every
    Agent A sample;
  - checks the core gauges against `replay.jsonl` at all 478 ticks;
  - checks the explicit review-tick values.
- **The Agent A differential trace** now also records:
  - the legend, the key hint, and any broadcast effects or cores held by the
    ring (they must be empty);
  - End, the tick box, slow playback and switching in from a playing
    Broadcast.
- **The smoke test** covers the new controls.

**Unchanged and still passing:**

- frozen fixture digests;
- byte-identical re-export;
- reproduction of the match from the frozen agents;
- the differential knowledge-isolation tests;
- the V6 capture test.

### 4.2 Independent code review

The full record is `docs/P1_INDEPENDENT_REVIEW_01.md`.

The reviewer was an AI agent (Claude) started by this session, with no part
in writing P1. **It is not a human reviewer.** It worked read-only in a
separate worktree of `d46ebdb` and was not allowed to run pytest. Its
verdict was **ACCEPT WITH FINDINGS**, with no BLOCKER or HIGH finding. The
developer reproduced each finding before fixing it.

| ID | Severity | Finding | Fixed in `b6e3124` |
| --- | --- | --- | --- |
| F1 | MEDIUM | Delivered SENSE samples disappeared mid-tick, and the shown set depended on later frames. The test copied the same faulty bound. | Search starts at a sound bound, and the test independently scans the whole record (M9 catches the regression) |
| F2 | LOW | Switching perspective while playing could carry the other perspective's progress through a tick (only at ticks 0–1) | Every navigation resets the playback sync (M10) |
| F3 | LOW | The decisive mark appeared one frame before the recorded elimination | Marked from the elimination frame, alongside the banner (M11) |
| F4 | LOW | Legend: "hollow = hit this tick" is wrong mid-tick | Now "last tick" |
| F5 | LOW | Help and README overstated per-frame playback at speed | Wording corrected |
| F6 | NOTE | Pending samples carried their future delivery data, which was not drawn | Blanked while pending (M12) |
| T1 | test gap | No switch-while-playing coverage | Added in three places |

**Fix verification.** The same reviewer re-checked `b6e3124` and confirmed
F1–F4, F6 and T1 **VERIFIED FIXED**, with no material new issue:

- **F1.** 0 frame differences against the 3-tick rule in either fixture.
  Captions, gauges and effects built from records cut at 99 sampled frames
  match the full record.
- **F5.** One wording residual: "1–2 ticks/s" should be "1 tick/s".
- **T1.** One gap: the tick-0 switch case.

Both were fixed in `c0af3d1`. The new tick-0 check fails with the F2 fix
reverted. The re-verification is recorded in
`docs/P1_INDEPENDENT_REVIEW_01.md`.

## 5. Information-isolation findings

### 5.1 What holds

- Agent A's view is built only from `agent_a.json`, together with public
  constants: the tick limit from the manifest and the ruleset's SENSE
  half-width. In Agent A mode the ring view drops every broadcast field, the
  effects and the core cards. Its legend, help and hint are static text.
- Agent A's playback is paced by its own frames only. F2 broke this at ticks
  0–1; it is fixed and tested.
- The differential test is unchanged in principle and passes. Window Scout
  plays three opponents whose activity Agent A never observes (different
  action kinds, process counts and per-tick decision counts), and everything
  the Agent A view shows is byte-identical across them, under every
  operation, now including End, jump, slow playback and switching during
  playback. A positive control proves the comparison can see a real
  difference.
- No broadcast-derived visual information reaches Agent A. This is checked on
  every frame in `fixture_check` and on every trace line in pytest.
- **P1 adds no new passive disclosure.** The independent reviewer reached the
  same conclusion.

### 5.2 Determination: Agent A seeking past its final recorded observation (OF-3)

**Determination: yes, the clamping discloses information beyond the stated
perspective contract**, which is "shows the public tick limit, never the
match length". The disclosure appears **only on explicit navigation**, and
**it cannot be removed without misrepresenting the record**.

- **What is revealed.** Agent A's record ends at its last callback. That is
  Agent A's elimination or the match end, tick 477 in the showcase. Seeking,
  dragging the slider, using the tick box or End to a later tick lands on
  477. Playback and stepping also stop there. P0-D's OF-3 described this as
  disclosed only by "an explicit later seek". In fact, letting playback run
  to the end reveals it as well.
- **What is not revealed.** Nothing shows it *passively*. The position label
  is "Tick n (limit 1000)", the timeline spans the public limit, and there is
  no banner, result, elimination text or frame total. All of this is checked
  on every frame and on every trace line.
- **Why it cannot simply be fixed.** Any viewer of Agent A's record can only
  show positions that exist in it. The alternative to clamping is to pad
  ticks 478–1000 with positions Agent A never had. Even a frozen "no new
  callbacks" view would be distinguishable from live play, because a living
  agent receives callbacks every tick. Padding would still reveal the end,
  and it would also fabricate perspective data.
- **P1 behaviour.** P1 keeps the clamp unchanged. End and the tick box behave
  exactly like the existing slider and seek, and add no new kind of
  disclosure.
- **Decision requested from the Project Lead.** Choose one:
  1. Accept the narrower contract: *no passive disclosure; explicit
     navigation to or past the end of Agent A's record shows where it ends*.
     The README now states this.
  2. Or require Agent A to be reachable only up to the Broadcast's current
     tick (a "no spoilers" coupling), which would make the end discoverable
     only after the Broadcast reaches it.

  Option 1 is recommended.

### 5.3 V6 baseline leaks (separate Bytefray maintenance item)

`docs/BYTEFRAY_V6_AGENT_VIEW_DISCLOSURE_CORRECTION_01.md` documents two
defects in the V6 sensing viewer:

- **BF-1.** The recorded result is printed in the entrant perspective
  (`sensing_renderer.py:158-159`).
- **BF-2.** The timeline playhead is placed by the length of the entrant's
  own record (`:151-154`, and `seek_from_mouse` `:107-114`).

The file also covers the inherent navigation clamp (BF-3), proposes a
narrow, client-only correction with tests, and confirms that the code is
identical at `9c81718` and `2fc3c82`. Bytefray was not modified and the pin
is unchanged.

### 5.4 Bytefray integrity

Bytefray checkout HEAD remained `2fc3c82`; `engine/` and `client/` were
unchanged by the Spectator evaluation.

Every Spectator export and test verified the pinned 142 files.

## 6. Independent viewer results (P1-6)

**Pending. No viewer session has been run.** The development session cannot
recruit people, and no viewer who took no part in development was
available. No result is reported or implied.

The kit is ready in `docs/p1/evaluation/`:

| File | Content |
| --- | --- |
| `FACILITATOR_PROTOCOL.md` | The protocol (summarized below) |
| `REVIEWER_SHEET.md` | The questions, with no answers |
| `ANSWER_KEY.md` | The answer key, for the facilitator only |
| `results_template.csv` | One row per viewer, viewer tool and question |

The protocol covers:

- **Eligibility.** At least three viewers with no development involvement.
- **Counterbalancing.** The order alternates: V6 then Godot, Godot then V6,
  V6 then Godot.
- **Comparable viewing.** Each viewer first watches the full match at the
  same duration in both viewers: V6 at 8x, about 96 s, and Godot at 5
  ticks/s, 95 s. Each question then allows 90 s with free controls within
  ±20 ticks.
- **Recording.** Correctness, time to answer, confusing or misleading
  elements, the 1–5 scores and comments are recorded. Developer, Project
  Lead and viewer results are kept separate.
- **V6 leaks.** BF-1 and BF-2 are accounted for explicitly:
  - an answer that uses the leaked result text or playhead is tagged
    `leak-assisted` and excluded from the comparison;
  - a V6 Q6 answer of "yes, it knows" that cites the printed result is
    scored wrong and tagged `leak-misled`;
  - Godot's own clamp is tagged `clamp-assisted` in the same way.
- **Weight of evidence.** Three viewers give formative feedback, not
  statistically conclusive validation.

The Appendix A questions are unchanged from P0-D.

## 7. Unresolved presentation problems

| # | Problem | Notes |
| --- | --- | --- |
| U1 | **Density at the action cluster.** About 90 of the 512 cells hold all the action, and effects overlap there (writes, chords, core rings and bursts around cells 168–175 and 246–253). | P0-D S8 (zoom on the active arc) was not in P1. This is the main remaining legibility limit. |
| U2 | At 5 ticks/s, about 60 of the roughly 165 recorded broadcast frames per second are displayed. | Effects persist for 3 ticks, so no action vanishes. The ordering within a tick is fully visible only at 1 tick/s (F5). |
| U3 | Long tick-end captions are cut off with an ellipsis at 1280 px. | The full summary is in the side panel. |
| U4 | Refused actions (out-of-reach SENSE or WRITE, exceptions) are drawn as crosses, but **no fixture contains one**, so that path is untested against data. | It needs a fixture with refusals, which would need authorization. |
| U5 | One decisive fixture (an upset), plus the tick-limit dev fixture. | The findings may not generalize. |
| U6 | Ring moiré in the unowned band (P0-D S9). | Not addressed. |
| U7 | Agent A's record end is shown on explicit navigation (§5.2). | Awaits the Project Lead's decision. |
| U8 | Only Agent A's perspective exists; Agent B's would need an export change. | Not authorized. |
| U9 | The V6 baseline still leaks (BF-1, BF-2) until Bytefray is corrected. | Separate maintenance item. |
| U10 | On a display narrower than 1280 px, the interactive window opens narrower and the layout compresses. | Evidence is rendered at a fixed 1280×800. |

## 8. Recommendation for P2 and public-release readiness

**Developer recommendation: run P1-6 before committing to a P2 scope.**
P1 makes the Broadcast's play visible, not only its outcome: sensing,
remote writes, moves, disruption, core pressure and the decisive capture.
Whether first-time viewers actually understand the match better is an open
question until the counterbalanced sessions are run.

**Proposed P2, subject to the P1-6 outcome:**

1. Readability at the action cluster: an optional zoom or lens on the active
   arc, computed from Broadcast data only and never shown in Agent A, plus
   the moiré fix (U1, U6).
2. Decide U7 and record the Agent A contract formally.
3. Fixture coverage for refused actions and a second decisive match, under a
   new, separately authorized selection protocol version (U4, U5).
4. If authorized: an Agent B perspective (an export format change, U8).
5. Fix whatever P1-6 shows to be confusing.

**Public-release readiness: NOT READY.** The reasons:

- there is no independent viewer evidence yet;
- there is a single showcase fixture;
- the interactive window assumes a 1280×800 display;
- there is no packaging or export build;
- the Bytefray V6 baseline still has its known leaks;
- no remote, licence decision or release process has been authorized.

The verified-replay architecture, the isolation tests and the deterministic
evidence pipeline are in a state that a release could build on.

Stopping at the P1 checkpoint.

## Appendix: reproduction

```powershell
$py = "D:\Projects\BATTLE2\.venv\Scripts\python.exe"
$godot = "C:\Program Files\Godot\Godot_v4.7.2-stable_win64_console.exe"
& $py -m pytest --basetemp=D:\Projects\Bytefray-Spectator-work\<new dir>
& $godot --headless --path . --script res://tests/smoke_test.gd
& $godot --headless --path . --script res://tests/fixture_check.gd -- --fixture=showcase --core-log=<file>
& $godot --headless --path . --script res://tests/fixture_check.gd -- --fixture=dev
& $godot --path . --script res://tests/capture_frames.gd -- --fixture=showcase --out=<dir> --ticks=1,9,12,320,447,461,467,476,477
& $godot --path . --script res://tests/record_frames.gd -- --fixture=showcase --perspective=broadcast --tick=440 --speed=5 --fps=30 --frames=256 --out=<dir>
ffmpeg -framerate 30 -i <dir>/frame-%05d.png -c:v libx264 -preset slow -crf 28 -pix_fmt yuv420p <file.mp4>
& $py docs/p1/review_ticks.py
./launch_showcase.ps1 -Perspective broadcast -Tick 470 -Speed 1 -Play
```
