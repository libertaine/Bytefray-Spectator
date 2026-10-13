# Bytefray V6 sensing viewer — Agent A disclosure correction (proposal 01)

For: the Bytefray lead. This is a separate Bytefray maintenance item named in
the P1 authorization ("Separate Bytefray maintenance item"). It can be
reviewed on its own, independently of Spectator P1.

**Status: proposal only.** Nothing in Bytefray was modified. The Spectator
pin (`9c81718`) is unchanged. The code locations below are identical at the
pin and at the current `v6-research` HEAD `2fc3c82`: `git diff --stat
9c81718 2fc3c82` is empty for the four files involved.

## 1. Defects

The V6 sensing viewer is `battle_client/renderers/sensing_renderer.py`
(`SensingReplayRenderer`), driven by `battle_client/sensing_presentation.py`
(`SensingPresentation`). Its entrant ("Agent A — delivered information")
perspective draws through a filtered `SensingView`, as intended. Two parts of
the shared frame, however, are drawn from the active cursor's position list
whatever the perspective is.

| ID | Severity | Defect | Location (at `9c81718` and `2fc3c82`) | Evidence |
| --- | --- | --- | --- | --- |
| BF-1 | MEDIUM | **The recorded result is printed in the entrant perspective.** `draw()` prints `presentation.terminal_text` whenever it is not `None`. `terminal_text` is not `None` when `at_end` is true, and `at_end` compares the index with the *active* cursor's last position, which in the entrant perspective is Agent A's own last position. At that position Agent A's view shows "Recorded end: winner B; last_agent_standing", or "Recorded end reached." when there is no result. Agent A is never delivered that information. | `sensing_renderer.py:158-159` (`draw`); `sensing_presentation.py:134-140` (`at_end`, `terminal_text`); the text is built in `load_sensing_presentation` (`sensing_presentation.py:203-207`) | Spectator `docs/p0d/screenshots/v6/capture.json` (agent_a, tick 477); `docs/p0d/side_by_side/tick-0477.png` |
| BF-2 | MEDIUM | **The timeline reveals the length of Agent A's record.** The playhead is drawn at `index / (len(positions) - 1)` of the active cursor's positions. In the entrant perspective that fraction is "how far through Agent A's own record we are", so its position gives away when the record ends. Because Agent A's record ends when Agent A is eliminated or the match ends, the playhead discloses the match length. Example: at tick 320 the playhead is about two-thirds along, which implies an end near tick 480 (the actual end is 477). Mouse seeking maps the same fraction back onto those positions. | `sensing_renderer.py:151-154` (playhead); `sensing_renderer.py:107-114` (`seek_from_mouse`) | `docs/p0d/screenshots/v6/v6-agent_a-tick-0320.png` |
| BF-3 | LOW (inherent) | Navigation stops at the end of Agent A's record. End ("recorded end") jumps to it, `seek_relative` clamps to the nearest tick end that exists in the record, and playback stops there. A user who navigates past the end therefore learns where the record ends. | `sensing_presentation.py:146-154`; help line `sensing_renderer.py:157` | Same class as Spectator OF-3; see §4 |

BF-1 and BF-2 are the same class of defect as Spectator P0-B finding F2
(the match length shown through the Agent A label and timeline), which
Spectator fixed in its own viewer in `ba9d69b`.

## 2. Proposed correction (narrow)

The correction is client-only. It changes no engine code, no replay or trace
format, no ruleset and no verification.

1. **BF-1.** In `SensingReplayRenderer.draw`, print `terminal_text` only in
   the omniscient branch, that is, when `not isinstance(view, SensingView)`.
   The omniscient perspective keeps the line exactly as today.
2. **BF-2.** In the entrant perspective, place the playhead by tick against
   the match's **public tick limit**, `tick / tick_limit`, instead of by index
   against the record length. The tick limit is in the replay header
   (`reproducibility.tick_limit`, 1000 in the Spectator showcase).
   `load_sensing_presentation` already holds the `ReplaySession`, so it can
   pass the limit to `SensingPresentation`. `seek_from_mouse` maps the mouse
   to a tick in `[0, tick_limit]` and seeks with the existing
   tick-boundary logic, which still clamps to the record. The omniscient
   perspective keeps index-based placement, because the full match length is
   legitimately visible there.
3. **BF-3: no code change proposed.** Change the entrant-perspective help
   text from "End: recorded end" to "End: last delivered position", and
   record the clamping as an inherent property (see §4).

## 3. Tests to add (Bytefray client tests)

- For a decisive match, capture the renderer's `text()` calls at the entrant
  perspective's last position. They must not contain the `terminal_text`
  string, while the omniscient perspective at its last position still does.
  The capture pattern already exists in `client/tests/test_v6_alpha_m1_5.py`.
- In the entrant perspective, the playhead x-coordinate at a given tick must
  equal `x + round(tick / tick_limit * width)`. It must not depend on
  `len(positions)`. One way to test this is two matches with the same tick
  limit that end at different ticks: at the same early tick both playheads
  must be at the same position.
- `seek_from_mouse` at the far right in the entrant perspective lands on the
  record's last tick end, which is today's clamping behaviour, unchanged.
- The existing M1.5 tests (filtered `draw_entrant` signature, bounded draw)
  stay green.

## 4. On BF-3 and Spectator OF-3

Any viewer that shows Agent A's own record can only show positions that
exist in that record. When a user asks for a later tick, the viewer has two
options. It can clamp, which reveals where the record ends. Or it can pad
with positions the agent never had, which would fabricate perspective data.
Spectator P1 reached the same conclusion for its own Agent A view (see
`docs/P1_READABLE_BROADCAST_REVIEW_01.md`, §5). Neither viewer reveals the end
*passively*, through labels, timeline range, playhead, banner or panel text,
once BF-1 and BF-2 are fixed. Both reveal it on explicit navigation to or
past the end.

## 5. Effect on Spectator

- No change to Spectator's pin is needed or implied. The Spectator exporter
  imports only `battle_engine` and `battle_client` verification and projection
  code. It does not use the pygame renderer.
- If this correction lands, Spectator's recorded V6 baseline captures
  (`docs/p0d/`) would still show BF-1 and BF-2, because they were rendered at
  `9c81718`. Re-rendering them against a corrected Bytefray would need a new
  pin, and that is a separate authorization.
- Until then, every comparison with the V6 baseline must account for BF-1
  and BF-2 (see the P1 evaluation protocol, `docs/p1/evaluation/`).
