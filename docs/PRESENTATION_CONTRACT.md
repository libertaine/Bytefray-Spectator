# Presentation contract: what Spectator accepts

Spectator plays **presentations**: a folder containing `manifest.json`,
`broadcast.json` and `agent_a.json`. It never reads raw Bytefray replays,
runs agents or simulates matches. Every presentation is verified before
anything is shown, however it was opened:

* the bundled showcase;
* `--fixture=` on the command line;
* **File > Open Presentation** (Ctrl+O);
* a folder (or its `manifest.json`) dropped on the window;
* a launch from Bytefray Designer.

## Who writes presentations

| Manifest version | Writer | Provenance | Used for |
|---|---|---|---|
| 1 | `exporter/spectator_export.py` in this repository, bound to the pinned Bytefray commit in `bytefray.pin.json` | `showcase_match` (with a `match.json` run record) or `teaching_demo` (with Bytefray's `demo.json`) | The frozen `showcase` and `dev` fixtures. Unchanged. |
| 2 | Bytefray's production exporter, `bytefray spectator export` (`battle_client.spectator_export`) | `bytefray_match`: an ordinary completed match whose canonical `result.json`, replay and trace are verified by Bytefray itself | Designer launches, `bytefray spectator export`, `fixtures/production_sample` |

Both versions describe the same `broadcast.json` and `agent_a.json`
documents (document `schema_version` 1). From identical source artifacts, the
production exporter reproduces the frozen showcase documents byte for byte,
and `exporter/tests/test_production_presentations.py` checks that.

The verification behind version 2 is specified in Bytefray's
[`docs/specs/spectator_export.md`](https://github.com/libertaine/Bytefray/blob/v6-research/docs/specs/spectator_export.md).
That spec is on the `v6-spectator-integration` development branch and may not
yet be published at that link.

## What the loader checks (`scripts/fixture_loader.gd`)

**Every version:**

* `schema` is `bytefray.spectator.manifest` and `schema_version` is exactly
  `1` or `2`. Any other value, including a fractional one, is "unsupported".
* `verification` records `artifact_pair_consistent`,
  `exchange_reconstructed`, `outcome_verified` and
  `agent_view_allowlist_checked` as `true`.
* `match.tick_limit` is a positive integer.
* Each listed file is a plain name (no `/`, `\` or `..`).
* Each file's size and SHA-256 equal the manifest, checked on the exact bytes
  that are then parsed.
* Each document's `schema` and `schema_version` are correct, and its frame
  count equals the manifest.

**Version 1:** provenance is `showcase_match` or `teaching_demo`. A teaching
demo also needs `teaching_complete`. `bytefray.commit` is the pinned commit.

**Version 2:**

* provenance is `bytefray_match`;
* `result_replay_preflight` and `sources_unchanged` are `true`;
* `exporter.name` is `battle_client.spectator_export`;
* `bytefray.version` names the exporting Bytefray;
* each file entry's `schema_version` is `1`.

A rejected presentation shows nothing. The title reads "Fixture rejected",
the reason is shown, the controls are disabled, and nothing from that folder
is kept. The window title says the presentation was rejected.
`tests/presentation_check.gd` covers each rejection rule.

The digests detect corruption and inconsistency between files. They do not
authenticate a presentation against someone who replaces the files and the
manifest together.

## Agent A knowledge isolation

`agent_a.json` holds only what Agent A was delivered. It is built upstream
from Bytefray's receipt-only `SensingView`, and every key is on an
allowlist. The viewer keeps the two perspectives in separate models, and
switching perspective maps tick boundaries only. Agent A never shows the
outcome, the match length or a winner cue.

## Launch options

The viewer's options go after Godot's `--` separator. Exported builds behave
the same way:

| Option | Meaning |
|---|---|
| `--fixture=showcase\|dev\|sample\|<folder>` | Presentation to open (default `showcase`). A folder may contain `=` or spaces. |
| `--perspective=broadcast\|agent_a` | Starting perspective |
| `--tick=<n>` | Starting tick |
| `--speed=1\|2\|5\|10\|20\|60\|200` | Playback speed in ticks per second |
| `--rendering=filled_arcs\|classic` | Memory style |
| `--play` | Start playing |
| `--check` | Print whether the presentation and the packaged cue bank verify, then exit: 0 if both verify, 1 if the presentation is rejected, 2 if the cue bank fails |

Bytefray Designer launches
`bytefray-spectator -- --fixture=<presentation> --perspective=broadcast`.
Spectator does not know or care that Designer started it.
