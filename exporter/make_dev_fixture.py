"""Generate the deterministic development fixture from the pinned Bytefray.

The fixture is Bytefray's own M1-2 Window Scout teaching demonstration
(``battle_engine.sensing_demo.run_sensing_demo``), arena 512, run at the fixed
seed declared below. The seed was declared before any match was run: it is the
demo's own published default. No seed was searched, compared or selected.

The demo runs into a fresh system-temp directory (the only product output
location it accepts besides ``runs/``), so nothing is written into the
Bytefray checkout. The four artifacts are copied to ``fixtures/dev/source`` and
a declaration with reproducibility digests is written to
``fixtures/dev/fixture.json``.

Usage::

    python exporter/make_dev_fixture.py --bytefray-root D:/Projects/BATTLE2
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
    SOURCE_NAMES,
    SPECTATOR_ROOT,
    ExportError,
    _import_bytefray,
    canonical_json,
    sha256_file,
    verify_pin,
)

DEV_SEED = 0  # declared: equals battle_engine.sensing_demo.DEFAULT_SEED
DEV_FIXTURE_DIR = SPECTATOR_ROOT / "fixtures" / "dev"
# Wall-clock fields are the only nondeterministic content of the artifacts.
TRACE_WALL_CLOCK_FIELD = "wall_time_ms"


def normalized_trace_sha256(trace_path: Path) -> str:
    """Digest of the trace with per-record wall-clock timings removed."""
    digest = hashlib.sha256()
    with trace_path.open(encoding="utf-8") as handle:
        for line in handle:
            record = json.loads(line)
            record.pop(TRACE_WALL_CLOCK_FIELD, None)
            digest.update(canonical_json(record))
    return digest.hexdigest()


def run_demo(bytefray_root: Path, pin_path: Path = DEFAULT_PIN) -> tuple[Path, dict[str, Any], Any]:
    """Run the pinned demo at DEV_SEED into a new system-temp directory."""
    pin = json.loads(pin_path.read_text(encoding="utf-8"))
    pin_record = verify_pin(bytefray_root, pin)
    _import_bytefray(bytefray_root)
    from battle_engine import sensing_demo

    if sensing_demo.DEFAULT_SEED != DEV_SEED or sensing_demo.DEFAULT_ARENA_SIZE != 512:
        raise ExportError("pinned demo defaults differ from the declared fixture")
    out = Path(tempfile.mkdtemp(prefix="spectator-dev-fixture-"))
    demo = sensing_demo.run_sensing_demo(out, seed=DEV_SEED)
    if not demo.is_verified:
        raise ExportError("teaching demonstration did not verify")
    return out, pin_record, demo


def make_fixture(bytefray_root: Path, pin_path: Path = DEFAULT_PIN) -> dict[str, Any]:
    out, pin_record, _ = run_demo(bytefray_root, pin_path)
    source_dir = DEV_FIXTURE_DIR / "source"
    source_dir.mkdir(parents=True, exist_ok=True)
    for name in SOURCE_NAMES:
        shutil.copyfile(out / name, source_dir / name)
    shutil.rmtree(out)
    result = json.loads((source_dir / "result.json").read_text(encoding="utf-8"))
    reproducibility = result["reproducibility"]
    declaration = {
        "schema": "bytefray.spectator.fixture",
        "schema_version": 1,
        "name": "dev",
        "purpose": "development fixture only; non-decisive matches are not showcase material",
        "generator": "battle_engine.sensing_demo.run_sensing_demo",
        "bytefray": pin_record,
        "seed": DEV_SEED,
        "seed_policy": (
            "fixed and declared before any run (the demo's published DEFAULT_SEED); "
            "not searched, compared or selected"
        ),
        "config": {
            "arena_size": reproducibility["arena_size"],
            "action_budget": reproducibility["action_budget"],
            "tick_limit": reproducibility["tick_limit"],
            "entrants": [[e["agent_id"], e["name"]] for e in result["entrants"]],
        },
        "outcome": {
            "ticks": result["ticks"],
            "termination_reason": result["termination_reason"],
            "winner": result["winner"],
            "decisive": result["termination_reason"] != "tick_limit",
        },
        "reproducibility": {
            "replay_sha256": sha256_file(source_dir / "replay.jsonl"),
            "trace_sha256_without_wall_time_ms": normalized_trace_sha256(source_dir / "trace.jsonl"),
            "nondeterministic_fields": [
                "trace.jsonl: wall_time_ms",
                "result.json: completed_at, occurrence_id",
                "demo.json: completed_at and the result/trace digests that follow from them",
            ],
        },
        "sources": {name: sha256_file(source_dir / name) for name in SOURCE_NAMES},
    }
    (DEV_FIXTURE_DIR / "fixture.json").write_bytes(canonical_json(declaration))
    return declaration


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--bytefray-root", type=Path, required=True)
    parser.add_argument("--pin", type=Path, default=DEFAULT_PIN)
    args = parser.parse_args(argv)
    try:
        declaration = make_fixture(args.bytefray_root.resolve(), args.pin)
    except Exception as exc:
        print(f"fixture generation failed: {exc}", file=sys.stderr)
        return 1
    print(json.dumps(declaration["outcome"]), declaration["reproducibility"]["replay_sha256"])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
