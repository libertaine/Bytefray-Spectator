"""Production (manifest v2) presentations written by Bytefray itself.

Bytefray's ``bytefray spectator export`` (battle_client.spectator_export) is the
production exporter; this repository's pinned prototype exporter and its frozen
fixtures are unchanged. These tests check the contract from Spectator's side:

* without Bytefray: the bundled ``fixtures/production_sample`` declaration and
  manifest bind their files, the viewer accepts version 2 and rejects every
  unsupported or tampered variant, and what the viewer shows of the sample
  equals the sample's own authoritative match records;
* with ``BYTEFRAY_PRODUCTION_ROOT`` (a Bytefray checkout that has
  ``battle_client/spectator_export.py``): the production exporter reproduces
  the frozen showcase and the bundled sample presentation documents byte for
  byte, and a freshly played match goes Bytefray -> export -> Spectator with the
  viewer showing exactly Bytefray's recorded chronology, deliveries and result.

Skipped tests are reported as skipped, never counted as passes.
"""

from __future__ import annotations

import hashlib
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
SAMPLE = ROOT / "fixtures" / "production_sample"
SHOWCASE = ROOT / "fixtures" / "showcase"
GODOT = Path(os.environ.get("GODOT", "C:/Program Files/Godot/Godot_v4.7.2-stable_win64_console.exe"))
PRODUCTION = Path(os.environ["BYTEFRAY_PRODUCTION_ROOT"]).resolve() if os.environ.get("BYTEFRAY_PRODUCTION_ROOT") else None
needs_godot = pytest.mark.skipif(not GODOT.is_file(), reason="needs Godot 4.7.2; set GODOT")
needs_production = pytest.mark.skipif(
    PRODUCTION is None or not (PRODUCTION / "client/src/battle_client/spectator_export.py").is_file(),
    reason="needs a Bytefray checkout with the production exporter; set BYTEFRAY_PRODUCTION_ROOT",
)
DOCUMENTS = ("broadcast.json", "agent_a.json")


def _sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def _godot(*args: str) -> subprocess.CompletedProcess[str]:
    if not (ROOT / ".godot").is_dir():
        subprocess.run([str(GODOT), "--headless", "--path", str(ROOT), "--import"], capture_output=True, timeout=900, check=False)
    return subprocess.run(
        [str(GODOT), "--headless", "--path", str(ROOT), *args], capture_output=True, text=True, timeout=900, check=False
    )


def _bytefray(*args: str, cwd: Path | None = None) -> subprocess.CompletedProcess[str]:
    assert PRODUCTION is not None
    env = dict(os.environ)
    env["PYTHONPATH"] = os.pathsep.join([str(PRODUCTION / "engine/src"), str(PRODUCTION / "client/src")])
    env["PYTHONDONTWRITEBYTECODE"] = "1"
    command = [sys.executable, "-m", "battle_engine", *args]
    return subprocess.run(command, capture_output=True, text=True, timeout=1800, env=env, cwd=cwd, check=False)


def _num(value):
    return int(value) if isinstance(value, float) and value.is_integer() else value


def _norm(rows: list) -> list:
    return [[_num(v) if not isinstance(v, list) else [_num(x) for x in v] for v in row] for row in rows]


def _dump(tmp_path: Path, presentation: Path) -> dict:
    out = tmp_path / "dump.json"
    # The same viewer arguments Designer passes to an installed Spectator.
    completed = _godot(
        "--script", "res://tests/acceptance_dump.gd", "--",
        f"--fixture={presentation}", "--perspective=broadcast", f"--out={out}",
    )  # fmt: skip
    assert completed.returncode == 0, completed.stdout + completed.stderr
    return _json(out)


def assert_viewer_matches_records(dump: dict, source: Path) -> None:
    """What the viewer showed equals Bytefray's authoritative trace and result."""
    result = _json(source / "result.json")
    decisions = [
        record
        for record in map(json.loads, (source / "trace.jsonl").read_text(encoding="utf-8").splitlines())
        if record.get("record_type") == "decision_v2"
    ]
    # Broadcast: every recorded action, in order, with its recorded outcome.
    assert _norm(dump["broadcast"]["actions"]) == [
        [
            d["observation"]["current_tick"], d["agent_id"], d["process_id"], d["action"]["kind"],
            d["applied_result"]["status"], d["applied_result"].get("normalized_address"),
        ]
        for d in decisions
    ]  # fmt: skip
    broadcast = dump["broadcast"]
    assert {k: _num(v) for k, v in broadcast["result"].items()} == {
        "winner": result["winner"], "termination_reason": result["termination_reason"], "ticks": result["ticks"],
    }  # fmt: skip
    assert [_num(t) for t, _ in broadcast["tick_ends"]] == list(range(result["ticks"] + 1))
    assert broadcast["tick_ends"][-1][1] == [e["agent_id"] for e in result["entrants"] if e["alive"]]
    assert _num(broadcast["end_tick"]) == result["ticks"]
    names = {e["agent_id"]: e["name"] for e in result["entrants"]}
    if result["winner"] in names:
        assert broadcast["banner"] == f"{result['winner']} {names[result['winner']]} WINS".upper()
        assert broadcast["panel_result_line"][0].startswith(f"Result: {result['winner']} {names[result['winner']]} wins")
    else:
        assert broadcast["banner"] == f"RESULT: {result['winner']}".upper()

    # Agent A: its own actions, and only what was delivered to it.
    own = [d for d in decisions if d["agent_id"] == "A"]
    assert [row[:4] for row in _norm(dump["agent_a"]["events"])] == [
        [d["observation"]["current_tick"], d["process_id"], d["action"]["kind"], d["applied_result"]["status"]] for d in own
    ]
    samples: list[list] = []
    reads: list[list] = []
    last: dict[str, dict] = {}
    for d in own:
        observation, previous = d["observation"], last.get(d["process_id"])
        if "previous_sense_anchors" in observation and previous is not None:
            anchors = observation["previous_sense_anchors"]
            samples.append(
                [previous["observation"]["current_tick"], observation["current_tick"],
                 previous["applied_result"]["normalized_address"], anchors if anchors is not None else []]
            )  # fmt: skip
        if (
            previous is not None
            and previous["action"]["kind"] == "read"
            and observation.get("previous_action_applied") is True
            and observation.get("previous_read_value") is not None
        ):
            reads.append(
                [previous["observation"]["current_tick"], previous["applied_result"]["normalized_address"],
                 observation["previous_read_value"], observation["previous_read_owner"]]
            )  # fmt: skip
        last[d["process_id"]] = d
    assert [[s[0], s[1], s[2], s[4]] for s in _norm(dump["agent_a"]["samples"])] == samples
    assert _norm(dump["agent_a"]["reads"]) == reads
    # The Agent A perspective never shows the outcome or the match length.
    agent_text = dump["agent_a"]["position_label"] + dump["agent_a"]["panel"]
    assert "wins" not in agent_text.lower() and f"/ {result['ticks']}" not in dump["agent_a"]["position_label"]
    assert f"(limit {result['reproducibility']['tick_limit']})" in dump["agent_a"]["position_label"]


# --- bundled production sample (no Bytefray needed) ---------------------------------


def test_sample_declaration_and_manifest_bind_their_files() -> None:
    declaration = _json(SAMPLE / "fixture.json")
    for name, digest in declaration["sources"].items():
        assert _sha(SAMPLE / "source" / name) == digest
    for name, digest in declaration["presentation"].items():
        assert _sha(SAMPLE / "presentation" / name) == digest
    manifest = _json(SAMPLE / "presentation" / "manifest.json")
    assert (manifest["schema"], manifest["schema_version"]) == ("bytefray.spectator.manifest", 2)
    assert manifest["verification"]["provenance"] == "bytefray_match"
    assert manifest["exporter"]["name"] == "battle_client.spectator_export"
    for name, record in manifest["sources"].items():
        data = (SAMPLE / "source" / name).read_bytes()
        assert record == {"sha256": hashlib.sha256(data).hexdigest(), "bytes": len(data)}
    for key, filename in (("broadcast", "broadcast.json"), ("agent_a", "agent_a.json")):
        entry = manifest["presentation"][key]
        data = (SAMPLE / "presentation" / filename).read_bytes()
        assert (entry["sha256"], entry["bytes"], entry["schema_version"]) == (hashlib.sha256(data).hexdigest(), len(data), 1)
    result = _json(SAMPLE / "source" / "result.json")
    assert {k: manifest["match"][k] for k in ("match_id", "winner", "ticks")} == {
        k: result[k] for k in ("match_id", "winner", "ticks")
    }
    assert declaration["outcome"] == {k: manifest["match"][k] for k in ("winner", "termination_reason", "ticks")}


@needs_godot
def test_viewer_presentation_handling() -> None:
    completed = _godot("--script", "res://tests/presentation_check.gd")
    assert completed.returncode == 0 and "PRESENTATION CHECK PASS" in completed.stdout, completed.stdout + completed.stderr


@needs_godot
def test_viewer_plays_the_sample_end_to_end() -> None:
    completed = _godot("--script", "res://tests/fixture_check.gd", "--", "--fixture=sample")
    assert completed.returncode == 0 and "FIXTURE CHECK PASS" in completed.stdout, completed.stdout + completed.stderr


@needs_godot
def test_viewer_shows_the_samples_authoritative_records(tmp_path: Path) -> None:
    assert_viewer_matches_records(_dump(tmp_path, SAMPLE / "presentation"), SAMPLE / "source")


@needs_godot
def test_viewer_rejects_a_tampered_copy_launched_like_designer(tmp_path: Path) -> None:
    copy = tmp_path / "presentation with spaces"
    shutil.copytree(SAMPLE / "presentation", copy)
    data = bytearray((copy / "agent_a.json").read_bytes())
    data[len(data) // 2] ^= 1
    (copy / "agent_a.json").write_bytes(bytes(data))
    completed = _godot(
        "--script", "res://tests/acceptance_dump.gd", "--",
        f"--fixture={copy}", "--perspective=broadcast", f"--out={tmp_path / 'dump.json'}",
    )  # fmt: skip
    assert completed.returncode == 1 and "agent_a.json SHA-256 does not match" in completed.stderr
    assert not (tmp_path / "dump.json").exists()


# --- with the production exporter ------------------------------------------------------


@needs_production
@pytest.mark.parametrize("fixture", ["showcase", "production_sample"])
def test_production_exporter_reproduces_bundled_documents(tmp_path: Path, fixture: str) -> None:
    source = ROOT / "fixtures" / fixture / "source"
    out = tmp_path / "presentation"
    completed = _bytefray("spectator", "export", "--source", str(source), "--out", str(out))
    assert completed.returncode == 0, completed.stderr
    for name in DOCUMENTS:
        assert (out / name).read_bytes() == (ROOT / "fixtures" / fixture / "presentation" / name).read_bytes(), name
    if fixture == "production_sample":
        produced, bundled = _json(out / "manifest.json"), _json(SAMPLE / "presentation" / "manifest.json")
        # Only the exporting Bytefray's identity may differ between Bytefray builds.
        assert {k: v for k, v in produced.items() if k != "bytefray"} == {k: v for k, v in bundled.items() if k != "bytefray"}


@needs_production
@needs_godot
def test_fresh_bytefray_match_plays_correctly_in_spectator(tmp_path: Path) -> None:
    """Bytefray V6 match -> verified artifacts -> production export -> standalone Spectator."""
    match = tmp_path / "Bytefray Runs" / "match one"
    match.mkdir(parents=True)
    played = _bytefray(
        "run", "--ticks", "150", "--arena", "512", "--a-type", "v6_window_scout", "--b-type", "v6_watchful_keeper",
        "--ruleset", "bytefray-rules-6-alpha1", "--seed", "11", "--win-mode", "score_fallback",
        "--replay", str(match / "replay.jsonl"), "--trace", str(match / "trace.jsonl"),
    )  # fmt: skip
    assert played.returncode == 0, played.stderr[-2000:]
    presentation = tmp_path / "Spectator Presentations" / "match one"
    exported = _bytefray("spectator", "export", "--source", str(match), "--out", str(presentation))
    assert exported.returncode == 0, exported.stderr
    manifest = _json(presentation / "manifest.json")
    assert manifest["schema_version"] == 2 and manifest["sources"]["trace.jsonl"]["sha256"] == _sha(match / "trace.jsonl")
    dump = _dump(tmp_path, presentation)
    assert dump["manifest_version"] == 2 and dump["footer"].startswith("Verified Bytefray match")
    assert_viewer_matches_records(dump, match)
