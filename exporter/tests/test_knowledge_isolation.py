"""Differential knowledge-isolation tests for the Agent A perspective.

Window Scout (Agent A, unchanged official starter) plays short matches at fixed
starts against test-only opponents that differ only in activity A never
observes:

* ``quiet``  - one stationary process reading its own core;
* ``busy``   - two processes on the same anchor that read, write their own core
  and sense away from A: different action kinds, process count and ownership;
* ``split``  - a stationary process plus a decoy parked where A never scans, so
  when A disrupts the anchor the opponent keeps acting: a different number of
  hidden opponent decisions per tick (the omniscient timing).

Their Agent A exports must be byte-identical, and so must everything the viewer
shows in the Agent A perspective under stepping, seeking, the timeline, playback
and switching. ``relocating`` (moves once, onto a cell A does scan) is the
positive control proving the comparison can see a real difference.
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
from collections import Counter
from pathlib import Path

import pytest

EXPORTER = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(EXPORTER))

from run_match import run_match  # noqa: E402
from spectator_export import export  # noqa: E402

ROOT = EXPORTER.parent
BYTEFRAY_ROOT = Path(os.environ.get("BYTEFRAY_ROOT", "D:/Projects/BATTLE2")).resolve()
SCOUT = BYTEFRAY_ROOT / "engine/src/battle_engine/data/starter_agents/v6_window_scout"
AGENTS = Path(__file__).resolve().parent / "agents"
GODOT = Path(os.environ.get("GODOT", "C:/Program Files/Godot/Godot_v4.7.2-stable_win64_console.exe"))
TICKS = 120
STARTS = (0, 91)  # the teaching layout: A's first scan window covers B's anchor
UNOBSERVED = ("quiet", "busy", "split")


def _match(root: Path, name: str, agent_a: Path, opponent: str) -> Path:
    source = root / name / "source"
    run_match(BYTEFRAY_ROOT, agent_a, AGENTS / opponent, 0, source, ticks=TICKS, starts=STARTS)
    export(BYTEFRAY_ROOT, source, root / name / "presentation")
    return root / name / "presentation"


@pytest.fixture(scope="module")
def exports(tmp_path_factory: pytest.TempPathFactory) -> dict[str, Path]:
    root = tmp_path_factory.mktemp("isolation")
    out = {name: _match(root, name, SCOUT, f"{name}_opponent") for name in (*UNOBSERVED, "relocating")}
    out["raid"] = _match(root, "raid", AGENTS / "core_raider", "quiet_opponent")
    return out


def _load(path: Path, name: str) -> dict:
    return json.loads((path / name).read_text(encoding="ascii"))


def _opponent_decisions_per_tick(broadcast: dict) -> Counter:
    return Counter(frame["t"] for frame in broadcast["frames"] if frame["actor"] == "B" and frame["p"] == 1)


def test_unobserved_opponent_activity_leaves_agent_a_byte_identical(exports: dict[str, Path]) -> None:
    agent_bytes = {name: (exports[name] / "agent_a.json").read_bytes() for name in UNOBSERVED}
    assert len(set(agent_bytes.values())) == 1
    digests = {_load(exports[name], "manifest.json")["presentation"]["agent_a"]["sha256"] for name in UNOBSERVED}
    assert digests == {hashlib.sha256(agent_bytes["quiet"]).hexdigest()}


def test_the_unobserved_variants_really_differ(exports: dict[str, Path]) -> None:
    broadcasts = {name: _load(exports[name], "broadcast.json") for name in UNOBSERVED}
    raw = {name: (exports[name] / "broadcast.json").read_bytes() for name in UNOBSERVED}
    assert len(set(raw.values())) == len(UNOBSERVED)

    kinds = {name: {f["kind"] for f in b["frames"] if f["actor"] == "B" and f["p"] == 1} for name, b in broadcasts.items()}
    assert kinds["quiet"] == {"read"} and kinds["busy"] == {"read", "write", "sense"}
    processes = {name: {f["process"] for f in b["frames"] if f["actor"] == "B"} for name, b in broadcasts.items()}
    assert len(processes["quiet"]) == 1 and len(processes["busy"]) == len(processes["split"]) == 2

    # Hidden timing: the split opponent takes a different number of decisions in some ticks.
    quiet, split = (_opponent_decisions_per_tick(broadcasts[name]) for name in ("quiet", "split"))
    assert quiet != split
    assert len(broadcasts["quiet"]["frames"]) != len(broadcasts["split"]["frames"])
    for name in UNOBSERVED:
        assert broadcasts[name]["result"] == {"termination_reason": "tick_limit", "ticks": TICKS, "winner": "tie"}


def test_agent_frames_follow_entrant_local_positions_only(exports: dict[str, Path]) -> None:
    agent = _load(exports["quiet"], "agent_a.json")
    per_tick = Counter(frame["t"] for frame in agent["frames"])
    split = _load(exports["split"], "broadcast.json")
    assert per_tick == Counter(frame["t"] for frame in _load(exports["split"], "agent_a.json")["frames"])
    assert _opponent_decisions_per_tick(split) != _opponent_decisions_per_tick(_load(exports["quiet"], "broadcast.json"))
    callbacks = [frame["cb"] for frame in agent["frames"] if frame["cb"] is not None]
    assert callbacks == sorted(callbacks) and callbacks[0] == 1


def test_observed_opponent_activity_changes_agent_a(exports: dict[str, Path]) -> None:
    quiet = _load(exports["quiet"], "agent_a.json")
    relocating = _load(exports["relocating"], "agent_a.json")
    assert quiet != relocating

    def sample_sets(agent: dict) -> list[list[int]]:
        return [s["addresses"] for frame in agent["frames"] for s in frame["samples"]]

    assert sample_sets(quiet) != sample_sets(relocating)


def test_decisive_match_outcome_comes_from_verified_state(exports: dict[str, Path]) -> None:
    manifest = _load(exports["raid"], "manifest.json")
    broadcast = _load(exports["raid"], "broadcast.json")
    match = manifest["match"]
    assert (match["winner"], match["termination_reason"]) == ("A", "last_agent_standing")
    assert match["ticks"] < match["tick_limit"] == TICKS
    assert broadcast["result"] == {k: match[k] for k in ("termination_reason", "ticks", "winner")}
    assert broadcast["frames"][-1]["alive"] == ["A"]
    assert manifest["verification"]["provenance"] == "showcase_match"
    assert manifest["verification"]["outcome_verified"] is True


@pytest.mark.parametrize(
    ("field", "value", "reason"),
    [("seed", 7, "seed"), ("artifacts", {"replay.jsonl": "0" * 64}, "artifact digests"), ("ruleset_id", "x", "ruleset")],
)
def test_export_refuses_an_altered_match_record(
    exports: dict[str, Path], tmp_path: Path, field: str, value: object, reason: str
) -> None:
    source = tmp_path / "source"
    shutil.copytree(exports["raid"].parent / "source", source)
    record = json.loads((source / "match.json").read_text(encoding="ascii"))
    record[field] = value
    (source / "match.json").write_text(json.dumps(record), encoding="ascii")
    with pytest.raises(Exception, match=f"match.json does not verify: .*{reason}"):
        export(BYTEFRAY_ROOT, source, tmp_path / "out")


# ---------------------------------------------------------------------------
# What the Godot viewer shows in the Agent A perspective
# ---------------------------------------------------------------------------

needs_godot = pytest.mark.skipif(not GODOT.is_file(), reason=f"Godot not found at {GODOT} (set GODOT)")


def _godot(*args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [str(GODOT), "--headless", "--path", str(ROOT), *args], capture_output=True, text=True, timeout=900, check=False
    )


@pytest.fixture(scope="module")
def traces(exports: dict[str, Path], tmp_path_factory: pytest.TempPathFactory) -> dict[str, list[str]]:
    if not (ROOT / ".godot").is_dir():
        _godot("--import")
    out_dir = tmp_path_factory.mktemp("traces")
    traces: dict[str, list[str]] = {}
    for name in (*UNOBSERVED, "relocating", "raid"):
        out = out_dir / f"{name}.txt"
        completed = _godot("--script", "res://tests/agent_view_trace.gd", "--", f"--fixture={exports[name]}", f"--out={out}")
        assert completed.returncode == 0, completed.stdout + completed.stderr
        traces[name] = out.read_text(encoding="utf-8").splitlines()
    return traces


@needs_godot
def test_viewer_agent_perspective_is_identical_under_unobserved_activity(traces: dict[str, list[str]]) -> None:
    assert len(traces["quiet"]) > 3 * TICKS
    for name in UNOBSERVED[1:]:
        assert traces[name] == traces["quiet"], name
    assert {line.split("|", 1)[0] for line in traces["quiet"]} == {
        "step",
        "tick-back",
        "seek",
        "slider",
        "end",
        "jump",
        "play",
        "play-slow",
        "play-switch",
        "switch",
    }
    assert all(line.split("|")[1] == "agent_a" for line in traces["quiet"])
    # P1: the agent's own indicators and the static legend are recorded; the ring holds no broadcast
    # effects. (The footer and key hint contain "|", so later fields are matched by content.)
    legend = r"Own core location (ownership not delivered)\nOwn process and its reach"
    for line in traces["quiet"]:
        assert '"own_actions":' in line and f"|{legend}" in line and "|[{},[]]|" in line
    own = [json.loads(re.search(r'"own_actions":(\{.*?\]\})', line).group(1)) for line in traces["quiet"]]
    assert any(o["writes"] for o in own) and any(o["moves"] for o in own) and any(o["pending_senses"] for o in own)


@needs_godot
def test_viewer_trace_detects_observed_activity(traces: dict[str, list[str]]) -> None:
    assert traces["relocating"] != traces["quiet"]


@needs_godot
def test_viewer_agent_perspective_never_reveals_when_the_match_ends(traces: dict[str, list[str]]) -> None:
    ticks = _load_raid_ticks(traces)
    for line in traces["raid"]:
        fields = line.split("|")
        assert re.fullmatch(rf"Tick \d+ \(limit {TICKS}\)   [A-Z_]+   step \d+", fields[5]), fields[5]
        assert fields[6].endswith(f"/{TICKS}"), fields[6]
        assert "Result" not in fields[4] and "eliminated" not in fields[4]
    # The match itself ended long before the limit.
    assert ticks < TICKS


def _load_raid_ticks(traces: dict[str, list[str]]) -> int:
    seen = [int(re.match(r"Tick (\d+)", line.split("|")[5]).group(1)) for line in traces["raid"]]
    return max(seen)


def test_isolation_fixtures_leave_no_files_in_bytefray(exports: dict[str, Path]) -> None:
    status = subprocess.run(
        ["git", "-C", str(BYTEFRAY_ROOT), "status", "--porcelain", "--", "engine/src", "client/src"],
        capture_output=True,
        text=True,
        check=True,
    ).stdout
    assert status == ""
