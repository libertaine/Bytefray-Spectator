"""The P0-C showcase fixture (fixtures/showcase) and its selection provenance."""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from pathlib import Path

import pytest

EXPORTER = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(EXPORTER))

import make_dev_fixture  # noqa: E402
from run_match import agent_digests, run_match  # noqa: E402
from showcase_search import PROTOCOL_ID, candidate_metrics, hard_filter_failures, score  # noqa: E402
from spectator_export import _import_bytefray, export, sha256_file, verify_pin  # noqa: E402

ROOT = EXPORTER.parent
# The exporter tests need the unpublished pinned Bytefray source. There is no default
# location: without BYTEFRAY_ROOT they are skipped, never silently pointed elsewhere.
BYTEFRAY_ROOT = Path(os.environ["BYTEFRAY_ROOT"]).resolve() if os.environ.get("BYTEFRAY_ROOT") else None
needs_bytefray = pytest.mark.skipif(BYTEFRAY_ROOT is None, reason="needs unpublished pinned Bytefray source; set BYTEFRAY_ROOT")
GODOT = Path(os.environ.get("GODOT", "C:/Program Files/Godot/Godot_v4.7.2-stable_win64_console.exe"))
FIXTURE = ROOT / "fixtures" / "showcase"
SOURCE = FIXTURE / "source"
PRESENTATION = FIXTURE / "presentation"
SELECTION = FIXTURE / "selection"
FILES = ("manifest.json", "broadcast.json", "agent_a.json")


def _json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def test_fixture_declaration_binds_sources_selection_and_frozen_agents() -> None:
    declaration = _json(FIXTURE / "fixture.json")
    for name, digest in declaration["sources"].items():
        assert sha256_file(SOURCE / name) == digest
    selection = declaration["selection"]
    assert selection["protocol"] == PROTOCOL_ID
    assert sha256_file(ROOT / selection["protocol_document"]) == selection["protocol_document_sha256"]
    for key in ("ranking", "validation", "examination"):
        assert sha256_file(SELECTION / f"{key}.json") == selection[f"{key}_sha256"]
    run = _json(SOURCE / "match.json")
    for entrant in run["entrants"]:
        current = agent_digests(ROOT / "agents" / entrant["name"])
        assert current["tree_sha256"] == entrant["source_tree_sha256"]
        assert current["files"] == entrant["source_files"]
    assert run["config"]["placement"] == "seeded" and run["seed"] == declaration["seed"] == 427


def test_selected_candidate_is_rank_one_and_its_metrics_reproduce() -> None:
    ranking = _json(SELECTION / "ranking.json")
    validation = _json(SELECTION / "validation.json")
    top = ranking["ranking"][0]
    assert (top["rank"], top["pairing"], top["seed"]) == (1, "P1", 427)
    assert ranking["candidates"] == 1000 and not ranking["missing_or_failed_runs"]
    assert validation["selected"]["seed"] == 427 and validation["ranking_sha256"] == sha256_file(SELECTION / "ranking.json")
    metrics = candidate_metrics(SOURCE)
    assert hard_filter_failures(metrics) == []
    assert score(metrics) == top["score"]
    assert metrics["artifacts"] == top["artifacts"]


def test_manifest_vouches_for_presentation_and_outcome() -> None:
    manifest = _json(PRESENTATION / "manifest.json")
    for entry in manifest["presentation"].values():
        assert sha256_file(PRESENTATION / entry["path"]) == entry["sha256"]
    for name, entry in manifest["sources"].items():
        assert sha256_file(SOURCE / name) == entry["sha256"]
    verification = manifest["verification"]
    assert verification["provenance"] == "showcase_match" and verification["outcome_verified"] is True
    assert verification["artifact_pair_consistent"] and verification["exchange_reconstructed"]
    match = manifest["match"]
    assert (match["winner"], match["termination_reason"], match["ticks"], match["tick_limit"]) == (
        "B",
        "last_agent_standing",
        477,
        1000,
    )
    broadcast = _json(PRESENTATION / "broadcast.json")
    alive_by_tick = {frame["t"]: frame["alive"] for frame in broadcast["frames"] if frame["p"] == 2}
    assert alive_by_tick[477] == ["B"] and alive_by_tick[476] == ["A", "B"]


@needs_bytefray
def test_reexport_is_byte_identical(tmp_path: Path) -> None:
    export(BYTEFRAY_ROOT, SOURCE, tmp_path)
    for name in FILES:
        assert (tmp_path / name).read_bytes() == (PRESENTATION / name).read_bytes(), name


@needs_bytefray
def test_match_reproduces_from_frozen_inputs(tmp_path: Path) -> None:
    declaration = _json(FIXTURE / "fixture.json")
    agents = ROOT / "agents"
    run_match(BYTEFRAY_ROOT, agents / "spectator_harrier", agents / "spectator_bastion", 427, tmp_path / "rerun")
    assert sha256_file(tmp_path / "rerun" / "replay.jsonl") == declaration["reproducibility"]["replay_sha256"]
    assert (
        make_dev_fixture.normalized_trace_sha256(tmp_path / "rerun" / "trace.jsonl")
        == declaration["reproducibility"]["trace_sha256_without_wall_time_ms"]
    )


@needs_bytefray
def test_viewer_sense_window_is_the_pinned_ruleset_value() -> None:
    """The one rule constant the viewer draws with: the public SENSE half-width."""
    source = (ROOT / "scripts" / "broadcast_effects.gd").read_text(encoding="utf-8")
    table = dict(re.findall(r'"([a-z0-9-]+)": (\d+)', re.search(r"SENSE_HALF_WIDTH := \{([^}]*)\}", source).group(1)))
    verify_pin(BYTEFRAY_ROOT, _json(ROOT / "bytefray.pin.json"))
    _import_bytefray(BYTEFRAY_ROOT)
    from battle_engine.ruleset_policy import resolve_ruleset_policy

    for ruleset_id, half_width in table.items():
        assert resolve_ruleset_policy(ruleset_id).sensing_window == int(half_width)
    broadcast = _json(PRESENTATION / "broadcast.json")
    window = int(table[broadcast["ruleset_id"]])
    agent = _json(PRESENTATION / "agent_a.json")
    assert {s["half_width"] for frame in agent["frames"] for s in frame["samples"]} == {window}
    arena = broadcast["arena_size"]
    for frame in broadcast["frames"]:
        for anchor in (frame["sensed"] or []) if frame["p"] == 1 else []:
            distance = abs(anchor - frame["address"]) % arena
            assert min(distance, arena - distance) <= window


def _replay_core_states() -> dict[int, dict[str, tuple[int, bool]]]:
    """Core cells held and alive per entrant at every tick, from replay.jsonl alone."""
    states: dict[int, dict[str, tuple[int, bool]]] = {}
    owners: dict[int, str | None] = {}
    cores: dict[str, list[int]] = {}
    arena = None
    with (SOURCE / "replay.jsonl").open(encoding="utf-8") as handle:
        for line in handle:
            record = json.loads(line)
            if record.get("record_type") == "header":
                arena = record["config"]["arena_size"]
            if record.get("record_type") != "tick":
                continue
            if record["tick"] == 0:
                cores = {a["id"]: [(a["region"][0] + k) % arena for k in range(8)] for a in record["agents"]}
            for diff in record["memory_diffs"]:
                for k in range(diff["length"]):
                    owners[(diff["address"] + k) % arena] = diff["owner"]
            states[record["tick"]] = {
                a["id"]: (sum(owners.get(cell) == a["id"] for cell in cores[a["id"]]), a["alive"]) for a in record["agents"]
            }
    return states


@pytest.mark.skipif(not GODOT.is_file(), reason=f"Godot not found at {GODOT} (set GODOT)")
def test_godot_plays_the_showcase_fixture(tmp_path: Path) -> None:
    core_log = tmp_path / "cores.txt"
    completed = subprocess.run(
        [str(GODOT), "--headless", "--path", str(ROOT), "--script", "res://tests/fixture_check.gd"]
        + ["--", f"--fixture={PRESENTATION}", f"--core-log={core_log}"],
        capture_output=True,
        text=True,
        timeout=900,
        check=False,
    )
    assert completed.returncode == 0 and "FIXTURE CHECK PASS" in completed.stdout, completed.stdout + completed.stderr

    # P1-3: the core gauges at every tick end equal the replay's authoritative tick states.
    replay = _replay_core_states()
    shown: dict[int, dict[str, tuple[int, str]]] = {}
    for line in core_log.read_text(encoding="utf-8").splitlines():
        tick, *entrants = line.split(",")
        shown[int(tick)] = {e.split(":")[0]: (int(e.split(":")[1]), e.split(":")[2]) for e in entrants}
    assert sorted(shown) == sorted(replay) == list(range(478))
    for tick, entrants in replay.items():
        for entrant, (held, alive) in entrants.items():
            level = "eliminated" if not alive else "critical" if held <= 2 else "low" if held <= 4 else "ok"
            assert shown[tick][entrant] == (held, level), (tick, entrant)
    # The review ticks named in the P1 authorization.
    review = {tick: {e: shown[tick][e] for e in ("A", "B")} for tick in (12, 320, 447, 467, 476, 477)}
    assert review == {
        12: {"A": (6, "ok"), "B": (4, "low")},
        320: {"A": (4, "low"), "B": (1, "critical")},
        447: {"A": (3, "low"), "B": (1, "critical")},
        467: {"A": (2, "critical"), "B": (8, "ok")},
        476: {"A": (2, "critical"), "B": (2, "critical")},
        477: {"A": (0, "eliminated"), "B": (2, "critical")},
    }
