"""Showcase agents (agents/spectator_*) use only legal Agent API v2 knowledge and actions.

Static checks read each agent's source; the live check plays one short match in
each seat order at a development seed (900001), outside the public candidate
seed range declared in docs/P0_SHOWCASE_SELECTION_PROTOCOL.md.
"""

from __future__ import annotations

import ast
import json
import os
import sys
from collections import Counter
from pathlib import Path

import pytest

EXPORTER = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(EXPORTER))

from run_match import run_match  # noqa: E402

ROOT = EXPORTER.parent
BYTEFRAY_ROOT = Path(os.environ.get("BYTEFRAY_ROOT", "D:/Projects/BATTLE2")).resolve()
AGENTS = {"harrier": ROOT / "agents" / "spectator_harrier", "bastion": ROOT / "agents" / "spectator_bastion"}
DEV_SEED = 900001
# Names an agent must never touch: hidden or seed-derived knowledge, I/O, process control.
FORBIDDEN_NAMES = {"seed", "visible_enemy_anchor_addresses", "open", "eval", "exec", "__import__", "globals"}


@pytest.mark.parametrize("name", sorted(AGENTS))
def test_agent_imports_only_the_agent_api(name: str) -> None:
    tree = ast.parse((AGENTS[name] / "agent.py").read_text(encoding="utf-8"))
    imported = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            imported.update(alias.name for alias in node.names)
        elif isinstance(node, ast.ImportFrom):
            imported.add(node.module)
    assert imported == {"__future__", "battle_engine.agent_api"}


@pytest.mark.parametrize("name", sorted(AGENTS))
def test_agent_never_touches_hidden_knowledge(name: str) -> None:
    tree = ast.parse((AGENTS[name] / "agent.py").read_text(encoding="utf-8"))
    used = {node.attr for node in ast.walk(tree) if isinstance(node, ast.Attribute)}
    used |= {node.id for node in ast.walk(tree) if isinstance(node, ast.Name)}
    assert not used & FORBIDDEN_NAMES
    # No literal arena addresses: every number is a small offset, count or byte constant.
    numbers = {node.value for node in ast.walk(tree) if isinstance(node, ast.Constant) and isinstance(node.value, int)}
    assert max(numbers) <= 0xFF


@pytest.mark.parametrize(("a", "b"), [("harrier", "bastion"), ("bastion", "harrier")])
def test_agents_play_legally_and_sense(tmp_path: Path, a: str, b: str) -> None:
    out = tmp_path / "match"
    run_match(BYTEFRAY_ROOT, AGENTS[a], AGENTS[b], DEV_SEED, out, ticks=150)
    result = json.loads((out / "result.json").read_text(encoding="utf-8"))
    assert all(entrant["diagnostic"] is None for entrant in result["entrants"])
    assert all(entrant["termination_reason"] in (None, "core_captured") for entrant in result["entrants"])
    statuses: Counter = Counter()
    positive: Counter = Counter()
    for line in (out / "trace.jsonl").open(encoding="utf-8"):
        record = json.loads(line)
        if record.get("record_type") != "decision_v2":
            continue
        assert record["observation"]["visible_enemy_anchor_addresses"] == []
        applied = record["applied_result"] or {}
        statuses[applied.get("status")] += 1
        if record["action"]["kind"] == "sense" and applied.get("sensed_anchors"):
            positive[record["agent_id"]] += 1
    assert set(statuses) == {"APPLIED"}
    assert positive["A"] and positive["B"]
