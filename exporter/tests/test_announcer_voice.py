"""Original nonverbal cue provenance and deterministic raw/processed reproduction.

Historical desktop-voice clips were excluded from publication history. Current
cues must regenerate on any supported generator platform without a speech engine.
"""

from __future__ import annotations

import json
import shutil
import sys
from pathlib import Path

import pytest

EXPORTER = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(EXPORTER))

import make_arcade_cues as voice  # noqa: E402


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


@pytest.mark.parametrize("word", [*voice.BASE_WORDS, "BASTION", "HARRIER"])
def test_procedural_step_reproduces_the_raw_clip(word: str, tmp_path: Path) -> None:
    out = tmp_path / f"{word.lower()}.wav"
    voice.generate_cue(word, out)
    assert voice.sha256(out) == _record()["words"][word]["raw_sha256"]


def test_current_bank_is_original_nonverbal_version_two() -> None:
    record = _record()
    assert record["schema"] == "bytefray.spectator.announcer"
    assert record["schema_version"] == 2
    assert record["kind"] == "nonverbal-procedural" and record["license"] == "MIT"
    assert record["voice"] == voice.VOICE and "ssml" not in record
    assert record["words"]["BASTION"]["raw_sha256"] != record["words"]["HARRIER"]["raw_sha256"]


def test_arbitrary_raw_audio_cannot_be_relabelled_as_original_cues(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    bank = tmp_path / "bank"
    shutil.copytree(voice.VOICE_DIR, bank)
    monkeypatch.setattr(voice, "VOICE_DIR", bank)
    record = _record()
    entry = record["words"]["BASTION"]
    raw, processed = bank / entry["raw"], bank / entry["file"]
    voice.write_wav(raw, [0.1] * voice.MIX_RATE)
    voice.write_wav(processed, voice.process(voice.read_wav(raw)))
    entry["raw_sha256"], entry["sha256"] = voice.sha256(raw), voice.sha256(processed)
    (bank / "voice.json").write_text(json.dumps(record), encoding="ascii")
    before = {p.relative_to(bank): p.read_bytes() for p in bank.rglob("*") if p.is_file()}
    assert any("original oscillator" in problem for problem in voice.check())
    with pytest.raises(ValueError, match="raw bytes are not this original cue"):
        voice.build(voice.vocabulary([]), regenerate=False)
    assert before == {p.relative_to(bank): p.read_bytes() for p in bank.rglob("*") if p.is_file()}
    voice.build(voice.vocabulary([]), regenerate=True)
    assert voice.check() == []
    assert raw.read_bytes() == voice.wav_bytes(voice.cue_samples("BASTION"))
