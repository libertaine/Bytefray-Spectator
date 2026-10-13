"""P0-C showcase seed search: run, measure, rank and validate candidate matches.

Implements docs/P0_SHOWCASE_SELECTION_PROTOCOL.md (protocol
``spectator-p0c-showcase-selection-v1``). Every metric is a pure function of a
candidate's authoritative artifacts (replay.jsonl, trace.jsonl, result.json).

Usage::

    python exporter/showcase_search.py run      --bytefray-root D:/Projects/BATTLE2 --work <dir> [--workers N]
    python exporter/showcase_search.py rank     --work <dir>
    python exporter/showcase_search.py validate --bytefray-root D:/Projects/BATTLE2 --work <dir>
"""

from __future__ import annotations

import sys

sys.dont_write_bytecode = True

import argparse  # noqa: E402
import json  # noqa: E402
from concurrent.futures import ProcessPoolExecutor  # noqa: E402
from pathlib import Path  # noqa: E402
from typing import Any  # noqa: E402

sys.path.insert(0, str(Path(__file__).resolve().parent))
from run_match import run_match  # noqa: E402
from spectator_export import SPECTATOR_ROOT, canonical_json, export, sha256_file  # noqa: E402

PROTOCOL_ID = "spectator-p0c-showcase-selection-v1"
SEEDS = range(1, 501)  # public candidate seeds, every one run for each pairing
PAIRINGS = {
    "P1": ("spectator_harrier", "spectator_bastion"),  # seat A, seat B
    "P2": ("spectator_bastion", "spectator_harrier"),
}
AGENTS_DIR = SPECTATOR_ROOT / "agents"
TICK_LIMIT = 1000
LENGTH_RANGE = (300, 800)
LENGTH_IDEAL = 550
CORE = 8
MIN_A_POSITIVE_SENSES = 3
WEIGHTS = {"contest": 30, "swings": 20, "sensing": 15, "disruption": 15, "length": 10, "close_finish": 10}


def candidate_dir(work: Path, pairing: str, seed: int) -> Path:
    return work / pairing / f"seed-{seed:04d}"


# ---------------------------------------------------------------------------
# Running
# ---------------------------------------------------------------------------


def _run_one(job: tuple[str, str, int, str]) -> tuple[str, int, str]:
    root, work, seed, pairing = job
    out = candidate_dir(Path(work), pairing, seed)
    if (out / "match.json").is_file():
        return pairing, seed, "existing"
    a, b = PAIRINGS[pairing]
    try:
        run_match(Path(root), AGENTS_DIR / a, AGENTS_DIR / b, seed, out, ticks=TICK_LIMIT)
    except Exception as exc:  # recorded, never retried silently
        (out.parent / f"seed-{seed:04d}.error.txt").write_text(f"{type(exc).__name__}: {exc}\n", encoding="utf-8")
        return pairing, seed, "error"
    return pairing, seed, "ran"


def run_all(bytefray_root: Path, work: Path, workers: int) -> dict[str, int]:
    for pairing in PAIRINGS:
        (work / pairing).mkdir(parents=True, exist_ok=True)
    jobs = [(str(bytefray_root), str(work), seed, pairing) for pairing in PAIRINGS for seed in SEEDS]
    counts: dict[str, int] = {}
    with ProcessPoolExecutor(max_workers=workers) as pool:
        for _, _, status in pool.map(_run_one, jobs, chunksize=4):
            counts[status] = counts.get(status, 0) + 1
    return counts


# ---------------------------------------------------------------------------
# Measuring (pure functions of the artifacts)
# ---------------------------------------------------------------------------


def candidate_metrics(src: Path) -> dict[str, Any]:
    result = json.loads((src / "result.json").read_text(encoding="utf-8"))
    run = json.loads((src / "match.json").read_text(encoding="utf-8"))
    owners: list[str | None] = []
    cores: dict[str, list[int]] = {}
    own_cells: list[dict[str, int]] = []  # per tick end: entrant -> own core cells it owns
    disrupted_prev: set[tuple[str, str]] = set()
    onsets = {"A": 0, "B": 0}  # disruption onsets *caused* by each entrant (on the other's processes)
    with (src / "replay.jsonl").open(encoding="utf-8") as handle:
        for line in handle:
            record = json.loads(line)
            if record.get("record_type") != "tick":
                continue
            if record["tick"] == 0:
                size = run["config"]["arena_size"]
                owners = [None] * size
                cores = {a["id"]: [(a["region"][0] + i) % size for i in range(CORE)] for a in record["agents"]}
            for diff in record["memory_diffs"]:
                for offset in range(diff["length"]):
                    owners[(diff["address"] + offset) % len(owners)] = diff["owner"]
            own_cells.append({e: sum(owners[c] == e for c in cells) for e, cells in cores.items()})
            disrupted = {(p["entrant_id"], p["process_id"]) for p in record["processes"] if p["disrupted"]}
            for victim, _ in disrupted - disrupted_prev:
                onsets["B" if victim == "A" else "A"] += 1
            disrupted_prev = disrupted
    kinds: dict[str, dict[str, int]] = {"A": {}, "B": {}}
    positive = {"A": 0, "B": 0}
    core_writes = {"A": 0, "B": 0}
    not_applied = 0
    with (src / "trace.jsonl").open(encoding="utf-8") as handle:
        for line in handle:
            record = json.loads(line)
            if record.get("record_type") != "decision_v2":
                continue
            agent, action = record["agent_id"], record["action"] or {}
            applied = record["applied_result"] or {}
            kinds[agent][action.get("kind")] = kinds[agent].get(action.get("kind"), 0) + 1
            if applied.get("status") != "APPLIED":
                not_applied += 1
                continue
            if action.get("kind") == "sense" and applied.get("sensed_anchors"):
                positive[agent] += 1
            enemy = "B" if agent == "A" else "A"
            if action.get("kind") == "write" and applied.get("normalized_address") in cores[enemy]:
                core_writes[agent] += 1
    ticks = result["ticks"]
    # Pressure: ticks ending with at least one of the defender's core cells lost.
    pressure = {e: sum(1 for cells in own_cells[1:] if cells[other] < CORE) for e, other in (("A", "B"), ("B", "A"))}
    margins = [cells["A"] - cells["B"] for cells in own_cells[1:]]
    signs = [m > 0 for m in margins if m != 0]
    swings = sum(1 for x, y in zip(signs, signs[1:], strict=False) if x != y)
    winner = result["winner"]
    return {
        "seed": run["seed"],
        "agents": [e["name"] for e in run["entrants"]],
        "ticks": ticks,
        "termination_reason": result["termination_reason"],
        "winner": winner,
        "entrant_termination": {e["agent_id"]: e["termination_reason"] for e in result["entrants"]},
        "diagnostics": sum(1 for e in result["entrants"] if e["diagnostic"]),
        "not_applied_actions": not_applied,
        "action_kinds": kinds,
        "positive_senses": positive,
        "enemy_core_writes": core_writes,
        "pressure_ticks": pressure,
        "disruption_onsets": onsets,
        "swings": swings,
        "winner_core_cells_at_end": own_cells[-1].get(winner) if winner in own_cells[-1] else None,
        "artifacts": run["artifacts"],
    }


def hard_filter_failures(m: dict[str, Any]) -> list[str]:
    failures = []
    if m["termination_reason"] != "last_agent_standing":
        failures.append("H2 decisive capture finish")
    if not LENGTH_RANGE[0] <= m["ticks"] <= LENGTH_RANGE[1]:
        failures.append("H3 length 300-800")
    if min(m["enemy_core_writes"].values()) < 1:
        failures.append("H4 both entrants attack")
    if m["positive_senses"]["A"] < MIN_A_POSITIVE_SENSES or m["positive_senses"]["B"] < 1:
        failures.append("H5 observable sensing")
    loser = "B" if m["winner"] == "A" else "A"
    if (
        m["diagnostics"]
        or m["not_applied_actions"]
        or (m["winner"] in ("A", "B") and m["entrant_termination"].get(loser) != "core_captured")
    ):
        failures.append("H6 legal play, elimination by core capture")
    return failures


def _balance(values: dict[str, int]) -> float:
    low, high = min(values.values()), max(values.values())
    return low / high if high else 0.0


def score(m: dict[str, Any]) -> dict[str, float]:
    """Weighted entertainment and gameplay criteria, each in [0, 1] (protocol section 6)."""
    ticks = m["ticks"]
    parts = {
        "contest": min(m["pressure_ticks"].values()) / ticks,
        "swings": min(m["swings"] * 100 / ticks / 20, 1.0),
        "sensing": _balance(m["positive_senses"]),
        "disruption": _balance(m["disruption_onsets"]),
        "length": max(0.0, 1 - abs(ticks - LENGTH_IDEAL) / 250),
        "close_finish": 1 - ((m["winner_core_cells_at_end"] or 1) - 1) / (CORE - 1),
    }
    parts = {k: round(v, 6) for k, v in parts.items()}
    parts["total"] = round(sum(WEIGHTS[k] * v for k, v in parts.items()), 4)
    return parts


def rank_key(row: dict[str, Any]) -> tuple:
    """Total, then contest, then closeness to 550 ticks, then lower seed, then P1 before P2."""
    return (
        -row["score"]["total"],
        -row["score"]["contest"],
        abs(row["metrics"]["ticks"] - LENGTH_IDEAL),
        row["metrics"]["seed"],
        row["pairing"],
    )


def rank_all(work: Path) -> dict[str, Any]:
    rows, errors = [], []
    for pairing in PAIRINGS:
        for seed in SEEDS:
            src = candidate_dir(work, pairing, seed)
            if not (src / "match.json").is_file():
                errors.append({"pairing": pairing, "seed": seed})
                continue
            m = candidate_metrics(src)
            rows.append({"pairing": pairing, "metrics": m, "failures": hard_filter_failures(m), "score": score(m)})
    qualified = sorted((r for r in rows if not r["failures"]), key=rank_key)
    for position, row in enumerate(qualified, start=1):
        row["rank"] = position
    ranking = {
        "protocol": PROTOCOL_ID,
        "search_source_sha256": sha256_file(Path(__file__)),
        "candidates": len(rows),
        "missing_or_failed_runs": errors,
        "qualified": len(qualified),
        "failure_counts": _failure_counts(rows),
        "ranking": [_summary(r) for r in qualified],
        "all": [_summary(r) for r in sorted(rows, key=lambda r: (r["pairing"], r["metrics"]["seed"]))],
    }
    (work / "ranking.json").write_bytes(canonical_json(ranking))
    return ranking


def _failure_counts(rows: list[dict[str, Any]]) -> dict[str, int]:
    counts: dict[str, int] = {}
    for row in rows:
        for failure in row["failures"]:
            counts[failure] = counts.get(failure, 0) + 1
    return dict(sorted(counts.items()))


def _summary(row: dict[str, Any]) -> dict[str, Any]:
    m = row["metrics"]
    return {
        "rank": row.get("rank"),
        "pairing": row["pairing"],
        "seed": m["seed"],
        "agents": m["agents"],
        "ticks": m["ticks"],
        "termination_reason": m["termination_reason"],
        "winner": m["winner"],
        "failures": row["failures"],
        "score": row["score"],
        "pressure_ticks": m["pressure_ticks"],
        "swings": m["swings"],
        "positive_senses": m["positive_senses"],
        "disruption_onsets": m["disruption_onsets"],
        "enemy_core_writes": m["enemy_core_writes"],
        "winner_core_cells_at_end": m["winner_core_cells_at_end"],
        "artifacts": m["artifacts"],
    }


# ---------------------------------------------------------------------------
# Validation (H7) in rank order
# ---------------------------------------------------------------------------


def validate(bytefray_root: Path, work: Path, limit: int) -> dict[str, Any]:
    ranking = json.loads((work / "ranking.json").read_text(encoding="ascii"))
    attempts = []
    selected = None
    for row in ranking["ranking"][:limit]:
        src = candidate_dir(work, row["pairing"], row["seed"])
        out = work / "validation" / f"{row['pairing']}-seed-{row['seed']:04d}"
        attempt = {"rank": row["rank"], "pairing": row["pairing"], "seed": row["seed"]}
        try:
            first = export(bytefray_root, src, out / "export-1")
            second = export(bytefray_root, src, out / "export-2")
            identical = all(
                (out / "export-1" / name).read_bytes() == (out / "export-2" / name).read_bytes()
                for name in ("manifest.json", "broadcast.json", "agent_a.json")
            )
            attempt.update(
                verified=True,
                repeat_export_identical=identical,
                manifest_sha256=sha256_file(out / "export-1" / "manifest.json"),
                winner=first["match"]["winner"],
                ticks=first["match"]["ticks"],
                termination_reason=first["match"]["termination_reason"],
            )
            del second
        except Exception as exc:
            attempt.update(verified=False, error=f"{type(exc).__name__}: {exc}")
        attempts.append(attempt)
        if attempt.get("verified") and attempt.get("repeat_export_identical"):
            selected = attempt
            break
    record = {"protocol": PROTOCOL_ID, "ranking_sha256": sha256_file(work / "ranking.json"), "attempts": attempts}
    record["selected"] = selected
    (work / "validation.json").write_bytes(canonical_json(record))
    return record


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("command", choices=("run", "rank", "validate"))
    parser.add_argument("--bytefray-root", type=Path)
    parser.add_argument("--work", type=Path, required=True)
    parser.add_argument("--workers", type=int, default=1)
    parser.add_argument("--limit", type=int, default=10, help="validate: most candidates tried, in rank order")
    args = parser.parse_args(argv)
    if args.command == "run":
        print(json.dumps(run_all(args.bytefray_root.resolve(), args.work, args.workers)))
    elif args.command == "rank":
        ranking = rank_all(args.work)
        print(json.dumps({k: ranking[k] for k in ("candidates", "qualified", "failure_counts")}))
    else:
        print(json.dumps(validate(args.bytefray_root.resolve(), args.work, args.limit)["selected"]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
