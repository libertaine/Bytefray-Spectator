"""Render the existing Bytefray V6 sensing viewer at chosen ticks (P0-D baseline).

Read-only: it verifies the pinned Bytefray checkout, loads a match source
directory (replay.jsonl, trace.jsonl, result.json) exactly as the Bytefray CLI
does, and saves what the unmodified SensingReplayRenderer draws, offscreen via
SDL's dummy video driver, at its default window size:

    python exporter/capture_v6_viewer.py --bytefray-root D:/Projects/BATTLE2 \
        --source fixtures/showcase/source --out <dir> --ticks 1,12,477

With --record omniscient|agent_a --start <tick> --speed <x> it instead plays the
viewer from that tick to the recorded end and encodes an H.264 video (ffmpeg).

Writes <out>/v6-omniscient-tick-<n>.png and <out>/v6-agent_a-tick-<n>.png, plus
capture.json (pin record, viewer text at each capture and playback pacing).
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path

os.environ["SDL_VIDEODRIVER"] = "dummy"
os.environ["PYGAME_HIDE_SUPPORT_PROMPT"] = "1"

from spectator_export import DEFAULT_PIN, _import_bytefray, canonical_json, sha256_file, verify_pin  # noqa: E402

WINDOW = (1100, 750)  # SensingReplayRenderer's default window size


def capture(bytefray_root: Path, source: Path, out: Path, ticks: list[int]) -> dict:
    pin_record = verify_pin(bytefray_root, json.loads(DEFAULT_PIN.read_text(encoding="utf-8")))
    _import_bytefray(bytefray_root)
    import pygame
    from battle_client.player import DEFAULT_SPEED_INDEX, DEFAULT_TICK_INTERVAL, SPEEDS
    from battle_client.renderers.sensing_renderer import SensingReplayRenderer
    from battle_client.sensing import SensingView
    from battle_client.sensing_presentation import load_sensing_presentation
    from battle_client.session import ReplaySession

    replay = source / "replay.jsonl"
    session = ReplaySession()
    session.load(replay)
    presentation, reason = load_sensing_presentation(
        session, replay, source / "trace.jsonl", result=source / "result.json", interval=DEFAULT_TICK_INTERVAL
    )
    if presentation is None:
        raise SystemExit(f"V6 viewer refused the source: {reason}")
    out.mkdir(parents=True, exist_ok=True)
    renderer = SensingReplayRenderer()
    renderer.pg = pygame
    pygame.init()
    try:
        renderer.screen = pygame.display.set_mode(WINDOW)
        renderer.font = pygame.font.SysFont("consolas", 15)
        shots = []
        pacing = {}
        for name, entrant in (("omniscient", False), ("agent_a", True)):
            presentation.switch(entrant)
            positions = len(presentation.controller.positions)
            seconds = positions * DEFAULT_TICK_INTERVAL / SPEEDS[DEFAULT_SPEED_INDEX]
            pacing[name] = {"phase_positions": positions, "default_full_playback_seconds": round(seconds, 1)}
            for tick in ticks:
                presentation.seek_relative(tick - presentation.position.tick)
                renderer.draw(presentation)
                path = out / f"v6-{name}-tick-{tick:04d}.png"
                pygame.image.save(renderer.screen, str(path))
                view = presentation.current_view
                shots.append(
                    {
                        "file": path.name,
                        "perspective": name,
                        "requested_tick": tick,
                        "shown_tick": presentation.position.tick,
                        "phase": presentation.position.phase.value,
                        "entrant_view": isinstance(view, SensingView),
                        "terminal_text": presentation.terminal_text,
                        "side_lines": list(renderer.last_lines),
                        "sha256": sha256_file(path),
                    }
                )
    finally:
        pygame.quit()
    record = {
        "schema": "bytefray.spectator.v6_viewer_capture",
        "schema_version": 1,
        "bytefray": pin_record,
        "renderer": "battle_client.renderers.sensing_renderer.SensingReplayRenderer.draw",
        "window": list(WINDOW),
        "source": {name: sha256_file(source / name) for name in ("replay.jsonl", "trace.jsonl", "result.json")},
        "pacing": {
            "tick_interval_seconds": DEFAULT_TICK_INTERVAL,
            "default_speed": SPEEDS[DEFAULT_SPEED_INDEX],
            "speeds": list(SPEEDS),
            **pacing,
        },
        "captures": shots,
    }
    (out / "capture.json").write_bytes(canonical_json(record))
    return record


def record_video(
    bytefray_root: Path, source: Path, out: Path, *, perspective: str, start: int, speed: float, fps: int, ffmpeg: str
) -> dict:
    """Play the V6 viewer from tick `start` to the recorded end at `speed`, as an H.264 video.

    The viewer's own controller is advanced by exactly 1/fps per frame, so the
    recording is deterministic; one extra second is held at the end.
    """
    verify_pin(bytefray_root, json.loads(DEFAULT_PIN.read_text(encoding="utf-8")))
    _import_bytefray(bytefray_root)
    import pygame
    from battle_client.player import DEFAULT_TICK_INTERVAL
    from battle_client.renderers.sensing_renderer import SensingReplayRenderer
    from battle_client.sensing_presentation import load_sensing_presentation
    from battle_client.session import ReplaySession

    replay = source / "replay.jsonl"
    session = ReplaySession()
    session.load(replay)
    presentation, reason = load_sensing_presentation(
        session, replay, source / "trace.jsonl", result=source / "result.json", interval=DEFAULT_TICK_INTERVAL
    )
    if presentation is None:
        raise SystemExit(f"V6 viewer refused the source: {reason}")
    out.parent.mkdir(parents=True, exist_ok=True)
    renderer = SensingReplayRenderer()
    renderer.pg = pygame
    pygame.init()
    encoder = subprocess.Popen(
        [
            ffmpeg,
            "-loglevel",
            "error",
            "-y",
            "-f",
            "rawvideo",
            "-pix_fmt",
            "rgb24",
            "-s",
            f"{WINDOW[0]}x{WINDOW[1]}",
            "-r",
            str(fps),
            "-i",
            "-",
            "-c:v",
            "libx264",
            "-preset",
            "slow",
            "-crf",
            "28",
            "-pix_fmt",
            "yuv420p",
            str(out),
        ],
        stdin=subprocess.PIPE,
    )
    frames = 0
    try:
        renderer.screen = pygame.display.set_mode(WINDOW)
        renderer.font = pygame.font.SysFont("consolas", 15)
        presentation.switch(perspective == "agent_a")
        presentation.seek_relative(start - presentation.position.tick)
        presentation.controller.set_speed(speed)
        presentation.controller.play()
        hold = fps
        while hold > 0:
            if not presentation.controller.playing:
                hold -= 1
            presentation.controller.update(1 / fps)
            renderer.draw(presentation)
            encoder.stdin.write(pygame.image.tobytes(renderer.screen, "RGB"))
            frames += 1
    finally:
        encoder.stdin.close()
        encoder.wait()
        pygame.quit()
    if encoder.returncode:
        raise SystemExit(f"ffmpeg failed ({encoder.returncode})")
    return {
        "file": out.name,
        "perspective": perspective,
        "start_tick": start,
        "speed": speed,
        "fps": fps,
        "frames": frames,
        "seconds": round(frames / fps, 2),
        "sha256": sha256_file(out),
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--bytefray-root", type=Path, required=True)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True, help="output dir (screenshots) or .mp4 file (--record)")
    parser.add_argument("--ticks", help="comma-separated ticks to capture")
    parser.add_argument("--record", choices=("omniscient", "agent_a"), help="record a video in this perspective")
    parser.add_argument("--start", type=int, default=0, help="--record: first tick")
    parser.add_argument("--speed", type=float, default=1.0, help="--record: the viewer's speed multiplier")
    parser.add_argument("--fps", type=int, default=30)
    parser.add_argument("--ffmpeg", default="ffmpeg")
    args = parser.parse_args(argv)
    root, source, out = args.bytefray_root.resolve(), args.source.resolve(), args.out.resolve()
    if args.record:
        video = record_video(
            root, source, out, perspective=args.record, start=args.start, speed=args.speed, fps=args.fps, ffmpeg=args.ffmpeg
        )
        print(json.dumps(video, indent=2))
        return 0
    if not args.ticks:
        parser.error("--ticks or --record is required")
    record = capture(root, source, out, [int(t) for t in args.ticks.split(",")])
    print(json.dumps(record["pacing"], indent=2))
    print(f"{len(record['captures'])} captures written to {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
