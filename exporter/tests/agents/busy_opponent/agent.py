"""Test-only differential opponent: lots of activity, none of it observable by the other side.

Two processes share the entrant's single anchor cell and never move, so any
sensing sample of this entrant returns exactly what a one-process stationary
opponent would return. Every write lands in this entrant's own core, and every
SENSE (which the sensed side never learns about) is aimed away from the anchor.
"""

from __future__ import annotations

from battle_engine.agent_api import ActionKindV2, AgentAction, MatchContextV2, ObservationV2, ProcessDeclaration


class BusyOpponent:
    def __init__(self) -> None:
        self.arena = 512
        self.calls = 0

    def reset(self, context: MatchContextV2) -> None:
        self.arena = context.arena_size
        self.calls = 0

    def declare_processes(self) -> list[ProcessDeclaration]:
        return [
            ProcessDeclaration(id="left", reach=128, share=0.5),
            ProcessDeclaration(id="right", reach=128, share=0.5),
        ]

    def act(self, observation: ObservationV2) -> AgentAction:
        self.calls += 1
        cell = (observation.own_core_base + self.calls % observation.own_core_size) % self.arena
        match self.calls % 3:
            case 0:
                return AgentAction(ActionKindV2.WRITE, operand=cell, value=self.calls & 0xFF)
            case 1:
                return AgentAction(ActionKindV2.SENSE, operand=(observation.self_anchor - 100) % self.arena)
            case _:
                return AgentAction(ActionKindV2.READ, operand=cell)


def create_agent() -> BusyOpponent:
    return BusyOpponent()
