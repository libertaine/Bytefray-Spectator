# P1-6 independent viewer comparison — facilitator protocol

For: whoever runs the P1-6 sessions. Reviewers never see this file or
`ANSWER_KEY.md`. They get only `REVIEWER_SHEET.md`.

**Status: no session has been run.** The kit is ready and the sessions are
pending. Three viewers give formative feedback, not statistically conclusive
validation.

## 1. Viewers

- At least three people who took no part in developing Spectator or Bytefray
  V6, and who have not seen the P0-D or P1 reports, screenshots or
  recordings.
- Record each viewer's prior familiarity (none, has played other programming
  games, knows Bytefray) without identifying them. Use the codes V1, V2, V3,
  and so on.
- Developer scores and Project Lead scores are recorded separately and are
  never pooled with viewer results.

## 2. Setup (same machine, same fixture, same window size)

```powershell
$py = "D:\Projects\BATTLE2\.venv\Scripts\python.exe"
cd D:\Projects\Bytefray-Spectator
# Godot Spectator (P1)
./launch_showcase.ps1 -Perspective broadcast -Tick <t>          # paused at tick t
./launch_showcase.ps1 -Perspective agent_a -Tick <t>
# Bytefray V6 sensing viewer (baseline, pinned 9c81718; the checkout's client and engine packages are verified identical)
& $py -m battle_client.cli --replay fixtures/showcase/source/replay.jsonl --trace fixtures/showcase/source/trace.jsonl --renderer pygame --start-tick <t> --paused --perspective broadcast
& $py -m battle_client.cli --replay fixtures/showcase/source/replay.jsonl --trace fixtures/showcase/source/trace.jsonl --renderer pygame --start-tick <t> --paused --perspective A
```

Run the V6 commands with `D:\Projects\BATTLE2\client\src` and
`D:\Projects\BATTLE2\engine\src` on `PYTHONPATH` if `battle_client` is not
installed in that environment. Before each session, check that the
exporter's pin check passes (`exporter/spectator_export.py` refuses a
modified checkout), so the V6 viewer is the pinned one.

## 3. Counterbalancing

| Viewer | First viewer | Second viewer |
| --- | --- | --- |
| V1 | V6 baseline | Godot Spectator |
| V2 | Godot Spectator | V6 baseline |
| V3 | V6 baseline | Godot Spectator |
| V4 (if available) | Godot Spectator | V6 baseline |

Each viewer answers every question in both viewers. The question order is
the same in both viewers (Q1–Q8). Leave at least a 5-minute break, or one
unrelated task, between the two viewers.

## 4. Comparable viewing opportunities

Do not compare default speeds only. A full match takes 12.8 min at V6's
default 1x and 95 s at Godot's default.

1. **Orientation, same duration.** Before any question, each viewer watches
   the whole match once in each viewer's omniscient perspective at a
   comparable pace: **V6 at 8x (about 96 s)** and **Godot at 5 ticks/s
   (95 s)**. Give no explanation beyond "this is a recorded match between two
   programs".
2. **Questions, same freedom.** For each question, open the stated position
   paused. The viewer may then use any control of that viewer (step, play,
   seek within ±20 ticks of the stated tick) for up to **90 seconds**. Start
   the timer when the position is on screen. Stop it when the viewer commits
   to an answer.
3. **Legend and help.** Both viewers have on-screen help (V6 `?`, Godot `H`
   and the always-on legend). Do not point at them. Note whether the viewer
   used them.

## 5. Accounting for the V6 baseline's Agent A leaks

The V6 Agent A perspective has two known disclosures (BF-1 and BF-2, in
`docs/BYTEFRAY_V6_AGENT_VIEW_DISCLOSURE_CORRECTION_01.md`):

- **BF-1.** At Agent A's last position, the result ("Recorded end: winner B;
  last_agent_standing") is printed.
- **BF-2.** The timeline playhead shows how far through Agent A's record the
  position is, and so roughly when the match ends.

These must not count as better comprehension:

- **Q6** (Agent A, tick 477: "Does Agent A know it has lost?"). In V6 the
  result is on screen in the agent's own view. Record whether the viewer read
  or mentioned it. The correct answer is "no" in both viewers. A V6 "yes"
  that cites the printed result is scored **wrong** and tagged
  `leak-misled`.
- **Any Agent A question.** If a viewer uses the V6 playhead position to
  reason about the match end, or the V6 result line to answer anything other
  than Q6, tag the answer `leak-assisted`. Score it as given, and **exclude it
  from the V6-versus-Godot comprehension comparison**. Report both the raw
  and the excluded totals.
- **Godot's own limit (OF-3).** In Godot's Agent A, seeking past the record
  clamps to tick 477. If a viewer infers the match end that way, tag it
  `clamp-assisted` and treat it the same way.

## 6. What to record

Use `results_template.csv`, one row per viewer, viewer and question:

- the answer verbatim;
- correct, partly correct or wrong, judged against `ANSWER_KEY.md`;
- the time to answer, in seconds;
- the tag `leak-assisted`, `leak-misled`, `clamp-assisted` or none;
- confusing or misleading elements, in the viewer's own words.

After both viewers, record:

- the 1–5 scores of P0-D §6.1 for each of the 8 categories, in each viewer
  and perspective;
- engagement (1–5): "How much did you want to keep watching?";
- free comments.

## 7. Reporting

- Report per viewer and per question. Do not average across fewer than three
  viewers.
- Keep these columns separate: raw correct, correct excluding tagged answers,
  median time, and scores.
- State plainly that three viewers are formative evidence.
