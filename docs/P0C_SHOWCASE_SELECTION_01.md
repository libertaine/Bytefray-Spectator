# P0-C showcase selection record (01)

> Spectator commit IDs in this publication copy identify equivalent stages in the sanitized public history. Original dates and test outcomes remain historical; frozen declarations and checksum-bound evidence are unchanged.

Protocol: **`spectator-p0c-showcase-selection-v1`**
(`docs/P0_SHOWCASE_SELECTION_PROTOCOL.md`, SHA-256 `e3ceccf4…ce08`, frozen in
commit `4eceb88`). Agents frozen in commit `1229630`. Executed 2026-10-12,
locally. This is product demonstration, not evidence about agent performance.

## 1. Execution

| Step | Result |
| --- | --- |
| Pre-run integrity | HEAD `4eceb88`; clean tree; SHA-256 of both agents' files, every exporter script, the pin and the protocol recorded |
| Run | 1,000 candidates (P1 and P2 × seeds 1–500), 6 worker processes, **1,000 ran, 0 failed**, about 65 s. Outputs in `D:\Projects\Bytefray-Spectator-work\p0c-search-v1\` |
| Post-run integrity | HEAD and every recorded digest unchanged; Bytefray `engine/src` and `client/src` clean. All 1,000 `match.json` records bind the frozen agent trees, runner `9823d351…`, pin `9c81718` and seeded placement. |
| Rank | `ranking.json` SHA-256 `885161da…213d`; search script `f7147c8c…41f8` |
| Validate (H7) | Rank 1 passed at the first attempt: verified, two exports byte-identical (`validation.json` `5b6cf55e…db7`) |
| Examine | Ranks 1–3 (all pass H7) examined in the viewer (`examination.json` `0e2d9e0e…9e80`); **no disqualification** |

Outcomes across all candidates (the agents are not evenly matched):

| Pairing | Harrier wins | Bastion wins | `all_agents_dead` | `tick_limit` tie | Median length |
| --- | --- | --- | --- | --- | --- |
| P1 (A Harrier, B Bastion) | 451 | 26 | 11 | 12 | 75 ticks |
| P2 (A Bastion, B Harrier) | 447 | 31 | 10 | 12 | 78–79 ticks |

Filter failures (a candidate can fail several): H3 length 923, H2 decisive
finish 45, H4 both sides attack 11. **77 candidates qualified** (P1 45, P2
32). Of these, Harrier won 73 and Bastion 4.

Top ten:

| Rank | Pairing | Seed | Ticks | Winner (seat) | Total | Contest |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | P1 | 427 | 477 | B (Bastion) | 81.74 | 0.891 |
| 2 | P2 | 294 | 404 | B (Harrier) | 79.07 | 0.854 |
| 3 | P1 | 421 | 526 | A (Harrier) | 77.70 | 0.920 |
| 4 | P1 | 3 | 575 | A (Harrier) | 77.07 | 0.908 |
| 5 | P2 | 230 | 575 | B (Harrier) | 76.52 | 0.901 |
| 6 | P1 | 125 | 419 | A (Harrier) | 76.35 | 0.869 |
| 7 | P2 | 108 | 591 | B (Harrier) | 75.37 | 0.844 |
| 8 | P2 | 140 | 603 | B (Harrier) | 75.33 | 0.896 |
| 9 | P2 | 6 | 418 | B (Harrier) | 75.22 | 0.902 |
| 10 | P2 | 322 | 719 | B (Harrier) | 74.57 | 0.894 |

## 2. Examination (protocol §7.2)

| Rank | Candidate | H7 manifest | Godot `fixture_check` | Agent A trace (`agent_view_trace`) |
| --- | --- | --- | --- | --- |
| 1 | P1 / 427 | `526b26cf…546c`, repeat identical | PASS, 21 checks | 11,358 observations: every label shows only "(limit 1000)"; none shows the result or an elimination |
| 2 | P2 / 294 | `ad9c066b…dd13`, repeat identical | PASS, 21 checks | 10,149: same |
| 3 | P1 / 421 | `02e58c58…d85d`, repeat identical | PASS, 21 checks | 12,412: same |

Screenshots of the rank-1 match were rendered with a real renderer
(`tests/capture_frames.gd`) at ticks 1, 40, 240, 476 and 477 in both
perspectives and inspected. Four are kept in `docs/screenshots/p0c_showcase/`.
There is no objective defect. One presentation NOTE (not a defect): an
eliminated entrant's process markers are drawn at full color, while its core
arcs are dimmed.

## 3. Selected fixture

**P1, seed 427**: `spectator_harrier` (seat A, start 246) against
`spectator_bastion` (seat B, start 168). Bastion captures Harrier's core
and wins by `last_agent_standing` at **tick 477** of 1000, with 2 of its own 8
core cells left.

| Metric | Harrier (A) | Bastion (B) |
| --- | --- | --- |
| Ticks ending with the other side's core under pressure | 425 | 425 |
| Applied writes on the other's core | 995 | 930 |
| SENSE results with contacts | 239 | 334 |
| Disruptions caused | 170 | 236 |

There are 85 lead swings (sign changes in the core-ownership margin). Score
81.74: contest 0.891, swings 0.891, sensing 0.716, disruption 0.720, length
0.708, close finish 0.857.

**Rationale:** it is the protocol's rank-1 candidate. It passed H7 at the
first attempt and the examination found no defect. Its strengths are a long,
even contest (both cores under pressure for 89% of ticks), frequent swings,
sensing and disruption from both sides, and a narrow finish. Agent code was
not changed in response to any seed.

**Representativeness.** This is an upset: Bastion wins only 4 of the 77
qualifying matches (and about 6% of all matches). The fixture shows that a
decisive late capture is possible, not what usually happens. In the Agent A
perspective the viewer follows Harrier, the side that loses.

## 4. Provenance and digests

`fixtures/showcase/`:

| File | SHA-256 |
| --- | --- |
| `source/replay.jsonl` | `cd4a9ed6654faf46efec323cddb0ddf627e07e238bca09db14e6a863abf1cd28` |
| `source/trace.jsonl` | `7180592eeb5787331bf07317eb7e4de878c86092bd5c73189a480598b8f02311` |
| `source/result.json` | `f757bf9d0464b502d61dc94910a07198a83decebe5a1fb6ccb7217735327cc38` |
| `source/match.json` | `c227bcc10ab944811f028c75591bea48deb3062bd39c768f7e2abf4ec815e745` |
| `presentation/manifest.json` | `526b26cf2b451ac0ebd0ad0fb68b247eb2a3ec50e1292db22d97326e247e546c` |
| `presentation/broadcast.json` (15,310 frames) | `99045a052f2ee8e6f5feaafb9b6cd6374ef20b0f5252184d72a0f70fb78d72fe` |
| `presentation/agent_a.json` (7,754 frames) | `111b83a3b6038a693fe1981a374af56014bf1f0ef3c090fb6e0da2b4e27ee5af` |
| `selection/ranking.json` | `885161da4803bd711efc689e16d69f517328a173de5fed45d1ffaf67e7a6213d` |
| `selection/validation.json` | `5b6cf55eb95e35f1682b39400556074b937045880f1f48e43018e615df10adb7` |
| `selection/examination.json` | `0e2d9e0e4404744f22eda2bc7717a0eb236e4d0a540cf8092944e04249959e80` |
| `fixture.json` (declaration) | `afc1572425776330645fbd61cbbfff01ba2dbd656d3c7831bd0b333db1e96885` |

The source artifacts are byte copies of the search run's candidate
directory. The committed presentation equals the validated export byte for
byte.

**Reproduction.** Re-running the match from the frozen inputs:

```powershell
& $py exporter/run_match.py --bytefray-root D:\Projects\BATTLE2 --agent-a agents/spectator_harrier --agent-b agents/spectator_bastion --seed 427 --out <new dir>
& $py exporter/spectator_export.py --bytefray-root D:\Projects\BATTLE2 --source <new dir> --out <export dir>
```

This produced a byte-identical `replay.jsonl`. The trace was identical
without `wall_time_ms` (`3e227e62…cd72`), and `result.json` differed only in
`completed_at` and `occurrence_id`. `exporter/tests/test_showcase_fixture.py`
re-checks all of this: digests, frozen agent trees, rank-1 metrics recomputed
from the artifacts, a byte-identical re-export, re-run reproduction and Godot
playback.

**Seed governance.** Seed 427 is a public showcase seed, used under the
protocol's narrow exception (§9). It is not a research seed. No Bytefray
research directory or protected evidence path was read or written. E9
remains LOCKED, and Requirement C remains NOT ESTABLISHED.
