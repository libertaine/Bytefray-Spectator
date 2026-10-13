"""Test-only differential opponent whose hidden step count differs.

"main" stays on the entrant's anchor exactly like a one-process stationary
opponent. "decoy" moves once, 64 cells backwards, then reads, so it sits
where Window Scout (starting 91 cells behind) never scans. When the scout
writes on the shared anchor and disrupts "main", the decoy keeps taking this
entrant's actions, so the opponent's decisions per tick (the omniscient
timing) differ from a one-process opponent's while the scout's delivered
samples stay the same.
"""

from __future__ import annotations

from battle_engine.agent_api import ActionKindV2, AgentAction, MatchContextV2, ObservationV2, ProcessDeclaration


class SplitOpponent:
    def __init__(self) -> None:
        self.parked = False

    def reset(self, context: MatchContextV2) -> None:
        self.parked = False

    def declare_processes(self) -> list[ProcessDeclaration]:
        return [
            ProcessDeclaration(id="main", reach=128, share=0.5),
            ProcessDeclaration(id="decoy", reach=128, share=0.5),
        ]

    def act(self, observation: ObservationV2) -> AgentAction:
        if observation.self_process_id == "decoy" and not self.parked:
            self.parked = True
            return AgentAction(ActionKindV2.MOVE, operand=-64)
        return AgentAction(ActionKindV2.READ, operand=observation.own_core_base)


def create_agent() -> SplitOpponent:
    return SplitOpponent()
