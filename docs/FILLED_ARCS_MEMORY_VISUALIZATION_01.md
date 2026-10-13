# Filled Arc Memory Visualization — validation record (01)

Date: 2026-10-13. Spectator baseline: local `main` at `4e02040`.
Bytefray checkout: `v6-research` at `2fc3c82`; Spectator's pin remains `9c81718`.

## Behavior

The header selects **Classic** or **Filled Arcs** (default), with equivalent
`--rendering=classic|filled_arcs` and launcher `-Rendering` options. Changing
the mode redraws the arena without changing perspective, position, playback
progress or audio. The setting lasts across fixture loads in the session.

Filled Arcs uses cached, geometry-only annular polygons: one complete angular
interval `[address, address + 1]` per memory location. For the 512-cell showcase,
each wedge is a four-vertex polygon; both radial edges meet its neighbors,
including 511 and 0. Smaller arenas subdivide the curves. Angles remain
`-PI/2 + TAU * address / arena_size`, and markers remain at address centers.
The outer edge remains Classic's stroke edge (`radius + width/2`); the band
extends 40 pixels inward. Faint 3-pixel notches at the circumference distinguish
addresses without full-depth gaps between same-owner cells.

Unowned Broadcast cells are `#191a1f`. Owned cells use the existing competitor
palette and existing resting shade. A recorded ownership-changing WRITE
brightens the current recorded owner's color, with strengths 1, 0.5 and 0.25
over three tick ages, then returns to the resting shade. No previous owner is
blended in, no WRITE outcome is fabricated, and no animation history is kept.
The existing recorded WRITE effects and sound cues continue independently.

Core status cards and the original core band remain. Broadcast also has a
narrow inner core border. All existing process, movement, sensing, remote
WRITE and disruption coordinates remain identical. Sensing lanes and WRITE
lines receive contrast backing in Filled Arcs where they cross the band.

Agent A keeps an unknown memory ring and its existing core-location outline;
it has no ownership fills or ownership flashes. Its draw path branches before
accessing owners. Perspective changes clear Broadcast state, effects, entrants,
core gauges and banners. The sole retained cache contains geometry only.

## Validation

| Check | Result |
| --- | --- |
| `tests/memory_ring_check.gd` | PASS: 4,711 checks; every address/shared edge at sizes 8, 512 and 1024; independent raw ownership fold and WRITE-flash reference at every showcase frame; all requested ticks; core counts; arbitrary seeks; Agent A isolation; playback/caption/audio equivalence between modes |
| `tests/memory_ring_pixels.gd`, native renderer | PASS: 28,668 actual pixel checks; every cell at three depths inside the band and two radii outside it; all five recorded ticks in both perspectives; synthetic same-owner runs including 511 -> 0 |
| Existing `tests/smoke_test.gd` | PASS: 56 checks |
| Existing `tests/fixture_check.gd`, showcase / Filled Arcs | PASS: 47 checks, including all-frame effects, core display, playback order, seeking and switching |
| Spectator pytest suite | 50 passed; 2 inherited frozen-agent fixture failures (details below). Both modes pass the differential knowledge-isolation checks and existing sound checks. |
| `python -m ruff check .`, `git diff --check` | PASS |
| Showcase launcher, `-Rendering classic -Tick 461 -QuitAfter 3` | PASS |
| Classic comparison against pre-change captures | All 10 arena/side-panel regions (1280x600, y=37) are pixel-identical; only the header gains the rendering menu |
| Filled Arcs repeated capture | All 10 complete PNG files reproduce byte-for-byte |

The existing differential viewer traces now run in **both** rendering modes:
quiet, busy and split hidden opponent activity must produce identical Agent A
outputs, while a genuinely observed opponent move must change them. Existing
sound checks exercise synthesis, cues, WRITE/core sounds, seeking, muting,
throttling, announcer behavior and determinism. The native pixel test suppresses
overlays only in its test subclass, so it can sample memory pixels directly;
the captures below show the complete product view with every overlay enabled.

The working-tree suite has two inherited frozen-agent fixture failures:
`test_fixture_declaration_binds_sources_selection_and_frozen_agents` and
`test_match_reproduces_from_frozen_inputs`. At task start, these untracked
directories already existed inside Harrier's source tree:

- `agents/spectator_harrier/spectator_bastion/`
- `agents/spectator_harrier/spectator_harrier/`

They change its recursive source digest from the fixture's
`3c36e94f80e36eb59ff90c6ea8dfd127252b587cad2c414fec7a0957429050ae` to
`cd712b801c954575ad617053ad0d12b14900522309f6063828f6f17ae8511ba2`.
Both checks **pass** (2 passed) in an isolated `git archive HEAD` of the tracked
baseline under `D:/Projects/Bytefray-Spectator-work/filled-arcs-frozen-fixture-check-20261013/`.
The original directories, agents and frozen artifacts were preserved.
The working-tree rerun has the same 478 gameplay records and the same terminal
winner B, tick 477 and last-agent-standing reason. Only Harrier's
local_source_fingerprint / local_source_fingerprint_final and the derived
result_id differ in the header and terminal record; these explain the replay
digest mismatch without a gameplay difference.

The final working-tree suite used the fresh basetemp
`D:/Projects/Bytefray-Spectator-work/filled-arcs-pytest-20261013/`. An initial
attempt used a basetemp inside Bytefray and was refused by the exporter's
existing output-location guard; it is superseded by the outside-checkout run.
No Bytefray/E8/E9 research suite was run. Validation here is automated renderer,
playback and audio verification, not a new human readability or listening study.

## Comparable screenshots

All captures use the unchanged seed-427 showcase exports, paused at the
tick-end boundary, in a fixed 1280x800 SubViewport on Godot 4.7.2's OpenGL
Compatibility renderer (NVIDIA RTX 4070). They include core cards, process and
sensing markers, recorded WRITE/disruption effects, controls and captions.

| Tick | Classic Broadcast | Filled Arcs Broadcast | Classic Agent A | Filled Arcs Agent A |
| --- | --- | --- | --- | --- |
| 12 | [view](filled_arcs/classic/broadcast-tick-0012.png) | [view](filled_arcs/filled_arcs/broadcast-tick-0012.png) | [view](filled_arcs/classic/agent_a-tick-0012.png) | [view](filled_arcs/filled_arcs/agent_a-tick-0012.png) |
| 320 | [view](filled_arcs/classic/broadcast-tick-0320.png) | [view](filled_arcs/filled_arcs/broadcast-tick-0320.png) | [view](filled_arcs/classic/agent_a-tick-0320.png) | [view](filled_arcs/filled_arcs/agent_a-tick-0320.png) |
| 461 | [view](filled_arcs/classic/broadcast-tick-0461.png) | [view](filled_arcs/filled_arcs/broadcast-tick-0461.png) | [view](filled_arcs/classic/agent_a-tick-0461.png) | [view](filled_arcs/filled_arcs/agent_a-tick-0461.png) |
| 476 | [view](filled_arcs/classic/broadcast-tick-0476.png) | [view](filled_arcs/filled_arcs/broadcast-tick-0476.png) | [view](filled_arcs/classic/agent_a-tick-0476.png) | [view](filled_arcs/filled_arcs/agent_a-tick-0476.png) |
| 477 | [view](filled_arcs/classic/broadcast-tick-0477.png) | [view](filled_arcs/filled_arcs/broadcast-tick-0477.png) | [view](filled_arcs/classic/agent_a-tick-0477.png) | [view](filled_arcs/filled_arcs/agent_a-tick-0477.png) |

The PNG digests are in [SHA256SUMS](filled_arcs/SHA256SUMS). Reproduce with:

```powershell
$godot = "C:\Program Files\Godot\Godot_v4.7.2-stable_win64_console.exe"
& $godot --path . --script res://tests/capture_frames.gd -- --rendering=classic --out=<classic-dir> --ticks=12,320,461,476,477
& $godot --path . --script res://tests/capture_frames.gd -- --rendering=filled_arcs --out=<filled-dir> --ticks=12,320,461,476,477
& $godot --headless --path . --script res://tests/memory_ring_check.gd
& $godot --path . --script res://tests/memory_ring_pixels.gd
```

## Scope and retained boundaries

Only Spectator rendering, launch configuration, renderer tests and documentation
changed. Bytefray engine/client source, agents, gameplay, match outcomes, frozen
fixtures, exporter implementation, export schemas and the pin remain unchanged.
Existing sound/announcer code, playback models and recorded-effect derivation
remain unchanged. The engine working-tree status matches the task-start inventory.

The implementation and evidence are committed locally; no remote push or release.
E9 remains **LOCKED**. Requirement C remains **NOT ESTABLISHED**.
