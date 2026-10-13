"""Bytefray-Spectator showcase agent -- Harrier (hunter-raider).

Strategy
    Harrier commits most of its actions to finding and capturing the opponent's
    core.

    Its ``hunter`` process sweeps SENSE windows across its reach, patrols the
    ring when a sweep comes back empty, and remembers every delivered contact
    with the tick it was sampled. On a fresh contact it closes in and READs the
    cells around it. A core is eight cells in a row that the opponent owns, so
    the first such run it reads (never Harrier's own core) becomes the target,
    and the hunter overwrites it cell by cell. During the raid it refreshes a
    SENSE window over the target and spends some writes on any enemy anchor it
    finds there, because a WRITE on an anchor disrupts that process. Every so
    often it READs a target cell; if the opponent never takes cells back, the
    run was not a defended core and the hunter goes back to searching.

    Its ``keeper`` process guards Harrier's own core: it rewrites the core in
    a freshly shuffled order every round, so a raider cannot predict which
    cell comes back next, and it hops at random between parking spots off
    both ends of the core so that a disrupting WRITE aimed where it was last
    sensed tends to miss.

What it may know
    Only Agent API v2 observations and its match context: its own anchors,
    reach and core, and the delayed results of its own READ and SENSE actions.
    It never uses the seed, the opponent's placement, replays or any hardcoded
    location. The context RNG only chooses the initial patrol direction and
    the keeper's repair order and parking spots.
"""

from __future__ import annotations

from battle_engine.agent_api import (
    ActionKindV2,
    AgentAction,
    MatchContextV2,
    ObservationV2,
    ProcessDeclaration,
)

CORE_SIZE = 8  # public Ruleset constant
SIGNATURE = 0x48
HUNTER_REACH = 96
KEEPER_REACH = 16
SWEEP_OFFSETS = (-81, -27, 27, 81)  # four abutting +/-27 windows: +/-108 around the anchor
STANDOFF = 24  # how far short of a target an approach stops
CONTACT_TTL = 40  # ticks a sampled contact is trusted
PROBE_SPAN = 12  # cells read on each side of a contact
RESCAN_EVERY = 6  # raid actions between SENSE refreshes over the target
GUARD_EVERY = 3  # at most one in this many raid actions disrupts a sensed guard
VERIFY_EVERY = 16  # raid actions between READs of a target cell
GIVE_UP_AFTER = 3  # consecutive verifications finding the cell still Harrier's
KEEPER_SPOTS = (-6, -4, 11, 13)  # parking offsets from the core base, off either end of the core
KEEPER_HOP_EVERY = 6  # keeper actions between hops


def circular_distance(a: int, b: int, arena: int) -> int:
    d = (a - b) % arena
    return min(d, arena - d)


def shortest_delta(target: int, anchor: int, arena: int) -> int:
    forward = (target - anchor) % arena
    return forward - arena if forward > arena // 2 else forward


def enemy_run(owned: dict[int, bool], arena: int) -> list[int] | None:
    """The first run of at least CORE_SIZE consecutive cells read as enemy-owned."""
    for start in sorted(owned):
        if not owned[start] or owned.get((start - 1) % arena):
            continue
        run = [start]
        while owned.get((run[-1] + 1) % arena) and len(run) < arena:
            run.append((run[-1] + 1) % arena)
        if len(run) >= CORE_SIZE:
            return run
    return None


def outward(centre: int, span: int, arena: int) -> list[int]:
    return [centre % arena] + [(centre + s * d) % arena for d in range(1, span + 1) for s in (1, -1)]


class Harrier:
    def __init__(self) -> None:
        self.arena = 0  # set from the match context by reset()
        self.me = ""
        self.rng = None
        self.direction = 1
        self.last: dict[str, tuple[str, int | None]] = {}  # process -> (kind, address)
        self.contacts: dict[int, int] = {}  # enemy anchor address -> tick it was sampled
        self.probes: list[int] = []
        self.owned: dict[int, bool] = {}  # probed cell -> read as enemy-owned
        self.target: list[int] | None = None  # the enemy core run being raided
        self.sweep = 0
        self.raid = 0
        self.still_mine = 0
        self.repairs: list[int] = []  # core offsets still to rewrite this round
        self.keeper_actions = 0
        self.keeper_spot = 0

    # -- Agent API -----------------------------------------------------------
    def reset(self, context: MatchContextV2) -> None:
        self.__init__()
        self.arena = context.arena_size
        self.me = context.agent_id
        self.rng = context.rng
        self.direction = 1 if context.rng.random() < 0.5 else -1

    def declare_processes(self) -> list[ProcessDeclaration]:
        return [
            ProcessDeclaration(id="hunter", reach=HUNTER_REACH, share=0.5),
            ProcessDeclaration(id="keeper", reach=KEEPER_REACH, share=0.5),
        ]

    def act(self, obs: ObservationV2) -> AgentAction:
        self._absorb(obs)
        action = self._keeper(obs) if obs.self_process_id == "keeper" else self._hunter(obs)
        kind = action.kind.value
        address = None if kind == "move" or action.operand is None else action.operand % self.arena
        self.last[obs.self_process_id] = (kind, address)
        return action

    # -- Knowledge -------------------------------------------------------------
    def _absorb(self, obs: ObservationV2) -> None:
        """Fold this process's delivered SENSE/READ result into shared memory."""
        kind, address = self.last.get(obs.self_process_id, ("", None))
        if kind == "sense" and obs.previous_sense_anchors is not None:
            for contact in obs.previous_sense_anchors:
                self.contacts[contact] = obs.previous_action_tick
        if kind == "read" and address is not None and obs.previous_action_applied:
            enemy = obs.previous_read_owner not in (None, self.me)
            if self.target is not None and address in self.target:
                self.still_mine = 0 if enemy else self.still_mine + 1
                if self.still_mine >= GIVE_UP_AFTER:  # nobody defends it: not a live core
                    self.target, self.still_mine = None, 0
            elif self.target is None:
                own = {(obs.own_core_base + i) % self.arena for i in range(obs.own_core_size)}
                self.owned[address] = enemy and address not in own
                run = enemy_run(self.owned, self.arena)
                if run is not None:
                    self.target, self.probes, self.owned = run, [], {}
        horizon = obs.current_tick - CONTACT_TTL
        self.contacts = {a: t for a, t in self.contacts.items() if t >= horizon}

    def _by_freshness(self, obs: ObservationV2) -> list[int]:
        return sorted(
            self.contacts,
            key=lambda a: (-self.contacts[a], circular_distance(a, obs.self_anchor, self.arena)),
        )

    def _in_reach(self, obs: ObservationV2, address: int) -> bool:
        return circular_distance(address, obs.self_anchor, self.arena) <= obs.self_reach

    def _approach(self, obs: ObservationV2, target: int) -> AgentAction:
        delta = shortest_delta(target, obs.self_anchor, self.arena)
        size = max(1, min(64, abs(delta) - STANDOFF))
        return AgentAction(ActionKindV2.MOVE, operand=size if delta >= 0 else -size)

    # -- Keeper: rewrite the core in shuffled rounds, hopping between spots ---
    def _keeper(self, obs: ObservationV2) -> AgentAction:
        self.keeper_actions += 1
        if self.keeper_actions % KEEPER_HOP_EVERY == 0:
            self.keeper_spot = self.rng.choice([i for i in range(len(KEEPER_SPOTS)) if i != self.keeper_spot])
        spot = (obs.own_core_base + KEEPER_SPOTS[self.keeper_spot]) % self.arena
        if obs.self_anchor != spot:
            return AgentAction(ActionKindV2.MOVE, operand=shortest_delta(spot, obs.self_anchor, self.arena))
        if not self.repairs:
            self.repairs = list(range(obs.own_core_size))
            self.rng.shuffle(self.repairs)
        cell = (obs.own_core_base + self.repairs.pop()) % self.arena
        return AgentAction(ActionKindV2.WRITE, operand=cell, value=SIGNATURE)

    # -- Hunter ----------------------------------------------------------------
    def _hunter(self, obs: ObservationV2) -> AgentAction:
        if self.target is not None:
            return self._raid(obs)
        if self.probes:
            probe = self.probes[0]
            if not self._in_reach(obs, probe):
                return self._approach(obs, probe)
            self.probes.pop(0)
            return AgentAction(ActionKindV2.READ, operand=probe)
        contacts = self._by_freshness(obs)
        if contacts:
            contact = contacts[0]
            if circular_distance(contact, obs.self_anchor, self.arena) > obs.self_reach - PROBE_SPAN:
                return self._approach(obs, contact)
            # A guarding process stands beside its core: read everything around it.
            self.contacts.pop(contact)
            self.owned = {}
            self.probes = outward(contact, PROBE_SPAN, self.arena)
            return self._hunter(obs)
        return self._search(obs)

    def _search(self, obs: ObservationV2) -> AgentAction:
        if self.sweep == len(SWEEP_OFFSETS):
            self.sweep = 0
            return AgentAction(ActionKindV2.MOVE, operand=64 * self.direction)
        offset = SWEEP_OFFSETS[self.sweep]
        self.sweep += 1
        return AgentAction(ActionKindV2.SENSE, operand=(obs.self_anchor + offset) % self.arena)

    def _raid(self, obs: ObservationV2) -> AgentAction:
        assert self.target is not None
        centre = self.target[len(self.target) // 2]
        if max(circular_distance(c, obs.self_anchor, self.arena) for c in self.target) > obs.self_reach:
            return self._approach(obs, centre)
        self.raid += 1
        if self.raid % RESCAN_EVERY == 0:
            return AgentAction(ActionKindV2.SENSE, operand=centre)
        if self.raid % VERIFY_EVERY == 0:
            return AgentAction(ActionKindV2.READ, operand=self.target[self.raid // VERIFY_EVERY % len(self.target)])
        guards = [a for a in self._by_freshness(obs) if self._in_reach(obs, a)]
        if guards and self.raid % GUARD_EVERY == 0:
            self.contacts.pop(guards[0])
            return AgentAction(ActionKindV2.WRITE, operand=guards[0], value=SIGNATURE)
        return AgentAction(ActionKindV2.WRITE, operand=self.target[self.raid % len(self.target)], value=SIGNATURE)


def create_agent() -> Harrier:
    return Harrier()
