"""Bytefray-Spectator showcase agent -- Bastion (warden and raider).

Strategy
    Bastion splits its actions evenly between defending and expanding.

    Its ``warden`` process stands beside Bastion's core and rewrites it cell
    by cell, keeps SENSE windows over and around the core, and when a sampled
    intruder anchor is within reach and still fresh it WRITEs on that cell,
    which disrupts the intruding process. After each such hit, and
    periodically anyway, it moves to another spot off either end of the core,
    chosen at random, because a raider that sensed it will try the same
    trick.

    Its ``raider`` process walks the ring claiming territory with its
    signature byte and scanning ahead and behind. When a scan delivers a
    contact away from home it moves in and READs the cells around it. A core
    is eight cells in a row that the opponent owns, so the first such run it
    reads (never Bastion's own core) becomes the target, and the raider
    overwrites it, hitting any guard it senses there. Every so often it READs
    a target cell; if the opponent never takes cells back, the run was not a
    defended core and the raider resumes exploring.

What it may know
    Only Agent API v2 observations and its match context: its own anchors,
    reach and core, and the delayed results of its own READ and SENSE actions.
    It never uses the seed, the opponent's placement, replays or any hardcoded
    location. The context RNG only chooses the raider's initial heading and
    the warden's standing spots.
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
SIGNATURE = 0xB5
WARDEN_REACH = 56
RAIDER_REACH = 112
WARDEN_SPOTS = (-9, -5, 12, 16)  # standing offsets from the core base, off either end of the core
WATCH_OFFSETS = (0, -40, 0, 40)  # warden SENSE centres relative to the core's middle
WATCH_EVERY = 3  # every third routine warden action is a SENSE
WARDEN_HOP_EVERY = 10  # warden actions between routine hops
INTRUDER_TTL = 2  # ticks a sampled intruder is worth a disrupting WRITE
EXPLORE = ("sense-ahead", "claim", "sense-behind", "claim", "move")
STEP = 48  # raider stride while exploring
STANDOFF = 30
HOME_RADIUS = 40  # contacts this close to Bastion's own core are left to the warden
CONTACT_TTL = 40
PROBE_SPAN = 12
RESCAN_EVERY = 5
GUARD_EVERY = 2
VERIFY_EVERY = 12
GIVE_UP_AFTER = 3


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


class Bastion:
    def __init__(self) -> None:
        self.arena = 0  # set from the match context by reset()
        self.me = ""
        self.heading = 1
        self.rng = None
        self.last: dict[str, tuple[str, int | None]] = {}  # process -> (kind, address)
        self.contacts: dict[int, int] = {}  # enemy anchor address -> tick it was sampled
        # warden
        self.spot = 0
        self.warden_actions = 0
        self.watch = 0
        self.repair = 0
        # raider
        self.explore = 0
        self.claimed = 0
        self.probes: list[int] = []
        self.owned: dict[int, bool] = {}  # probed cell -> read as enemy-owned
        self.target: list[int] | None = None
        self.raid = 0
        self.still_mine = 0

    # -- Agent API -----------------------------------------------------------
    def reset(self, context: MatchContextV2) -> None:
        self.__init__()
        self.arena = context.arena_size
        self.me = context.agent_id
        self.rng = context.rng
        self.heading = 1 if context.rng.random() < 0.5 else -1

    def declare_processes(self) -> list[ProcessDeclaration]:
        return [
            ProcessDeclaration(id="warden", reach=WARDEN_REACH, share=0.5),
            ProcessDeclaration(id="raider", reach=RAIDER_REACH, share=0.5),
        ]

    def act(self, obs: ObservationV2) -> AgentAction:
        self._absorb(obs)
        action = self._warden(obs) if obs.self_process_id == "warden" else self._raider(obs)
        kind = action.kind.value
        address = None if kind == "move" or action.operand is None else action.operand % self.arena
        self.last[obs.self_process_id] = (kind, address)
        return action

    # -- Knowledge -------------------------------------------------------------
    def _absorb(self, obs: ObservationV2) -> None:
        kind, address = self.last.get(obs.self_process_id, ("", None))
        if kind == "sense" and obs.previous_sense_anchors is not None:
            for contact in obs.previous_sense_anchors:
                self.contacts[contact] = obs.previous_action_tick
        if kind == "read" and address is not None and obs.previous_action_applied:  # only the raider READs
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

    def _in_reach(self, obs: ObservationV2, address: int) -> bool:
        return circular_distance(address, obs.self_anchor, self.arena) <= obs.self_reach

    def _approach(self, obs: ObservationV2, target: int) -> AgentAction:
        delta = shortest_delta(target, obs.self_anchor, self.arena)
        size = max(1, min(64, abs(delta) - STANDOFF))
        return AgentAction(ActionKindV2.MOVE, operand=size if delta >= 0 else -size)

    def _by_freshness(self, obs: ObservationV2) -> list[int]:
        return sorted(
            self.contacts,
            key=lambda a: (-self.contacts[a], circular_distance(a, obs.self_anchor, self.arena)),
        )

    # -- Warden ----------------------------------------------------------------
    def _warden(self, obs: ObservationV2) -> AgentAction:
        self.warden_actions += 1
        if self.warden_actions % WARDEN_HOP_EVERY == 0:
            self._hop()
        spot = (obs.own_core_base + WARDEN_SPOTS[self.spot]) % self.arena
        if obs.self_anchor != spot:
            return AgentAction(ActionKindV2.MOVE, operand=shortest_delta(spot, obs.self_anchor, self.arena))
        fresh = [
            a for a in self._by_freshness(obs) if obs.current_tick - self.contacts[a] <= INTRUDER_TTL and self._in_reach(obs, a)
        ]
        if fresh:
            self.contacts.pop(fresh[0])
            self._hop()  # expect retaliation where the intruder sensed the warden
            return AgentAction(ActionKindV2.WRITE, operand=fresh[0], value=SIGNATURE)
        self.watch += 1
        if self.watch % WATCH_EVERY == 0:
            middle = (obs.own_core_base + obs.own_core_size // 2) % self.arena
            centre = (middle + WATCH_OFFSETS[self.watch // WATCH_EVERY % len(WATCH_OFFSETS)]) % self.arena
            return AgentAction(ActionKindV2.SENSE, operand=centre)
        self.repair += 1
        cell = (obs.own_core_base + self.repair % obs.own_core_size) % self.arena
        return AgentAction(ActionKindV2.WRITE, operand=cell, value=SIGNATURE)

    def _hop(self) -> None:
        self.spot = self.rng.choice([i for i in range(len(WARDEN_SPOTS)) if i != self.spot])

    # -- Raider ----------------------------------------------------------------
    def _raider(self, obs: ObservationV2) -> AgentAction:
        if self.target is not None:
            return self._raid(obs)
        if self.probes:
            probe = self.probes[0]
            if not self._in_reach(obs, probe):
                return self._approach(obs, probe)
            self.probes.pop(0)
            return AgentAction(ActionKindV2.READ, operand=probe)
        # Contacts sitting on Bastion's own core are intruders: the warden's job.
        home = (obs.own_core_base + obs.own_core_size // 2) % self.arena
        away = [a for a in self._by_freshness(obs) if circular_distance(a, home, self.arena) > HOME_RADIUS]
        if away:
            contact = away[0]
            if circular_distance(contact, obs.self_anchor, self.arena) > obs.self_reach - PROBE_SPAN:
                return self._approach(obs, contact)
            self.contacts.pop(contact)
            self.owned = {}
            self.probes = outward(contact, PROBE_SPAN, self.arena)
            return self._raider(obs)
        return self._explore(obs)

    def _explore(self, obs: ObservationV2) -> AgentAction:
        step = EXPLORE[self.explore % len(EXPLORE)]
        self.explore += 1
        if step == "move":
            return AgentAction(ActionKindV2.MOVE, operand=STEP * self.heading)
        if step == "claim":
            self.claimed += 1
            cell = (obs.self_anchor + self.heading * (self.claimed % 16) * 3) % self.arena
            return AgentAction(ActionKindV2.WRITE, operand=cell, value=SIGNATURE)
        ahead = 1 if step == "sense-ahead" else -1
        return AgentAction(ActionKindV2.SENSE, operand=(obs.self_anchor + ahead * self.heading * 84) % self.arena)

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


def create_agent() -> Bastion:
    return Bastion()
