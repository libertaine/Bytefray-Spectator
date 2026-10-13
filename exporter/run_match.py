"""Run one V6 alpha1 match between two agent directories with the pinned Bytefray.

The runner mirrors ``bytefray run --ruleset bytefray-rules-6-alpha1`` (seeded
core placement, declared parameter defaults, engine Config defaults) but takes
agent directories directly, so nothing is written into the Bytefray checkout.
Each agent directory is first copied into a private snapshot; the match runs
from the snapshot, and the snapshot's file digests must equal the source's.

Outputs in ``out_dir`` (which must not exist yet): ``replay.jsonl``,
``trace.jsonl``, ``result.json`` and ``match.json``, a canonical run record
binding the three artifacts, the pin, the configuration and both agents'
source digests.

Usage::

    python exporter/run_match.py --bytefray-root D:/Projects/BATTLE2 \
        --agent-a agents/sweeper --agent-b agents/hunter --seed 17 --out <dir>
"""

from __future__ import annotations

import sys

sys.dont_write_bytecode = True

import argparse  # noqa: E402
import hashlib  # noqa: E402
import json  # noqa: E402
import shutil  # noqa: E402
import tempfile  # noqa: E402
from pathlib import Path  # noqa: E402
from typing import Any  # noqa: E402

sys.path.insert(0, str(Path(__file__).resolve().parent))
from spectator_export import (  # noqa: E402
    DEFAULT_PIN,
    ExportError,
    _import_bytefray,
    canonical_json,
    sha256_file,
    verify_pin,
)

RUN_SCHEMA = "bytefray.spectator.match_run"
RUN_SCHEMA_VERSION = 1
ARTIFACTS = ("replay.jsonl", "trace.jsonl", "result.json")
DEFAULT_ARENA = 512
DEFAULT_BUDGET = 8
DEFAULT_TICKS = 1000
# Directory names SensingCursor refuses as research inputs; transient match
# outputs must never live under them.
REFUSED_PATH_PARTS = ("research", "research_", "e9_", "e8_", ".pytest_e9_")


def agent_digests(agent_dir: Path) -> dict[str, Any]:
    """Per-file SHA-256 of an agent directory (bytecode caches excluded)."""
    files = {
        path.relative_to(agent_dir).as_posix(): sha256_file(path)
        for path in sorted(agent_dir.rglob("*"))
        if path.is_file() and "__pycache__" not in path.parts
    }
    listing = "".join(f"{digest}  {name}\n" for name, digest in files.items())
    return {"files": files, "tree_sha256": hashlib.sha256(listing.encode("utf-8")).hexdigest()}


def _check_output_location(out_dir: Path, bytefray_root: Path) -> None:
    resolved = out_dir.resolve()
    if bytefray_root.resolve() in (resolved, *resolved.parents):
        raise ExportError("match output must be outside the Bytefray checkout")
    for part in resolved.parts:
        lowered = part.lower()
        if lowered == "research" or lowered.startswith(REFUSED_PATH_PARTS[1:]):
            raise ExportError(f"match output path contains a refused research component: {part}")
    if out_dir.exists():
        raise ExportError(f"match output directory already exists: {out_dir}")


def run_match(
    bytefray_root: Path,
    agent_a: Path,
    agent_b: Path,
    seed: int,
    out_dir: Path,
    *,
    ticks: int = DEFAULT_TICKS,
    arena_size: int = DEFAULT_ARENA,
    action_budget: int = DEFAULT_BUDGET,
    starts: tuple[int, int] | None = None,
    pin_path: Path = DEFAULT_PIN,
) -> dict[str, Any]:
    """Run one match; ``starts`` overrides seeded placement (tests only)."""
    _check_output_location(out_dir, bytefray_root)
    pin = json.loads(pin_path.read_text(encoding="utf-8"))
    pin_record = verify_pin(bytefray_root, pin)
    _import_bytefray(bytefray_root)

    from battle_engine.agent_parameters import resolve_parameters
    from battle_engine.agents import agent_spec_from_dir
    from battle_engine.config import Config
    from battle_engine.match_service import MatchEntrant, MatchRequest, NativeMatchService
    from battle_engine.placement import resolve_direct_match_starts
    from battle_engine.rules import BYTEFRAY_RULESET_V6_ALPHA1_ID

    sources = {"A": agent_a.resolve(), "B": agent_b.resolve()}
    declared = {seat: agent_digests(path) for seat, path in sources.items()}
    resolved_starts = resolve_direct_match_starts(
        ruleset_id=BYTEFRAY_RULESET_V6_ALPHA1_ID,
        arena_size=arena_size,
        entrant_count=2,
        supplied_starts=list(starts) if starts is not None else [None, None],
        seed=seed,
    )
    out_dir.mkdir(parents=True)
    with tempfile.TemporaryDirectory(prefix="spectator-agents-") as snapshot_root:
        entrants = []
        records = []
        for (seat, source), start in zip(sources.items(), resolved_starts, strict=True):
            snapshot = Path(snapshot_root) / seat / source.name
            shutil.copytree(source, snapshot, ignore=shutil.ignore_patterns("__pycache__"))
            if agent_digests(snapshot) != declared[seat]:
                raise ExportError(f"agent {seat} snapshot differs from its source")
            spec = agent_spec_from_dir(snapshot)
            if spec is None:
                raise ExportError(f"agent {seat}: {source} is not an agent directory")
            parameters = resolve_parameters(spec.parameter_schema, legacy_defaults=getattr(spec, "defaults", None), path=snapshot)
            entrants.append(MatchEntrant.python(seat, spec.name, start, spec, parameters))
            records.append(
                {
                    "agent_id": seat,
                    "name": spec.name,
                    "start": start,
                    "parameters": parameters,
                    "source_tree_sha256": declared[seat]["tree_sha256"],
                    "source_files": declared[seat]["files"],
                }
            )
        config = Config(arena_size=arena_size, instr_per_tick=action_budget, seed=seed)
        NativeMatchService().run(
            MatchRequest(
                config=config,
                entrants=tuple(entrants),
                max_ticks=ticks,
                replay_path=out_dir / "replay.jsonl",
                trace_path=out_dir / "trace.jsonl",
                ruleset_id=BYTEFRAY_RULESET_V6_ALPHA1_ID,
                verbose=False,
            )
        )
        for seat, record in zip(sources, records, strict=True):
            snapshot = Path(snapshot_root) / seat / sources[seat].name
            if agent_digests(snapshot)["tree_sha256"] != record["source_tree_sha256"]:
                raise ExportError(f"agent {seat} source changed during the match")
    result = json.loads((out_dir / "result.json").read_text(encoding="utf-8"))
    for record, entrant in zip(records, result["entrants"], strict=True):
        if entrant["agent_id"] != record["agent_id"] or entrant["name"] != record["name"]:
            raise ExportError("result entrants do not match the requested entrants")
    run = {
        "schema": RUN_SCHEMA,
        "schema_version": RUN_SCHEMA_VERSION,
        "runner_source_sha256": sha256_file(Path(__file__)),
        "bytefray": pin_record,
        "ruleset_id": BYTEFRAY_RULESET_V6_ALPHA1_ID,
        "seed": seed,
        "config": {
            "arena_size": arena_size,
            "action_budget": action_budget,
            "tick_limit": ticks,
            "placement": "explicit" if starts is not None else "seeded",
        },
        "entrants": records,
        "artifacts": {name: sha256_file(out_dir / name) for name in ARTIFACTS},
    }
    (out_dir / "match.json").write_bytes(canonical_json(run))
    return run


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--bytefray-root", type=Path, required=True)
    parser.add_argument("--agent-a", type=Path, required=True)
    parser.add_argument("--agent-b", type=Path, required=True)
    parser.add_argument("--seed", type=int, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--ticks", type=int, default=DEFAULT_TICKS)
    args = parser.parse_args(argv)
    try:
        run = run_match(args.bytefray_root.resolve(), args.agent_a, args.agent_b, args.seed, args.out, ticks=args.ticks)
    except Exception as exc:
        print(f"match failed: {exc}", file=sys.stderr)
        return 1
    print(json.dumps(run["artifacts"]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
