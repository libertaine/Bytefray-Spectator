# Bytefray Spectator

A presentation-only viewer for verified [Bytefray](https://github.com/libertaine/Bytefray)
V6 alpha1 matches, built with Godot 4 (GDScript).

The Spectator never simulates a match and never decides anything about one.
A read-only Python exporter uses Bytefray's own verification and projection
code, pinned to one Bytefray commit, to turn a recorded match into
presentation files. The Godot viewer refuses any file whose SHA-256 does not
match the manifest.

Status: **P1** (readable broadcast: sensing, actions, core status and
controls). Local repository only.

## Watch the showcase

```powershell
./launch_showcase.ps1                                   # Broadcast, tick 0, paused, 5 ticks/s
./launch_showcase.ps1 -Perspective agent_a -Tick 440 -Speed 20 -Play
```

The viewer opens the verified showcase fixture (Harrier vs Bastion, seed 427)
and refuses it if any file differs from its manifest. Set `GODOT` or pass
`-Godot <path>` if Godot 4.7.2 is not at the default location.

## Layout

| Path | Contents |
| --- | --- |
| `bytefray.pin.json` | The Bytefray commit and packages the exporter must import |
| `exporter/spectator_export.py` | Read-only exporter: match artifacts → `broadcast.json`, `agent_a.json`, `manifest.json` |
| `exporter/make_dev_fixture.py` | Regenerates the development fixture from the pinned Bytefray |
| `exporter/run_match.py` | Runs one alpha1 match between two agent directories (seeded placement) and writes a `match.json` run record |
| `exporter/tests/` | Exporter, fixture and differential knowledge-isolation tests (pytest); `agents/` holds test-only opponents |
| `fixtures/dev/` | `fixture.json` declaration, `source/` match artifacts, `presentation/` exported files |
| `fixtures/showcase/` | The P0-C showcase match (Harrier vs Bastion, seed 427), with `selection/` evidence (`ranking.json`, `validation.json`, `examination.json`) |
| `agents/` | Two showcase agents, `spectator_harrier` and `spectator_bastion` (see `agents/README.md`) |
| `exporter/showcase_search.py` | Runs, measures, ranks and validates showcase candidates under `docs/P0_SHOWCASE_SELECTION_PROTOCOL.md` |
| `project.godot`, `scenes/`, `scripts/` | Godot viewer (`broadcast_effects.gd`: broadcast-only effects, core status and tick summaries derived from recorded frames; `legend_view.gd`: the legend) |
| `tests/smoke_test.gd` | Headless playback smoke test |
| `tests/agent_view_trace.gd` | Records everything the Agent A perspective shows (used by the differential tests) |
| `tests/fixture_check.gd` | Generic headless playback check for any fixture (`-- --fixture=<dir>`) |
| `tests/capture_frames.gd` | Renders screenshots of a fixture into a fixed 1280x800 viewport (needs a real renderer, not `--headless`) |
| `tests/record_frames.gd` | Records playback as PNG frames at a fixed frame rate into the same viewport, for encoding with ffmpeg |
| `launch_showcase.ps1` | Opens the viewer on the showcase fixture with a chosen perspective, tick, speed and play state |
| `exporter/capture_v6_viewer.py` | Renders Bytefray's own V6 sensing viewer at chosen ticks, or records it, for comparison (P0-D) |
| `docs/` | Phase records |

## Perspectives and information boundaries

- **Broadcast** (`broadcast.json`): this is the full world state. It has one
  frame per verified exchange fact, built from Bytefray's omniscient
  `SensingCursor`. Each frame holds:
  - cell ownership, stored as deltas
  - process anchors and disruption
  - which entrants are alive
  - the recorded action
- **Agent A** (`agent_a.json`): this holds only what Agent A was delivered,
  serialized exclusively from Bytefray's receipt-only `SensingView`:
  - its own core and processes
  - delivered sensing samples and reads
  - anonymous historical contacts
  - its own events

  The exporter fails closed if this file carries any key outside an
  allowlist. The viewer keeps the two perspectives in separate models.
  Switching perspective maps the position on tick boundaries only, never a
  global decision index. The Agent A perspective shows the public tick limit,
  never the match length.

The outcome shown (winner, termination, eliminations) is re-derived from the
verified final state and the replay's terminal record; a `result.json` that
disagrees is refused. A source directory carries exactly one provenance
record: Bytefray's teaching-demo `demo.json`, or a Spectator `match.json`
written by `run_match.py`.

## Requirements

- Godot 4.7.2 (`C:\Program Files\Godot\Godot_v4.7.2-stable_win64_console.exe` on the dev machine).
- A local Bytefray checkout. The packages listed in `bytefray.pin.json` must
  be byte-identical to the pinned commit, and the exporter verifies this with
  `git ls-tree` and `git hash-object`.
- That checkout's Python environment (Python 3.13). The exporter imports
  `battle_engine` and `battle_client` from the checkout and writes no
  bytecode into it.

## Commands

The examples use the dev machine's paths. Run them from the repository root.

```powershell
$py = "D:\Projects\BATTLE2\.venv\Scripts\python.exe"
$godot = "C:\Program Files\Godot\Godot_v4.7.2-stable_win64_console.exe"

# Regenerate the development fixture (declared seed 0) and export it
& $py exporter/make_dev_fixture.py --bytefray-root D:\Projects\BATTLE2
& $py exporter/spectator_export.py --bytefray-root D:\Projects\BATTLE2 --source fixtures/dev/source --out fixtures/dev/presentation

# Run a match between two agent directories (output outside the Bytefray checkout)
& $py exporter/run_match.py --bytefray-root D:\Projects\BATTLE2 --agent-a <dir> --agent-b <dir> --seed <n> --out <new dir>

# Exporter and isolation tests (about 4 minutes; includes a full re-export and the
# Godot differential traces). The OS-default pytest temp root is unreadable on the
# dev machine, so pass a disposable basetemp.
& $py -m pytest --basetemp=D:\Projects\Bytefray-Spectator-work\pytest

# Viewer: first-time import, headless smoke test, interactive run
& $godot --headless --path . --import
& $godot --headless --path . --script res://tests/smoke_test.gd
& $godot --headless --path . --script res://tests/fixture_check.gd -- --fixture=res://fixtures/showcase/presentation
& $godot --path .                       # opens the showcase; options below

# Launch options (after --): --fixture=showcase|dev|<dir>, --perspective=broadcast|agent_a,
# --tick=<n>, --speed=1|2|5|10|20|60|200 (ticks per second), --play
& $godot --path . -- --fixture=dev --perspective=agent_a --tick=100

# Same-match baseline: Bytefray's V6 sensing viewer, offscreen (screenshots or an H.264 recording)
& $py exporter/capture_v6_viewer.py --bytefray-root D:\Projects\BATTLE2 --source fixtures/showcase/source --out <dir> --ticks 1,320,477
& $py exporter/capture_v6_viewer.py --bytefray-root D:\Projects\BATTLE2 --source fixtures/showcase/source --out <file.mp4> --record omniscient --start 440 --speed 8
```

## Viewer controls

| Key | Action |
| --- | --- |
| Space | Play/pause (ticks per second chosen in the speed menu) |
| Right / Left | Step one recorded frame |
| Shift+Right / Shift+Left | Step one tick |
| Home / End | Restart / jump to the last tick |
| G | Jump to a tick (type it in the Tick box, then Enter) |
| Tab | Switch Broadcast ↔ Agent A |
| - / + | Slower / faster (1, 2, 5, 10, 20, 60 or 200 ticks/s) |
| L | Show or hide the legend |
| H, F1 or ? | Show or hide the keyboard help |

The timeline slider seeks by tick. A key hint line is always shown.

Playback gives every recorded frame of a tick an equal, in-order share of that
tick's time. At 1 tick/s each action of a tick appears in turn; at faster
speeds a display frame can span several recorded frames, and the 3-tick
effects carry the actions.
While playing, the broadcast caption holds the summary of the last completed
tick; paused or stepping, it describes the current recorded fact and its
recorded outcome.

**Broadcast effects** are a pure function of the current frame. They show the
recorded actions of the last 3 ticks up to that frame, fading with age, and
never a later one:

- SENSE samples are drawn in a lane of the actor's colour, dashed until the
  recorded delivery and solid once delivered.
- WRITE targets are drawn filled when the write took the cell, and as a ring
  when the owner was unchanged. Core cells lost or regained are circled.
- MOVE arrows run from the old anchor to the new one.
- A burst marks a process hit by an opponent WRITE.

Seeking, restarting or switching perspective therefore redraws the effects
from the record, and nothing stale can remain. Core cards show each entrant's
core cells held, the change since the last tick boundary, and a CRITICAL
(2 or fewer) or ELIMINATED level. The decisive capture is marked on the WRITE
that took the last core cell from the recorded elimination (the tick end where
the banner appears) on, and stays drawn alongside the result banner. Before
that frame the WRITE is shown as a core cell lost and the gauge reads 0/8,
because the record has not yet said the entrant is eliminated.

In Broadcast, an eliminated entrant's process markers are dimmed and crossed
out, the tick-end caption names the entrant eliminated in that tick, and the
verified result appears as a banner only at the recorded end. The Agent A
perspective shows none of this, because Agent A is never delivered its
elimination or the result. Its own MOVE and WRITE indicators, and its pending
SENSE requests, come from `agent_a.json` alone. Its WRITE targets are drawn
as outlines, because the outcome of a write is never delivered to it.

In Agent A, End, the tick box and the slider all clamp to the last tick of
Agent A's own record, and playback stops there. Navigating to or past the end
therefore shows where Agent A's record ends. Nothing reveals it passively. See
`docs/P1_READABLE_BROADCAST_REVIEW_01.md` §5.

## Showcase fixture

`fixtures/showcase` is the match the frozen selection protocol
(`spectator-p0c-showcase-selection-v1`) ranked first among 1,000 public
candidates. In it, `spectator_harrier` (seat A) plays `spectator_bastion`
(seat B) at seed 427 under alpha1, arena 512. Bastion captures Harrier's
core at tick 477. This is product demonstration material, not evidence about
the agents. The selection, its digests and its reproduction are recorded in
`docs/P0C_SHOWCASE_SELECTION_01.md`.

## Development fixture

The fixture is Bytefray's M1-2 Window Scout teaching demonstration, run as
follows:

- arena 512, action budget 8, 1000 ticks;
- Window Scout at cell 0 against a stationary opponent at cell 91;
- the fixed seed **0**, which is the demonstration's published default. It
  was declared before any run and was not searched or selected.

The match verifies and ends in a **tie at the tick limit**. It is a
non-decisive match, used as a development fixture only, and is not showcase
material.

The replay is byte-reproducible. The trace differs between runs only in
`wall_time_ms`, and the exported presentation files are byte-reproducible.
