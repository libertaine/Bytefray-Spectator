"""The announcer's voice clips (audio/announcer) and their offline generator.

The processed clips must reproduce byte for byte from the committed raw clips,
and every digest must match voice.json. Where the Windows SAPI voice is
installed, speaking a word again must give the committed raw clip's bytes.
The spoken-name rule must match scripts/announcer.gd (checked there too).
"""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

import pytest

EXPORTER = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(EXPORTER))

import make_announcer_voice as voice  # noqa: E402


def _record() -> dict:
    return json.loads((voice.VOICE_DIR / "voice.json").read_text(encoding="ascii"))


def test_clips_verify_and_reproduce_from_raw() -> None:
    assert voice.check() == []
    record = _record()
    assert record["generator"] == voice.GENERATOR and record["settings"] == voice.SETTINGS
    assert {"FIGHT", "WINS", "PLAYER", "A", "B", "BASTION", "HARRIER"} <= set(record["words"])


def test_vocabulary_covers_every_agent_and_the_fallback() -> None:
    assert set(voice.vocabulary([])) == set(_record()["words"])


@pytest.mark.parametrize(
    ("name", "words"),
    [
        ("spectator_bastion", ["BASTION"]),
        ("spectator_harrier", ["HARRIER"]),
        ("v6_window_scout", ["WINDOW", "SCOUT"]),
        ("spectator_v2_iron-fist", ["IRON", "FIST"]),
        ("spectator", []),
    ],
)
def test_spoken_words(name: str, words: list[str]) -> None:
    assert voice.spoken_words(name) == words


def _voice_installed() -> bool:
    if sys.platform != "win32":
        return False
    script = (
        "Add-Type -AssemblyName System.Speech; "
        "(New-Object System.Speech.Synthesis.SpeechSynthesizer).GetInstalledVoices() | ForEach-Object { $_.VoiceInfo.Name }"
    )
    listed = subprocess.run(["powershell", "-NoProfile", "-Command", script], capture_output=True, text=True, check=False)
    return voice.VOICE in listed.stdout.splitlines()


@pytest.mark.skipif(not _voice_installed(), reason=f"SAPI voice {voice.VOICE!r} not installed")
@pytest.mark.parametrize("word", ["FIGHT", "BASTION", "WINS"])
def test_speech_step_reproduces_the_raw_clip(word: str, tmp_path: Path) -> None:
    out = tmp_path / f"{word.lower()}.wav"
    voice.synthesize(word, out)
    assert voice.sha256(out) == _record()["words"][word]["raw_sha256"]
