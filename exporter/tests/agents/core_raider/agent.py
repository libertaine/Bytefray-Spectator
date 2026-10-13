"""Test-only raider for a short decisive match; not a showcase agent.

The tests place it 91 cells behind a stationary opponent, so the cells it
overwrites are that opponent's core. It exists only to exercise outcome
verification and the agent view of a match that ends before its tick limit.
"""

from __future__ import annotations

from battle_engine.agent_api import ActionKindV2, AgentAction, MatchContextV2, ObservationV2, ProcessDeclaration

OFFSET = 91


class CoreRaider:
    def __init__(self) -> None:
        self.arena = 512
        self.calls = 0

    def reset(self, context: MatchContextV2) -> None:
        self.arena = context.arena_size
        self.calls = 0

    def declare_processes(self) -> list[ProcessDeclaration]:
        return [ProcessDeclaration(id="main", reach=128, share=1.0)]

    def act(self, observation: ObservationV2) -> AgentAction:
        target = (observation.self_anchor + OFFSET + self.calls % 8) % self.arena
        self.calls += 1
        return AgentAction(ActionKindV2.WRITE, operand=target, value=0x52)


def create_agent() -> CoreRaider:
    return CoreRaider()
