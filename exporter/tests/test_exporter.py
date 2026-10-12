"""Exporter, fixture and presentation-file checks.

Requires a local Bytefray checkout whose pinned packages match bytefray.pin.json
(BYTEFRAY_ROOT, default D:/Projects/BATTLE2) and its Python environment.
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

EXPORTER = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(EXPORTER))

import make_dev_fixture  # noqa: E402
import spectator_export  # noqa: E402
from spectator_export import ExportError, canonical_json, export, sha256_file, verify_pin  # noqa: E402

ROOT = EXPORTER.parent
BYTEFRAY_ROOT = Path(os.environ.get("BYTEFRAY_ROOT", "D:/Projects/BATTLE2")).resolve()
FIXTURE = ROOT / "fixtures" / "dev"
SOURCE = FIXTURE / "source"
PRESENTATION = FIXTURE / "presentation"
PRESENTATION_FILES = ("manifest.json", "broadcast.json", "agent_a.json")


def _load(name: str) -> dict:
    return json.loads((PRESENTATION / name).read_text(encoding="ascii"))


def _bytefray_snapshot() -> list[tuple[str, int, int]]:
    pin = json.loads(spectator_export.DEFAULT_PIN.read_text(encoding="utf-8"))
    return sorted(
        (path.relative_to(BYTEFRAY_ROOT).as_posix(), path.stat().st_size, path.stat().st_mtime_ns)
        for package in pin["paths"]
        for path in (BYTEFRAY_ROOT / package).rglob("*")
    )


def test_manifest_vouches_for_committed_files() -> None:
    manifest = _load("manifest.json")
    declaration = json.loads((FIXTURE / "fixture.json").read_text(encoding="ascii"))
    for entry in manifest["presentation"].values():
        path = PRESENTATION / entry["path"]
        assert sha256_file(path) == entry["sha256"]
        assert path.stat().st_size == entry["bytes"]
    for name, entry in manifest["sources"].items():
        assert sha256_file(SOURCE / name) == entry["sha256"] == declaration["sources"][name]
    assert manifest["bytefray"]["commit"] == declaration["bytefray"]["commit"]
    assert manifest["match"]["arena_size"] == 512
    assert manifest["match"]["seed"] == declaration["seed"] == make_dev_fixture.DEV_SEED == 0
    verification = manifest["verification"]
    assert verification["artifact_pair_consistent"] and verification["exchange_reconstructed"]
    assert verification["teaching_complete"] and verification["agent_view_allowlist_checked"]
    assert all(status == "VERIFIED" for _, status in verification["teaching_steps"])
    assert verification["tick_end_boundaries_checked"] == manifest["match"]["ticks"] + 1


def test_reexport_is_byte_identical_and_writes_nothing_into_bytefray(tmp_path: Path) -> None:
    before = _bytefray_snapshot()
    export(BYTEFRAY_ROOT, SOURCE, tmp_path)
    assert _bytefray_snapshot() == before
    for name in PRESENTATION_FILES:
        assert (tmp_path / name).read_bytes() == (PRESENTATION / name).read_bytes(), name


def test_fixture_regenerates_deterministically() -> None:
    declaration = json.loads((FIXTURE / "fixture.json").read_text(encoding="ascii"))
    out, pin_record, demo = make_dev_fixture.run_demo(BYTEFRAY_ROOT)
    try:
        assert demo.is_verified
        assert pin_record["commit"] == declaration["bytefray"]["commit"]
        recorded = declaration["reproducibility"]
        assert sha256_file(out / "replay.jsonl") == recorded["replay_sha256"]
        assert make_dev_fixture.normalized_trace_sha256(out / "trace.jsonl") == recorded["trace_sha256_without_wall_time_ms"]
    finally:
        shutil.rmtree(out)


def test_agent_view_carries_only_delivered_knowledge() -> None:
    agent = _load("agent_a.json")
    broadcast = _load("broadcast.json")
    spectator_export.check_agent_allowlist(agent)
    cores = {e["id"]: e["core"] for e in broadcast["entrants"]}
    assert agent["entrant_id"] == "A" and agent["core_base"] == cores["A"][0]
    assert agent["opponent_activity"] == "Unobserved"
    text = json.dumps(agent)
    for omniscient_key in ('"owners"', '"owner_changes"', '"anchors"', '"alive"', '"disrupted"', '"actor"', '"d"'):
        assert omniscient_key not in text
    own_processes = {process for entrant, process, _ in broadcast["frames"][0]["anchors"] if entrant == "A"}
    delivered: set[int] = set()
    for frame in agent["frames"]:
        for sample in frame["samples"]:
            delivered.update(sample["addresses"])
        assert {p[0] for p in frame["processes"]} <= own_processes
        # Every contact the agent shows was delivered to it by a sample.
        assert {c["address"] for c in frame["contacts"]} <= delivered
        for read in frame["reads"]:
            assert read["received"][0] <= frame["t"]


def test_broadcast_final_board_and_alive_set_match_the_replay() -> None:
    broadcast = _load("broadcast.json")
    frames = broadcast["frames"]
    owners = list(frames[0]["owners"])
    for frame in frames[1:]:
        for cell, owner in frame["owner_changes"]:
            owners[cell] = owner
    replay_owners: list[str | None] = [None] * broadcast["arena_size"]
    final_alive = None
    with (SOURCE / "replay.jsonl").open(encoding="utf-8") as handle:
        for line in handle:
            record = json.loads(line)
            if record.get("record_type") != "tick":
                continue
            for diff in record["memory_diffs"]:
                for offset in range(diff["length"]):
                    replay_owners[(diff["address"] + offset) % broadcast["arena_size"]] = diff["owner"]
            final_alive = sorted(a["id"] for a in record["agents"] if a["alive"])
    assert owners == replay_owners
    assert frames[-1]["alive"] == final_alive
    assert frames[-1]["t"] == broadcast["result"]["ticks"]


def test_export_refuses_a_tampered_source(tmp_path: Path) -> None:
    source = tmp_path / "source"
    shutil.copytree(SOURCE, source)
    trace = bytearray((source / "trace.jsonl").read_bytes())
    trace[len(trace) // 2] ^= 1
    (source / "trace.jsonl").write_bytes(bytes(trace))
    out = tmp_path / "out"
    out.mkdir()
    (out / "manifest.json").write_bytes(b"stale")
    with pytest.raises(Exception):  # noqa: B017 - any verification failure is a refusal
        export(BYTEFRAY_ROOT, source, out)
    assert not (out / "manifest.json").exists()


def _git(cwd: Path, *args: str) -> str:
    return subprocess.run(["git", *args], cwd=cwd, check=True, capture_output=True, text=True).stdout


def test_pin_refuses_a_checkout_that_differs_from_the_pinned_commit(tmp_path: Path) -> None:
    repo = tmp_path / "bytefray"
    package = repo / "engine" / "src" / "battle_engine"
    package.mkdir(parents=True)
    (package / "module.py").write_text("VALUE = 1\n", encoding="utf-8")
    _git(repo, "init", "-q")
    _git(repo, "add", ".")
    _git(repo, "-c", "user.name=t", "-c", "user.email=t@example.invalid", "commit", "-q", "-m", "pin")
    commit = _git(repo, "rev-parse", "HEAD").strip()
    pin = {"repository": "test", "commit": commit, "paths": ["engine/src/battle_engine"]}
    assert verify_pin(repo, pin)["files_verified"] == 1
    (package / "module.py").write_text("VALUE = 2\n", encoding="utf-8")
    with pytest.raises(ExportError, match="modified"):
        verify_pin(repo, pin)
    (package / "module.py").write_text("VALUE = 1\n", encoding="utf-8")
    (package / "extra.py").write_text("", encoding="utf-8")
    with pytest.raises(ExportError, match="extra"):
        verify_pin(repo, pin)


def test_canonical_json_is_stable() -> None:
    document = {"b": [1, {"z": None, "a": "\u2014"}], "a": 2}
    assert canonical_json(document) == b'{"a":2,"b":[1,{"a":"\\u2014","z":null}]}\n'
    assert canonical_json(dict(reversed(document.items()))) == canonical_json(document)
