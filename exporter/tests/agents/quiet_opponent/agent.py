"""Test-only differential opponent: one stationary process that reads its own core."""

from __future__ import annotations

from battle_engine.agent_api import ActionKindV2, AgentAction, MatchContextV2, ObservationV2, ProcessDeclaration


class QuietOpponent:
    def reset(self, context: MatchContextV2) -> None:
        pass

    def declare_processes(self) -> list[ProcessDeclaration]:
        return [ProcessDeclaration(id="main", reach=128, share=1.0)]

    def act(self, observation: ObservationV2) -> AgentAction:
        return AgentAction(ActionKindV2.READ, operand=observation.own_core_base)


def create_agent() -> QuietOpponent:
    return QuietOpponent()
