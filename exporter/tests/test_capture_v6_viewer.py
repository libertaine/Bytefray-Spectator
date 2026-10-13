"""The P0-D V6 viewer baseline capture is reproducible and shows the requested ticks."""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path

import pytest

EXPORTER = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(EXPORTER))

from capture_v6_viewer import capture  # noqa: E402

BYTEFRAY_ROOT = Path(os.environ.get("BYTEFRAY_ROOT", "D:/Projects/BATTLE2")).resolve()
SOURCE = EXPORTER.parent / "fixtures" / "showcase" / "source"


def test_capture_is_byte_identical_across_runs(tmp_path: Path) -> None:
    pytest.importorskip("pygame")
    first = capture(BYTEFRAY_ROOT, SOURCE, tmp_path / "one", [12, 477])
    second = capture(BYTEFRAY_ROOT, SOURCE, tmp_path / "two", [12, 477])
    assert (tmp_path / "one" / "capture.json").read_bytes() == (tmp_path / "two" / "capture.json").read_bytes()
    assert first == second
    shots = {(shot["perspective"], shot["requested_tick"]): shot for shot in first["captures"]}
    assert set(shots) == {(p, t) for p in ("omniscient", "agent_a") for t in (12, 477)}
    for (perspective, tick), shot in shots.items():
        assert shot["shown_tick"] == tick and shot["phase"] == "TICK_END"
        assert shot["entrant_view"] is (perspective == "agent_a")
    declaration = json.loads((SOURCE.parent / "fixture.json").read_text(encoding="utf-8"))
    assert first["source"]["replay.jsonl"] == declaration["sources"]["replay.jsonl"]
    assert first["pacing"]["omniscient"]["phase_positions"] == 15310
