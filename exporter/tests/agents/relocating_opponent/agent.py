"""Test-only positive control: one relocation, then a stationary core reader.

Window Scout's first scan is centred on the stationary cell and every later
scan on a cell 64 further along, so whichever runs first, a relocated anchor
changes what the scout's samples return.
"""

from __future__ import annotations

from battle_engine.agent_api import ActionKindV2, AgentAction, MatchContextV2, ObservationV2, ProcessDeclaration


class RelocatingOpponent:
    def __init__(self) -> None:
        self.moved = False

    def reset(self, context: MatchContextV2) -> None:
        self.moved = False

    def declare_processes(self) -> list[ProcessDeclaration]:
        return [ProcessDeclaration(id="main", reach=128, share=1.0)]

    def act(self, observation: ObservationV2) -> AgentAction:
        if not self.moved:
            self.moved = True
            return AgentAction(ActionKindV2.MOVE, operand=64)
        return AgentAction(ActionKindV2.READ, operand=observation.own_core_base)


def create_agent() -> RelocatingOpponent:
    return RelocatingOpponent()
