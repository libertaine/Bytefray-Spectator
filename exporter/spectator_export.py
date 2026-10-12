"""Read-only exporter: one verified Bytefray V6 alpha1 match -> Spectator files.

The exporter never simulates and never writes into the Bytefray checkout. It
imports Bytefray's own verification and projection code from a local checkout
whose packages must be byte-identical to the commit pinned in
``bytefray.pin.json``, then writes three files:

* ``broadcast.json`` - the omniscient (broadcast) presentation, one frame per
  verified exchange fact, built from ``SensingCursor(entrant_id=None)``;
* ``agent_a.json``   - Agent A's presentation, built *only* from the
  receipt-only ``SensingView`` objects of ``SensingCursor(entrant_id="A")``;
* ``manifest.json``  - provenance, verification outcome and SHA-256 digests.

Usage::

    python exporter/spectator_export.py --bytefray-root D:/Projects/BATTLE2 \
        --source fixtures/dev/source --out fixtures/dev/presentation
"""

from __future__ import annotations

import sys

# Importing the pinned checkout must not leave __pycache__ files inside it.
sys.dont_write_bytecode = True

import argparse  # noqa: E402
import hashlib  # noqa: E402
import json  # noqa: E402
import os  # noqa: E402
import subprocess  # noqa: E402
from pathlib import Path  # noqa: E402
from typing import Any  # noqa: E402

EXPORTER_VERSION = 1
MANIFEST_SCHEMA = "bytefray.spectator.manifest"
BROADCAST_SCHEMA = "bytefray.spectator.broadcast"
AGENT_SCHEMA = "bytefray.spectator.agent_view"
SCHEMA_VERSION = 1

SPECTATOR_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_PIN = SPECTATOR_ROOT / "bytefray.pin.json"
SOURCE_NAMES = ("replay.jsonl", "trace.jsonl", "result.json", "demo.json")
AGENT_ID = "A"
PHASE_CODES = {"OBSERVATION": 0, "ACTION": 1, "TICK_END": 2}

# Every key that may appear anywhere in agent_a.json. Anything else is a leak.
AGENT_ALLOWED_KEYS = frozenset(
    {
        "schema", "schema_version", "entrant_id", "name", "label", "arena_size",
        "core_base", "core_size", "opponent_activity", "phase_codes", "frames",
        "t", "cb", "p", "processes", "contacts", "receipt", "events", "samples",
        "reads", "address", "sampled", "received", "age_ticks", "age_callbacks",
        "stale_since", "kind", "process", "operand", "value", "cost", "status",
        "sample_status", "message", "center", "half_width", "addresses", "owner",
        *PHASE_CODES,
    }
)  # fmt: skip


class ExportError(RuntimeError):
    """The inputs could not be verified; nothing usable was exported."""


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def canonical_json(document: Any) -> bytes:
    """Deterministic encoding: sorted keys, no whitespace, ASCII, LF end."""
    text = json.dumps(document, sort_keys=True, separators=(",", ":"), ensure_ascii=True)
    return (text + "\n").encode("ascii")


def _git(root: Path, *args: str, stdin: str | None = None) -> str:
    # GIT_OPTIONAL_LOCKS=0 keeps git from refreshing (writing) the index.
    env = dict(os.environ, GIT_OPTIONAL_LOCKS="0")
    completed = subprocess.run(
        ["git", "-C", str(root), *args],
        input=stdin,
        capture_output=True,
        text=True,
        env=env,
        check=False,
    )
    if completed.returncode != 0:
        raise ExportError(f"git {args[0]} failed: {completed.stderr.strip()}")
    return completed.stdout


def verify_pin(root: Path, pin: dict[str, Any]) -> dict[str, Any]:
    """Prove the checkout's pinned packages equal the pinned commit's tree."""
    commit = pin["commit"]
    if _git(root, "rev-parse", "--verify", f"{commit}^{{commit}}").strip() != commit:
        raise ExportError(f"pinned commit {commit} is not present in {root}")
    listing = _git(root, "ls-tree", "-r", "--full-tree", commit, "--", *pin["paths"])
    tree: dict[str, str] = {}
    for line in listing.splitlines():
        meta, path = line.split("\t", 1)
        tree[path] = meta.split()[2]
    working = sorted(
        path.relative_to(root).as_posix()
        for package in pin["paths"]
        for path in (root / package).rglob("*")
        if path.is_file() and "__pycache__" not in path.parts
    )
    missing = sorted(set(tree) - set(working))
    extra = sorted(set(working) - set(tree))
    if missing or extra:
        raise ExportError(f"pinned packages differ from {commit}: missing={missing} extra={extra}")
    hashes = _git(root, "hash-object", "--stdin-paths", stdin="\n".join(working) + "\n").split()
    modified = [path for path, blob in zip(working, hashes, strict=True) if tree[path] != blob]
    if modified:
        raise ExportError(f"pinned packages modified relative to {commit}: {modified}")
    return {
        "repository": pin["repository"],
        "commit": commit,
        "paths": list(pin["paths"]),
        "files_verified": len(working),
        "tree_listing_sha256": hashlib.sha256(listing.encode("utf-8")).hexdigest(),
    }


def _import_bytefray(root: Path) -> None:
    for sub in ("client/src", "engine/src"):
        sys.path.insert(0, str(root / sub))
    import battle_client
    import battle_engine

    for module in (battle_engine, battle_client):
        location = Path(module.__file__ or "").resolve()
        if root.resolve() not in location.parents:
            raise ExportError(f"{module.__name__} imported from {location}, not the pinned checkout")


def _tick_zero_regions(replay_path: Path) -> dict[str, int]:
    with replay_path.open(encoding="utf-8") as handle:
        for line in handle:
            record = json.loads(line)
            if record.get("record_type") == "tick" and record.get("tick") == 0:
                return {agent["id"]: agent["region"][0] for agent in record["agents"]}
    raise ExportError("replay has no tick-0 snapshot")


def _broadcast(playback: Any, cursor: Any, core_cells: dict[str, list[int]], result: dict[str, Any]) -> dict[str, Any]:
    facts = playback.facts
    if len(cursor.positions) != len(facts):
        raise ExportError("broadcast positions do not match the verified facts")
    entrants = [
        {
            "id": entrant["agent_id"],
            "name": entrant["name"],
            "alive": entrant["alive"],
            "score": entrant["score"],
            "core": core_cells[entrant["agent_id"]],
        }
        for entrant in result["entrants"]
    ]
    frames: list[dict[str, Any]] = []
    previous: tuple[str | None, ...] | None = None
    view = cursor.restart()
    for index, fact in enumerate(facts):
        if index:
            view = cursor.step_forward()  # TICK_END steps re-check the replay boundary
        if (view.tick, view.global_decision_index, view.phase) != (fact.tick, fact.decision_index, fact.phase):
            raise ExportError(f"broadcast frame {index} is out of order with the verified facts")
        frame: dict[str, Any] = {
            "t": view.tick,
            "d": view.global_decision_index,
            "p": PHASE_CODES[view.phase.value],
            "anchors": [[entrant, process, anchor] for entrant, process, anchor in view.anchors],
            "disrupted": [[entrant, process] for entrant, process in view.disrupted_processes],
            "alive": list(view.alive_entrants),
            "actor": fact.actor_id,
            "process": fact.process_id,
            "kind": fact.action_kind,
            "status": fact.status,
            "address": fact.normalized_address,
            "operand": fact.operand,
            "sensed": None if fact.sensed_anchors is None else list(fact.sensed_anchors),
        }
        if previous is None:
            frame["owners"] = list(view.owners)
        else:
            frame["owner_changes"] = [
                [cell, owner] for cell, (old, owner) in enumerate(zip(previous, view.owners, strict=True)) if old != owner
            ]
        previous = view.owners
        frames.append(frame)
    return {
        "schema": BROADCAST_SCHEMA,
        "schema_version": SCHEMA_VERSION,
        "label": "Broadcast - full world state",
        "match_id": playback.match_id,
        "ruleset_id": playback.ruleset_id,
        "arena_size": playback.arena_size,
        "entrants": entrants,
        "result": {
            "termination_reason": result["termination_reason"],
            "ticks": result["ticks"],
            "winner": result["winner"],
        },
        "phase_codes": PHASE_CODES,
        "frames": frames,
    }


def _point(point: Any) -> list[Any]:
    return [point.tick, point.callback, point.process_id]


def _agent(cursor: Any, name: str) -> dict[str, Any]:
    """Serialize SensingView objects only; never the playback, facts or world."""
    from battle_client.sensing import SensingView

    frames: list[dict[str, Any]] = []
    seen = {"events": 0, "samples": 0, "reads": 0}
    first: Any = None
    view = cursor.restart()
    for index in range(len(cursor.positions)):
        if index:
            view = cursor.step_forward()
        if not isinstance(view, SensingView) or view.entrant_id != AGENT_ID:
            raise ExportError("agent cursor produced a non-entrant view")
        first = first or view
        events = view.events[seen["events"] :]
        samples = view.samples[seen["samples"] :]
        reads = view.reads[seen["reads"] :]
        seen = {"events": len(view.events), "samples": len(view.samples), "reads": len(view.reads)}
        frames.append(
            {
                "t": view.position.tick,
                "cb": view.position.callback,
                "p": PHASE_CODES[view.position.phase.value],
                "processes": [[p.process_id, p.anchor, p.reach] for p in view.own_processes],
                "contacts": [
                    {
                        "address": c.address,
                        "sampled": _point(c.sampled_at),
                        "received": _point(c.received_at),
                        "age_ticks": c.age_ticks,
                        "age_callbacks": c.age_callbacks,
                        "stale_since": None if c.not_present_in_newer_sample is None else _point(c.not_present_in_newer_sample),
                    }
                    for c in view.contacts
                ],
                "receipt": view.receipt_status.value,
                "events": [
                    {
                        "kind": e.kind,
                        "process": e.process_id,
                        "address": e.address,
                        "operand": e.operand,
                        "value": e.value,
                        "cost": e.cost,
                        "status": e.status,
                        "sample_status": e.sample_status.value,
                        "message": e.message,
                    }
                    for e in events
                ],
                "samples": [
                    {
                        "center": s.center,
                        "half_width": s.half_width,
                        "status": s.status.value,
                        "addresses": list(s.addresses),
                        "sampled": _point(s.sampled_at),
                        "received": _point(s.received_at),
                    }
                    for s in samples
                ],
                "reads": [
                    {
                        "address": r.address,
                        "value": r.value,
                        "owner": r.owner,
                        "sampled": _point(r.sampled_at),
                        "received": _point(r.received_at),
                    }
                    for r in reads
                ],
            }
        )
    if first is None:
        raise ExportError("agent view has no permitted phases")
    document = {
        "schema": AGENT_SCHEMA,
        "schema_version": SCHEMA_VERSION,
        "entrant_id": AGENT_ID,
        "name": name,
        "label": first.label,
        "arena_size": first.arena_size,
        "core_base": first.own_core_base,
        "core_size": first.own_core_size,
        "opponent_activity": first.opponent_activity,
        "phase_codes": PHASE_CODES,
        "frames": frames,
    }
    check_agent_allowlist(document)
    return document


def check_agent_allowlist(node: Any, path: str = "$") -> None:
    """Fail closed if the agent document carries any key outside the allowlist."""
    if isinstance(node, dict):
        for key, value in node.items():
            if key not in AGENT_ALLOWED_KEYS:
                raise ExportError(f"agent view leak: unexpected key {path}.{key}")
            check_agent_allowlist(value, f"{path}.{key}")
    elif isinstance(node, list):
        for item in node:
            check_agent_allowlist(item, path + "[]")


def export(bytefray_root: Path, source_dir: Path, out_dir: Path, pin_path: Path = DEFAULT_PIN) -> dict[str, Any]:
    # A failed export must never leave an older manifest vouching for new files.
    (out_dir / "manifest.json").unlink(missing_ok=True)
    pin = json.loads(pin_path.read_text(encoding="utf-8"))
    pin_record = verify_pin(bytefray_root, pin)
    _import_bytefray(bytefray_root)

    from battle_client.sensing import SensingCursor
    from battle_client.session import ReplaySession
    from battle_engine.python_runtime import core_addresses
    from battle_engine.rules import BYTEFRAY_RULESET_V6_ALPHA1_ID
    from battle_engine.sensing_playback import reconstruct_sensing_playback, verify_demonstration_artifacts

    paths = {name: source_dir / name for name in SOURCE_NAMES}
    for name, path in paths.items():
        if not path.is_file():
            raise ExportError(f"missing source artifact {name}")
    sources = {name: {"sha256": sha256_file(path), "bytes": path.stat().st_size} for name, path in paths.items()}

    verify_demonstration_artifacts(paths["demo.json"])
    playback = reconstruct_sensing_playback(
        paths["replay.jsonl"], paths["trace.jsonl"], result_path=paths["result.json"], demo_path=paths["demo.json"]
    )
    if playback.ruleset_id != BYTEFRAY_RULESET_V6_ALPHA1_ID:
        raise ExportError(f"unsupported ruleset {playback.ruleset_id}")
    result = json.loads(paths["result.json"].read_text(encoding="utf-8"))
    session = ReplaySession()
    session.load(paths["replay.jsonl"])

    broadcast_cursor = SensingCursor(playback, session, None)
    report = broadcast_cursor.verification_report()
    if not (report.artifact_pair_consistent and report.exchange_reconstructed and report.teaching_complete):
        raise ExportError("match did not verify")
    regions = _tick_zero_regions(paths["replay.jsonl"])
    core_cells = {entrant: list(core_addresses(start, playback.arena_size)) for entrant, start in regions.items()}
    broadcast = _broadcast(playback, broadcast_cursor, core_cells, result)
    agent_name = next(e["name"] for e in result["entrants"] if e["agent_id"] == AGENT_ID)
    agent = _agent(SensingCursor(playback, session, AGENT_ID), agent_name)

    out_dir.mkdir(parents=True, exist_ok=True)
    presentation: dict[str, Any] = {}
    for key, filename, document in (
        ("broadcast", "broadcast.json", broadcast),
        ("agent_a", "agent_a.json", agent),
    ):
        data = canonical_json(document)
        (out_dir / filename).write_bytes(data)
        presentation[key] = {
            "path": filename,
            "schema": document["schema"],
            "sha256": hashlib.sha256(data).hexdigest(),
            "bytes": len(data),
            "frames": len(document["frames"]),
        }
    tick_ends = sum(1 for frame in broadcast["frames"] if frame["p"] == PHASE_CODES["TICK_END"])
    manifest = {
        "schema": MANIFEST_SCHEMA,
        "schema_version": SCHEMA_VERSION,
        "exporter": {
            "version": EXPORTER_VERSION,
            "source_sha256": sha256_file(Path(__file__)),
        },
        "bytefray": pin_record,
        "match": {
            "match_id": playback.match_id,
            "result_id": result["result_id"],
            "ruleset_id": playback.ruleset_id,
            "arena_size": playback.arena_size,
            "seed": result["reproducibility"]["seed"],
            "ticks": result["ticks"],
            "termination_reason": result["termination_reason"],
            "winner": result["winner"],
        },
        "sources": sources,
        "verification": {
            "artifact_pair_consistent": report.artifact_pair_consistent,
            "exchange_reconstructed": report.exchange_reconstructed,
            "teaching_complete": report.teaching_complete,
            "teaching_steps": [[name, status.value] for name, status in report.teaching_steps],
            "tick_end_boundaries_checked": tick_ends,
            "agent_view_allowlist_checked": True,
        },
        "presentation": presentation,
    }
    (out_dir / "manifest.json").write_bytes(canonical_json(manifest))
    return manifest


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--bytefray-root", type=Path, required=True)
    parser.add_argument("--source", type=Path, required=True, help="directory with replay/trace/result/demo")
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--pin", type=Path, default=DEFAULT_PIN)
    args = parser.parse_args(argv)
    try:
        manifest = export(args.bytefray_root.resolve(), args.source.resolve(), args.out.resolve(), args.pin)
    except Exception as exc:  # report, never emit a partial manifest
        print(f"export failed: {exc}", file=sys.stderr)
        return 1
    for key, entry in manifest["presentation"].items():
        print(f"{key}: {entry['path']} frames={entry['frames']} sha256={entry['sha256']}")
    print(f"bytefray commit: {manifest['bytefray']['commit']} ({manifest['bytefray']['files_verified']} files verified)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
