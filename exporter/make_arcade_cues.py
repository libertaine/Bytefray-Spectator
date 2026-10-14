"""Generate original nonverbal arcade cue clips (audio/announcer/).

The labels FIGHT, WINS and entrant names identify electronic motifs, not spoken
words. Pure Python produces every raw PCM sample; the existing deterministic
arcade processing produces the playback clips. No speech engine, trained model,
voice recording or network is used. The version-2 manifest records this source
and binds the raw and processed bytes. See docs/AUDIO_ASSETS.md.

    python exporter/make_arcade_cues.py --check
    python exporter/make_arcade_cues.py --regenerate
    python exporter/make_arcade_cues.py --name spectator_new_agent
"""

from __future__ import annotations

import sys

sys.dont_write_bytecode = True

import argparse  # noqa: E402
import hashlib  # noqa: E402
import io  # noqa: E402
import json  # noqa: E402
import math  # noqa: E402
import re  # noqa: E402
import wave  # noqa: E402
from array import array  # noqa: E402
from pathlib import Path  # noqa: E402

SPECTATOR_ROOT = Path(__file__).resolve().parents[1]
VOICE_DIR = SPECTATOR_ROOT / "audio" / "announcer"
AGENTS = SPECTATOR_ROOT / "agents"

GENERATOR = "spectator-announcer-cues-v2"
VOICE = "Original procedural arcade cues (nonverbal)"
MIX_RATE = 22050
BASE_WORDS = ("FIGHT", "WINS", "PLAYER", "A", "B", "C", "D")
# Cue labels retained for the viewer vocabulary; the clips contain no speech.

# Processing settings (recorded in voice.json). A slower resample, sample-and-hold
# and an echo remain optional; current cues use only the settings recorded below.
SETTINGS = {
    "trim_threshold": 0.004,  # trims only silence; a soft oscillator onset is kept
    "trim_pad": 0.03,  # seconds kept either side
    "pitch": 0.92,  # resampling factor: 0.92 plays the motif lower and longer
    "gravel_hz": 41.0,  # amplitude buzz frequency
    "gravel_depth": 0.25,
    "drive": 2.0,
    "hold": 1,  # sample-and-hold factor (1 = off)
    "levels": 96,  # quantisation steps per unit amplitude
    "echo": [],  # [delay s, gain] pairs
    "lowpass_hz": 4500.0,
    "peak": 0.9,
}
WORD = re.compile(r"[A-Z0-9]+")


def spoken_words(agent_name: str) -> list[str]:
    """Cue labels of an agent: its name split on '_', '-' and spaces, upper case,
    without a leading 'spectator' or version word (v6). spectator_bastion -> BASTION,
    v6_window_scout -> WINDOW SCOUT. Mirrors scripts/announcer.gd."""
    words = [w.upper() for w in re.split(r"[_\- ]+", agent_name) if w]
    while words and (words[0] == "SPECTATOR" or re.fullmatch(r"V\d+", words[0])):
        words.pop(0)
    return [w for w in words if WORD.fullmatch(w)]


def read_wav(path: Path) -> list[float]:
    with wave.open(str(path), "rb") as w:
        if (w.getnchannels(), w.getsampwidth(), w.getframerate()) != (1, 2, MIX_RATE):
            raise ValueError(f"{path} is not {MIX_RATE} Hz 16-bit mono")
        data = array("h", w.readframes(w.getnframes()))
    if sys.byteorder == "big":
        data.byteswap()
    return [s / 32768.0 for s in data]


def wav_bytes(samples: list[float]) -> bytes:
    """Canonical mono PCM serialization, independent of any existing WAV."""
    data = array("h", (round(max(-1.0, min(1.0, s)) * 32767) for s in samples))
    if sys.byteorder == "big":
        data.byteswap()
    buffer = io.BytesIO()
    with wave.open(buffer, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(MIX_RATE)
        w.writeframes(data.tobytes())
    return buffer.getvalue()


def write_wav(path: Path, samples: list[float]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(wav_bytes(samples))


def process(raw: list[float]) -> list[float]:
    """Arcade processing: a pure function of the original raw motif."""
    s = SETTINGS
    # Trim silence.
    loud = [n for n, v in enumerate(raw) if abs(v) > s["trim_threshold"]]
    pad = int(s["trim_pad"] * MIX_RATE)
    x = raw[max(0, loud[0] - pad) : loud[-1] + pad + 1] if loud else raw
    # Deeper: resample by linear interpolation.
    out_len = int(len(x) / s["pitch"])
    y = []
    for m in range(out_len):
        pos = m * s["pitch"]
        k = int(pos)
        frac = pos - k
        a = x[k] if k < len(x) else 0.0
        b = x[k + 1] if k + 1 < len(x) else 0.0
        y.append(a + (b - a) * frac)
    # Gravel, drive, sample-and-hold and bit-crush.
    norm = math.tanh(s["drive"])
    held = 0.0
    for n in range(len(y)):
        t = n / MIX_RATE
        buzz = (1.0 - s["gravel_depth"]) + s["gravel_depth"] * math.tanh(4.0 * math.sin(2.0 * math.pi * s["gravel_hz"] * t))
        v = math.tanh(s["drive"] * y[n] * buzz) / norm
        if n % s["hold"] == 0:
            held = round(v * s["levels"]) / s["levels"]
        y[n] = held
    # Echo (off in the chosen settings).
    tail = max((int(d * MIX_RATE) for d, _ in s["echo"]), default=0)
    z = y + [0.0] * tail
    for delay, gain in s["echo"]:
        d = int(delay * MIX_RATE)
        for n in range(len(y)):
            z[n + d] += gain * y[n]
    # Low-pass, then normalise with 6 ms fades.
    alpha = 1.0 - math.exp(-2.0 * math.pi * s["lowpass_hz"] / MIX_RATE)
    acc = 0.0
    for n in range(len(z)):
        acc += alpha * (z[n] - acc)
        z[n] = acc
    peak = max((abs(v) for v in z), default=0.0) or 1.0
    fade = int(0.006 * MIX_RATE)
    for n in range(len(z)):
        z[n] = z[n] / peak * s["peak"] * min(1.0, n / fade, (len(z) - 1 - n) / fade)
    return z


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def vocabulary(extra_names: list[str]) -> list[str]:
    words = list(BASE_WORDS)
    names = sorted(p.name for p in AGENTS.iterdir() if (p / "agent.yaml").is_file()) if AGENTS.is_dir() else []
    for name in names + extra_names:
        words += spoken_words(name)
    return list(dict.fromkeys(words))


def cue_samples(word: str) -> list[float]:
    """Original electronic motif from a label, with no third-party sound source."""
    patterns = {
        "FIGHT": (220, 330, 440), "WINS": (330, 440, 660),
        "PLAYER": (196, 262, 330), "A": (262, 330), "B": (294, 392),
        "C": (330, 440), "D": (349, 466),
        "BASTION": (196, 294, 392, 588), "HARRIER": (294, 392, 588, 784),
    }
    digest = hashlib.sha256(word.encode("ascii")).digest()
    notes = patterns.get(word, tuple(180 + digest[n] * 2 for n in range(3)))
    note_frames = MIX_RATE * 12 // 100
    samples = []
    for frequency in notes:
        for n in range(note_frames):
            # Integer triangle oscillator and a short envelope. Every sample is
            # authored by this formula; there are no sampled voices or instruments.
            phase = (n * frequency * 65536 // MIX_RATE) % 65536
            triangle = 32767 - abs(phase - 32768) * 2
            envelope = min(256, n * 256 // 220, (note_frames - 1 - n) * 256 // 440)
            samples.append(triangle * max(0, envelope) / (32768.0 * 256) * 0.6)
    return samples


def generate_cue(word: str, out: Path) -> None:
    write_wav(out, cue_samples(word))


def build(words: list[str], regenerate: bool) -> dict:
    record: dict = {
        "generator": GENERATOR,
        "voice": VOICE,
        "schema": "bytefray.spectator.announcer",
        "schema_version": 2,
        "kind": "nonverbal-procedural",
        "license": "MIT",
        "mix_rate": MIX_RATE,
        "settings": SETTINGS,
        "words": {},
    }
    previous = _load_record()
    words = words + [w for w in previous.get("words", {}) if w not in words]
    expected = {word: wav_bytes(cue_samples(word)) for word in words}
    # Preflight all inputs before changing any file. Existing arbitrary or legacy
    # speech bytes must never acquire procedural/MIT provenance by being reused.
    for word in words:
        raw = VOICE_DIR / "raw" / f"{word.lower()}.wav"
        if raw.is_file() and not regenerate and raw.read_bytes() != expected[word]:
            raise ValueError(f"{word}: raw bytes are not this original cue; use --regenerate to replace them")
    for word in words:
        name = word.lower()
        raw = VOICE_DIR / "raw" / f"{name}.wav"
        if regenerate or not raw.is_file():
            raw.parent.mkdir(parents=True, exist_ok=True)
            raw.write_bytes(expected[word])
        processed = VOICE_DIR / f"{name}.wav"
        write_wav(processed, process(read_wav(raw)))
        with wave.open(str(processed), "rb") as w:
            seconds = round(w.getnframes() / MIX_RATE, 4)
        record["words"][word] = {
            "text": word,
            "raw": f"raw/{name}.wav",
            "raw_sha256": sha256(raw),
            "file": f"{name}.wav",
            "sha256": sha256(processed),
            "seconds": seconds,
        }
    record["words"] = dict(sorted(record["words"].items()))
    (VOICE_DIR / "voice.json").write_text(json.dumps(record, indent=2, sort_keys=True) + "\n", encoding="ascii", newline="\n")
    return record


def _load_record() -> dict:
    path = VOICE_DIR / "voice.json"
    return json.loads(path.read_text(encoding="ascii")) if path.is_file() else {}


def check() -> list[str]:
    """Problems with voice.json and the clips: digests, and reprocessing equality."""
    record = _load_record()
    problems = []
    if (
        record.get("generator") != GENERATOR or record.get("settings") != SETTINGS
        or record.get("schema_version") != 2 or record.get("kind") != "nonverbal-procedural"
    ):
        problems.append("voice.json was made by other generator settings")
    for word, entry in record.get("words", {}).items():
        raw, processed = VOICE_DIR / entry["raw"], VOICE_DIR / entry["file"]
        if not raw.is_file() or not processed.is_file():
            problems.append(f"{word}: cue file missing")
            continue
        if raw.read_bytes() != wav_bytes(cue_samples(word)):
            problems.append(f"{word}: raw bytes do not reproduce from the original oscillator")
            continue
        if sha256(raw) != entry["raw_sha256"] or sha256(processed) != entry["sha256"]:
            problems.append(f"{word}: digest mismatch")
            continue
        samples = process(read_wav(raw))
        rendered = array("h", (round(max(-1.0, min(1.0, s)) * 32767) for s in samples)).tobytes()
        with wave.open(str(processed), "rb") as w:
            if w.readframes(w.getnframes()) != rendered:
                problems.append(f"{word}: processed clip does not reproduce from its raw clip")
    return problems


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--name", action="append", default=[], help="agent name to add an electronic motif for")
    parser.add_argument("--regenerate", action="store_true", help="regenerate every original raw cue")
    parser.add_argument("--check", action="store_true", help="only verify voice.json and the clips")
    args = parser.parse_args(argv)
    if args.check:
        problems = check()
        print("\n".join(problems) if problems else "arcade cues OK")
        return 1 if problems else 0
    record = build(vocabulary(args.name), args.regenerate)
    for word, entry in record["words"].items():
        print(f"{word:10} {entry['seconds']:.2f} s  {entry['sha256'][:12]}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
