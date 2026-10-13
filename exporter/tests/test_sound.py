"""The viewer's procedural sound and memory rendering checks, run headless.

The Godot check needs no audio output: it checks the generated clips, the cues
against references built from the raw presentation files, and what playback,
seeking, pausing, muting and switching start. Agent A's sounds are also part of
the differential traces in test_knowledge_isolation.py. The memory ring check
also verifies address geometry, recorded ownership, seeking, isolation and
identical playback and sound across Classic and Filled Arcs.
"""

from __future__ import annotations

import os
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
GODOT = Path(os.environ.get("GODOT", "C:/Program Files/Godot/Godot_v4.7.2-stable_win64_console.exe"))


@pytest.mark.skipif(not GODOT.is_file(), reason=f"Godot not found at {GODOT} (set GODOT)")
@pytest.mark.parametrize(
    ("script", "marker"),
    [("sound_check", "SOUND CHECK PASS"), ("memory_ring_check", "MEMORY RING CHECK PASS")],
)
def test_godot_sound_check(script: str, marker: str) -> None:
    if not (ROOT / ".godot").is_dir():
        subprocess.run([str(GODOT), "--headless", "--path", str(ROOT), "--import"], capture_output=True, timeout=900, check=False)
    completed = subprocess.run(
        [str(GODOT), "--headless", "--path", str(ROOT), "--script", f"res://tests/{script}.gd"],
        capture_output=True,
        text=True,
        timeout=900,
        check=False,
    )
    output = completed.stdout + completed.stderr
    assert completed.returncode == 0 and marker in completed.stdout, output
    assert "FAIL:" not in output, output
