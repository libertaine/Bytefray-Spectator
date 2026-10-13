"""Derive the P0-D comparison ticks from the showcase presentation files (read-only).

Run from the repository root: python docs/p0d/moments.py > docs/p0d/moments.json
Every value comes from fixtures/showcase/presentation (broadcast.json and
agent_a.json); nothing is chosen by hand.
"""

from __future__ import annotations

import json
from pathlib import Path

PRESENTATION = Path("fixtures/showcase/presentation")


def main() -> None:
    broadcast = json.loads((PRESENTATION / "broadcast.json").read_text(encoding="utf-8"))
    agent = json.loads((PRESENTATION / "agent_a.json").read_text(encoding="utf-8"))
    cores = {entrant["id"]: entrant["core"] for entrant in broadcast["entrants"]}
    owners = list(broadcast["frames"][0]["owners"])
    first: dict[str, int] = {}
    held: dict[int, dict[str, int]] = {}
    territory: dict[int, int] = {}
    for i, frame in enumerate(broadcast["frames"]):
        if i:
            for cell, owner in frame["owner_changes"]:
                owners[cell] = owner
        tick = frame["t"]
        if frame["p"] == 1 and frame["status"] == "APPLIED":
            if frame["kind"] == "move":
                first.setdefault(f"first MOVE by {frame['actor']}/{frame['process']}", tick)
            if frame["kind"] == "write":
                for entrant, core in cores.items():
                    if entrant != frame["actor"] and frame["address"] in core:
                        first.setdefault(f"first {frame['actor']} write on {entrant}'s core", tick)
        for entrant, process in frame["disrupted"]:
            first.setdefault(f"first disruption of {entrant}/{process}", tick)
        if frame["p"] == 2:
            held[tick] = {entrant: sum(owners[c] == entrant for c in core) for entrant, core in cores.items()}
            territory[tick] = sum(owner is not None for owner in owners)
    for frame in agent["frames"]:
        for contact in frame["contacts"]:
            first.setdefault("Agent A: first remembered contact", frame["t"])
            if contact["stale_since"] is not None:
                first.setdefault("Agent A: first stale contact", frame["t"])
    lowest = {
        entrant: min(held, key=lambda t, e=entrant: (held[t][e] if broadcast["frames"][-1]["t"] != t else 9, t))
        for entrant in cores
    }
    report = {
        "first_events": dict(sorted(first.items(), key=lambda item: (item[1], item[0]))),
        "lowest_core_before_the_end": {e: {"tick": t, "cells_held": held[t][e]} for e, t in lowest.items()},
        "core_cells_held_at": {t: held[t] for t in (1, 9, 12, 320, 461, 476, 477)},
        "owned_cells_min_max": [min(territory.values()), max(territory.values())],
        "arena_size": broadcast["arena_size"],
    }
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
