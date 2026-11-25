# Changelog

This changelog records notable user- and developer-visible changes to Bytefray Spectator.

## [Unreleased]

### Added

- **Tactical feedback for Active Sensing playback (R1-A):**
  - Factual `READ` discovery classification in Broadcast (`enemy_core`, `enemy_cell`, `own_core_damaged`) with per-entrant `(address, owner)` deduplication so routine and repeat reads stay visually and audibly quiet, and strictly receipt-only `READ` discovery classification in Agent A (`enemy_owned`, `own_core_damaged`, `own_core_recovered`) from `agent_a.json` alone.
  - Positive `SENSE` delivery classification distinguishing `first_contact`, `confirm` (unchanged stationary anchor), and `reacquire` (new or relocated anchor), with an outer gold target ring on reacquired contacts.
  - Visual cues on the arena ring and legend for `READ` discoveries (diamond markers with dashed inspection spokes), double concentric rings on core recoveries, and emphasized initial `core_base` deployment arcs.
  - Deterministic procedural audio cues for `read_discovery`, `reacquire`, and `core_recovery` (26 cached voice variants total), rebalanced priority hierarchy, lowered routine texture amplitudes, and a `TACTICAL_RESERVE` token budget so routine writes/senses/moves never starve tactical turning-point cues.
  - Live caption turning-point headlines during playback, `READ` and deployment outcome wording, `read_discoveries` counts in tick summaries, and `Tactical turning points:` / `Tactical turning points (delivered):` side-panel histories.
  - Headless R1-A regression suite (`tests/tactical_feedback_check.gd`) covering event classification, audio priority, Agent A launch-speed isolation, real-key `Tab` focus behavior, and seek/step determinism.

### Changed

- Short matches (60 ticks or fewer) now default to `2 ticks/s` in Broadcast while longer matches remain at `5 ticks/s`. Direct `--perspective=agent_a` launches without `--speed=` judge only by the public `tick_limit` so the default speed never reveals hidden match length.

### Fixed

- `Tab` now switches reliably between Broadcast and Agent A on every key press without parking focus in playback buttons or the jump-to-tick field (`_jump` uses `FOCUS_CLICK`; playback controls use `FOCUS_NONE`; `G` and clicks still focus the jump field and `Escape`/`Tab` release it).

### Compatibility

- Presentation-only enhancement: simulation behavior, replay semantics, manifest schemas (v1 and v2), `broadcast.json` / `agent_a.json` schemas, and Bytefray production exporter outputs remain unchanged.
