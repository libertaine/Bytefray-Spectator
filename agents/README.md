# Spectator showcase agents

Two V6-native Agent API v2 agents written for Bytefray-Spectator showcase
matches under `bytefray-rules-6-alpha1`. They are **not** official Bytefray
starter agents and are not installed into Bytefray. They live only here and
are run by `exporter/run_match.py` from a private snapshot of their directory.

| Agent | Processes (reach, share) | Character |
| --- | --- | --- |
| `spectator_harrier` | `hunter` (96, 0.5), `keeper` (16, 0.5) | Hunter-raider. Sweeps SENSE windows and patrols. Remembers contacts. READs around a contact for a run of eight opponent-owned cells (a core) and overwrites it. Disrupts guards it senses there. The keeper rewrites its own core in shuffled rounds and hops at random between four spots beside it. |
| `spectator_bastion` | `warden` (56, 0.5), `raider` (112, 0.5) | Warden and raider. The warden rewrites its own core, watches it with SENSE windows, disrupts fresh intruders and hops after every hit. The raider claims territory as it explores, scans ahead and behind, and raids a core it identifies by ownership. |

## What they may know and do

- Only `ObservationV2` and `MatchContextV2`: their own anchors, reach and
  core, and the delayed results of their own READ and SENSE actions.
  `visible_enemy_anchor_addresses` is always empty under alpha1, and neither
  agent reads it.
- They use no seed, no opponent placement, no replay knowledge and no
  hardcoded addresses. The only numbers in the source are offsets, counts
  and byte values (`exporter/tests/test_showcase_agents.py` checks this
  statically). The context RNG chooses only patrol and heading directions,
  repair order and parking spots.
- Every action is legal. Across 118,102 decisions in the final development
  run, every one was `APPLIED`: no out-of-reach refusals, no diagnostics, and
  every elimination was a `core_captured`.

## How they were developed

The behavior was developed and tuned **only on development seeds 900001–900024**
(both seat orders). That range is disjoint from the public candidate range
declared in `docs/P0_SHOWCASE_SELECTION_PROTOCOL.md`. No candidate seed was
run before the source digests were frozen. The iterations, in order:

1. First versions recognized cores by the beacon byte `0xCE`. Matches lasted
   5–35 ticks.
2. Stronger defense (larger keeper share, warden repairs). Most matches then
   reached the tick limit, because each defender rewrites its core with its
   own byte, which erases the beacon, so neither raider could find a core.
3. Cores are recognized by ownership: eight consecutive cells the opponent
   owns, never the agent's own core. A raid is abandoned if the opponent
   never takes target cells back. Matches lasted 14–178 ticks.
4. Equal attack/defense shares for Harrier, then random parking spots for
   both defenders, so that disrupting writes aimed at stale contacts tend to
   miss. Final development results (48 matches): median about 55 ticks,
   2 matches in 300–800, Harrier won 41, Bastion 4, and 3 were ties.

These are product demonstration agents. Nothing about their relative
strength is a research result.

## Gameplay findings (for the Bytefray lead, not changed here)

- **Reach is free in alpha1.** Any reach up to arena size − 1 is legal at no
  cost, so a full-reach agent could sense and write anywhere and could decide
  most matches within a few ticks. Both agents deliberately use bounded reach
  (≤ 112), in the spirit of the official Window Scout starter (reach 128).
- **Camouflage hides cores.** The beacon byte disappears as soon as a
  defender rewrites its core with any other byte. Ownership, which a READ
  reveals, then becomes the only way to locate a core.
