# Bytefray Spectator

A presentation-only viewer for verified [Bytefray](https://github.com/libertaine/Bytefray)
V6 alpha1 matches, built with Godot 4 (GDScript).

The Spectator never simulates a match and never decides anything about one.
A read-only Python exporter uses Bytefray's own verification and projection
code, pinned to one Bytefray commit, to turn a recorded match into
presentation files. The Godot viewer refuses any file whose SHA-256 does not
match the manifest.

Status: **P0-B development vertical slice**. Local repository only.

## Layout

| Path | Contents |
| --- | --- |
| `bytefray.pin.json` | The Bytefray commit and packages the exporter must import |
| `exporter/spectator_export.py` | Read-only exporter: match artifacts → `broadcast.json`, `agent_a.json`, `manifest.json` |
| `exporter/make_dev_fixture.py` | Regenerates the development fixture from the pinned Bytefray |
| `exporter/tests/` | Exporter and fixture tests (pytest) |
| `fixtures/dev/` | `fixture.json` declaration, `source/` match artifacts, `presentation/` exported files |
| `project.godot`, `scenes/`, `scripts/` | Godot viewer |
| `tests/smoke_test.gd` | Headless playback smoke test |
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
  global decision index.

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

# Exporter tests (about 2.5 minutes; includes a full re-export)
& $py -m pytest

# Viewer: first-time import, headless smoke test, interactive run
& $godot --headless --path . --import
& $godot --headless --path . --script res://tests/smoke_test.gd
& $godot --path .                       # optional: -- --fixture=<dir>
```

## Viewer controls

| Key | Action |
| --- | --- |
| Space | Play/pause (ticks per second chosen in the speed menu) |
| Right / Left | Step one phase frame |
| Shift+Right / Shift+Left | Step one tick |
| Home | Restart |
| Tab | Switch Broadcast ↔ Agent A |

The timeline slider seeks by tick.

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
