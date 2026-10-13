"""Facts at the P1 review ticks, from the showcase presentation files (read-only).

Run from the repository root: python docs/p1/review_ticks.py > docs/p1/review_ticks.json
Every value comes from fixtures/showcase/presentation/broadcast.json. These are
the facts the P1 core cards, effects and captions must show at each tick.
"""

from __future__ import annotations

import json
from pathlib import Path

PRESENTATION = Path("fixtures/showcase/presentation")
TICKS = (12, 320, 447, 467, 476, 477)


def main() -> None:
    broadcast = json.loads((PRESENTATION / "broadcast.json").read_text(encoding="utf-8"))
    cores = {e["id"]: e["core"] for e in broadcast["entrants"]}
    owners = list(broadcast["frames"][0]["owners"])
    held: dict[int, dict[str, int]] = {}
    actions: dict[int, list[dict]] = {}
    disrupted: dict[int, list] = {}
    alive: dict[int, list] = {}
    decisive = None
    for i, frame in enumerate(broadcast["frames"]):
        before = owners[frame["address"]] if frame["p"] == 1 and frame["address"] is not None else None
        if i:
            for cell, owner in frame["owner_changes"]:
                owners[cell] = owner
        tick = frame["t"]
        if frame["p"] == 1 and frame["kind"] == "write" and frame["status"] == "APPLIED":
            for entrant, core in cores.items():
                if frame["address"] in core and before == entrant != frame["actor"]:
                    actions.setdefault(tick, []).append(
                        {
                            "frame": i,
                            "write": f"{frame['actor']}/{frame['process']} {frame['address']}",
                            "core_cell_lost_by": entrant,
                        }
                    )
                    if sum(owners[c] == entrant for c in core) == 0:
                        decisive = {
                            "frame": i,
                            "tick": tick,
                            "write": f"{frame['actor']}/{frame['process']} WRITE {frame['address']}",
                            "core_of": entrant,
                        }
                elif frame["address"] in core and frame["actor"] == entrant != before:
                    actions.setdefault(tick, []).append(
                        {
                            "frame": i,
                            "write": f"{frame['actor']}/{frame['process']} {frame['address']}",
                            "core_cell_regained_by": entrant,
                        }
                    )
        if frame["p"] == 2:
            held[tick] = {e: sum(owners[c] == e for c in core) for e, core in cores.items()}
            disrupted[tick] = frame["disrupted"]
            alive[tick] = frame["alive"]
    report = {
        tick: {
            "core_cells_held": held[tick],
            "change_since_previous_tick": {e: held[tick][e] - held[tick - 1][e] for e in cores},
            "alive": alive[tick],
            "core_changes_this_tick": actions.get(tick, []),
            "disrupted_at_tick_end": disrupted[tick],
        }
        for tick in TICKS
    }
    print(json.dumps({"review_ticks": report, "decisive_capture": decisive}, indent=2))


if __name__ == "__main__":
    main()
