"""The viewer's procedural sound effects (tests/sound_check.gd), run headless.

The Godot check needs no audio output: it checks the generated clips, the cues
against references built from the raw presentation files, and what playback,
seeking, pausing, muting and switching start. Agent A's sounds are also part of
the differential traces in test_knowledge_isolation.py.
"""

from __future__ import annotations

import os
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
GODOT = Path(os.environ.get("GODOT", "C:/Program Files/Godot/Godot_v4.7.2-stable_win64_console.exe"))


@pytest.mark.skipif(not GODOT.is_file(), reason=f"Godot not found at {GODOT} (set GODOT)")
def test_godot_sound_check() -> None:
    if not (ROOT / ".godot").is_dir():
        subprocess.run([str(GODOT), "--headless", "--path", str(ROOT), "--import"], capture_output=True, timeout=900, check=False)
    completed = subprocess.run(
        [str(GODOT), "--headless", "--path", str(ROOT), "--script", "res://tests/sound_check.gd"],
        capture_output=True,
        text=True,
        timeout=900,
        check=False,
    )
    output = completed.stdout + completed.stderr
    assert completed.returncode == 0 and "SOUND CHECK PASS" in completed.stdout, output
    assert "FAIL:" not in output, output
