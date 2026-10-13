"""Generate the arcade announcer's voice clips (audio/announcer/).

Offline, two steps:

1. **Speech.** Each word is spoken once by a Windows SAPI voice
   (``announcer_sapi.ps1``, 22050 Hz 16-bit mono) into ``raw/<word>.wav``.
   SAPI gives the same bytes for the same voice and text. A raw clip that
   already exists is reused unless ``--resynthesize`` is given, so the clips
   can be reprocessed on a machine without the voice.
2. **Announcer processing.** Pure Python with no randomness, so the processed
   ``<word>.wav`` is a pure function of the raw clip. The steps are: trim;
   drop the pitch by resampling (deeper and slower); a soft-square
   low-frequency amplitude buzz (gravel); overdrive; bit-crushing (arcade
   lo-fi); optional sample-and-hold and echo; low-pass; normalise.

``voice.json`` records the voice, the settings and both digests of every
word. The viewer verifies each clip against it, and plays nothing that does
not verify. The viewer never runs speech synthesis and needs no network.

The vocabulary is FIGHT, WINS, PLAYER, the seat letters A-D, and the spoken
name of every agent under ``agents/`` (see ``spoken_words``). Add a future
agent's name with ``--name <agent name>``.

Intelligibility is judged by listening (docs/ANNOUNCER_LISTENING_EVALUATION_01.md).

Usage::

    python exporter/make_announcer_voice.py                      # reuse raw clips, reprocess
    python exporter/make_announcer_voice.py --resynthesize       # speak every word again (Windows)
    python exporter/make_announcer_voice.py --name spectator_new_agent
    python exporter/make_announcer_voice.py --check              # verify voice.json and the clips
"""

from __future__ import annotations

import sys

sys.dont_write_bytecode = True

import argparse  # noqa: E402
import hashlib  # noqa: E402
import json  # noqa: E402
import math  # noqa: E402
import re  # noqa: E402
import subprocess  # noqa: E402
import wave  # noqa: E402
from array import array  # noqa: E402
from pathlib import Path  # noqa: E402

SPECTATOR_ROOT = Path(__file__).resolve().parents[1]
VOICE_DIR = SPECTATOR_ROOT / "audio" / "announcer"
AGENTS = SPECTATOR_ROOT / "agents"
SAPI = Path(__file__).resolve().parent / "announcer_sapi.ps1"

GENERATOR = "spectator-announcer-voice-v1"
VOICE = "Microsoft David Desktop"
MIX_RATE = 22050
SSML_RATE = "-10%"
SSML_PITCH = "x-low"
BASE_WORDS = ("FIGHT", "WINS", "PLAYER", "A", "B", "C", "D")
# What the voice is given to say for a word, where the word alone is read badly.
SPOKEN_TEXT = {"FIGHT": "Fight!", "WINS": "wins!", "A": "Ay", "B": "Bee", "C": "See", "D": "Dee"}

# Processing settings (recorded in voice.json). A deeper resample, sample-and-hold
# and an echo were tried and dropped as costing clarity; listening decides.
SETTINGS = {
    "trim_threshold": 0.004,  # trims only true silence: a soft onset (the f of FIGHT) is kept
    "trim_pad": 0.03,  # seconds kept either side
    "pitch": 0.92,  # resampling factor: 0.92 plays 8% lower and slower (SSML already speaks x-low)
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
    """Spoken name of an agent: its name split on '_', '-' and spaces, upper case,
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


def write_wav(path: Path, samples: list[float]) -> None:
    data = array("h", (round(max(-1.0, min(1.0, s)) * 32767) for s in samples))
    if sys.byteorder == "big":
        data.byteswap()
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(MIX_RATE)
        w.writeframes(data.tobytes())


def process(raw: list[float]) -> list[float]:
    """The announcer voice: a pure function of the raw clip."""
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


def synthesize(word: str, out: Path) -> None:
    out.parent.mkdir(parents=True, exist_ok=True)
    text = SPOKEN_TEXT.get(word, word.capitalize())
    command = ["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(SAPI)]
    command += ["-Voice", VOICE, "-Text", text, "-Out", str(out), "-Rate", SSML_RATE, "-Pitch", SSML_PITCH]
    subprocess.run(command, check=True, capture_output=True, text=True)


def build(words: list[str], resynthesize: bool) -> dict:
    record: dict = {
        "generator": GENERATOR,
        "voice": VOICE,
        "ssml": {"rate": SSML_RATE, "pitch": SSML_PITCH},
        "mix_rate": MIX_RATE,
        "settings": SETTINGS,
        "words": {},
    }
    previous = _load_record()
    for word in words + [w for w in previous.get("words", {}) if w not in words]:
        name = word.lower()
        raw = VOICE_DIR / "raw" / f"{name}.wav"
        if resynthesize or not raw.is_file():
            synthesize(word, raw)
        processed = VOICE_DIR / f"{name}.wav"
        write_wav(processed, process(read_wav(raw)))
        with wave.open(str(processed), "rb") as w:
            seconds = round(w.getnframes() / MIX_RATE, 4)
        record["words"][word] = {
            "text": SPOKEN_TEXT.get(word, word.capitalize()),
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
    if record.get("generator") != GENERATOR or record.get("settings") != SETTINGS:
        problems.append("voice.json was made by other generator settings")
    for word, entry in record.get("words", {}).items():
        raw, processed = VOICE_DIR / entry["raw"], VOICE_DIR / entry["file"]
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
    parser.add_argument("--name", action="append", default=[], help="agent name to add a spoken name for")
    parser.add_argument("--resynthesize", action="store_true", help="speak every word again with SAPI")
    parser.add_argument("--check", action="store_true", help="only verify voice.json and the clips")
    args = parser.parse_args(argv)
    if args.check:
        problems = check()
        print("\n".join(problems) if problems else "announcer voice OK")
        return 1 if problems else 0
    record = build(vocabulary(args.name), args.resynthesize)
    for word, entry in record["words"].items():
        print(f"{word:10} {entry['seconds']:.2f} s  {entry['sha256'][:12]}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
