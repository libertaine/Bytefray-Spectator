extends RefCounted
## Broadcast-only transient effects, core status, tactical turning points and
## tick summaries, derived from the recorded broadcast.json frames. The Agent A
## perspective never uses this model.
##
## Every query is a pure function of the frame index. An effect is shown at
## index i only if its recorded frame is at or before i, so nothing can show a
## future event, and only while it is younger than EFFECT_TICKS ticks. Seeking,
## restarting or switching perspective therefore rebuilds exactly the same
## effects, and nothing stale can survive a jump.
##
## Nothing is simulated. A SENSE sample's contents are the recorded `sensed`
## anchors of its ACTION frame. Its delivery is the recorded `sensed` field of
## the same process's next OBSERVATION frame. READ discoveries come from the
## recorded cell owners and core ranges at the READ frame. Ownership changes are
## the recorded owner_changes, a disruption is the recorded tick-end `disrupted`
## set and an elimination is the recorded `alive` set. The only rule constant is
## the ruleset's public SENSE half-width, used to draw the sampled window; the
## exporter tests check it against the pinned Bytefray ruleset.

const PHASE_OBSERVATION := 0
const PHASE_ACTION := 1
const PHASE_TICK_END := 2
const EFFECT_TICKS := 3
const TURNING_POINT_LIMIT := 6
## Public SENSE half-width per ruleset (Bytefray RulesetPolicy.sensing_window).
const SENSE_HALF_WIDTH := {"bytefray-rules-6-alpha1": 27}

var half_width := -1
var actions: Array = []  # one record per recorded action, in frame order
var tick_events: Array = []  # one record per TICK_END frame with a disruption or elimination

var _model  # BroadcastModel
var _action_frames := PackedInt32Array()
var _sense_actions := PackedInt32Array()  # indexes into `actions`
var _sense_frames := PackedInt32Array()
var _sense_span := 0  # longest frame span from a SENSE to its delivery (or the end)
var _tick_event_frames := PackedInt32Array()
var _core_at_tick_end: Dictionary = {}  # tick -> PackedInt32Array of core cells held per entrant
var _delivery_frames: Dictionary = {}  # OBSERVATION frame index -> SENSE action record
var _turning_points: Array = []  # ordered milestone records {"i", "t", "entrant", "actor", "kind", "text"}
var _turning_point_frames := PackedInt32Array()


func _init(model) -> void:
	_model = model
	half_width = int(SENSE_HALF_WIDTH.get(model.ruleset_id, -1))
	var frames: Array = model.frames
	var cells: int = model.arena_size
	var entrant_count: int = model.entrants.size()
	var core_of := PackedInt32Array()
	core_of.resize(cells)
	core_of.fill(-1)
	var core_base := PackedInt32Array()
	core_base.resize(entrant_count)
	core_base.fill(-1)
	var last_core_read: Array = []
	var seen_enemy_read: Array = []
	var seen_enemy_core_owner: Array = []
	for e in entrant_count:
		var core_cells: Array = model.entrants[e]["core"]
		if not core_cells.is_empty():
			core_base[e] = int(core_cells[0])
		var own_core_state := {}
		for cell in core_cells:
			core_of[int(cell)] = e
			own_core_state[int(cell)] = e
		last_core_read.append(own_core_state)
		seen_enemy_read.append({})
		seen_enemy_core_owner.append({})
	var owners := PackedInt32Array()
	owners.resize(cells)
	owners.fill(-1)
	var pending: Dictionary = {}  # "entrant/process" -> SENSE action record
	var deployed: Dictionary = {}  # "entrant/process" -> true after first move off core_base
	var had_deployment: Dictionary = {}  # entrant index -> true
	var had_contact: Dictionary = {}  # actor id -> true
	var active_contacts: Dictionary = {}  # actor id -> Dictionary (address -> true)
	var had_core_damage: Dictionary = {}  # core owner index -> true
	var in_critical: Dictionary = {}  # core owner index -> true
	var last_recovery_tick: Dictionary = {}  # core owner index -> tick
	var previous_disrupted: Array = []
	for i in frames.size():
		var frame: Dictionary = frames[i]
		var phase := int(frame["p"])
		var before := -1
		if phase == PHASE_ACTION and frame["address"] != null:
			before = owners[int(frame["address"]) % cells]
		if i == 0:
			var full: Array = frame["owners"]
			for cell in cells:
				owners[cell] = model.owner_code(full[cell])
		else:
			for change in frame.get("owner_changes", []):
				owners[int(change[0])] = model.owner_code(change[1])
		if phase == PHASE_ACTION and frame["kind"] != null:
			var record := _action_record(
				i, frame, frames[i - 1], owners, before, core_of, core_base,
				deployed, had_deployment, last_core_read, seen_enemy_read,
				seen_enemy_core_owner, had_core_damage, in_critical, last_recovery_tick
			)
			_action_frames.append(i)
			actions.append(record)
			if record["kind"] == "sense" and record["outcome"] == "applied":
				pending["%s/%s" % [frame["actor"], frame["process"]]] = record
				_sense_actions.append(actions.size() - 1)
				_sense_frames.append(i)
		elif phase == PHASE_OBSERVATION and frame["sensed"] != null:
			var key := "%s/%s" % [frame["actor"], frame["process"]]
			var sense: Dictionary = pending.get(key, {})
			# Paired only when the recorded delivery equals the recorded sample.
			if not sense.is_empty() and sense["sensed"] == frame["sensed"]:
				sense["delivered"] = i
				sense["receiver"] = _anchor(frame, String(frame["actor"]), String(frame["process"]))
				_classify_delivery(i, frame, sense, cells, had_contact, active_contacts)
				_delivery_frames[i] = sense
				pending.erase(key)
		elif phase == PHASE_TICK_END:
			previous_disrupted = _end_of_tick(i, frame, owners, previous_disrupted)
	for k in _sense_actions.size():
		var sense: Dictionary = actions[_sense_actions[k]]
		var until: int = sense["delivered"] if sense["delivered"] >= 0 else frames.size()
		_sense_span = maxi(_sense_span, until - int(sense["i"]))
	_mark_decisive()


func _action_record(
	i: int, frame: Dictionary, previous: Dictionary, owners: PackedInt32Array,
	before: int, core_of: PackedInt32Array, core_base: PackedInt32Array,
	deployed: Dictionary, had_deployment: Dictionary, last_core_read: Array,
	seen_enemy_read: Array, seen_enemy_core_owner: Array,
	had_core_damage: Dictionary, in_critical: Dictionary, last_recovery_tick: Dictionary
) -> Dictionary:
	var actor := String(frame["actor"])
	var process := String(frame["process"])
	var kind := String(frame["kind"])
	var applied: bool = frame["status"] == "APPLIED"
	var tick := int(frame["t"])
	var entrant := int(_model.entrant_index.get(actor, -1))
	var record := {
		"i": i, "t": tick, "entrant": entrant,
		"actor": actor, "process": process, "kind": kind, "status": frame["status"],
		"address": -1 if frame["address"] == null else int(frame["address"]),
		"source": _anchor(previous, actor, process),
		"outcome": "applied" if applied else "refused",
		"before_owner": before, "core_owner": -1, "core_change": "",
		"read_kind": "", "read_discovery": false, "deployment": false, "sense_kind": "",
		"hits": [], "decisive_from": -1,
		"from": -1, "delta": 0, "sensed": null, "delivered": -1, "receiver": -1,
	}
	if kind == "write" and applied:
		var address: int = record["address"]
		var after := owners[address]
		record["outcome"] = "took" if after != before else "kept"
		var core := core_of[address]
		record["core_owner"] = core
		if core >= 0 and before == core and after != core:
			record["core_change"] = "damage"
			var held := _count_core_held(core, owners)
			var core_size := (_model.entrants[core]["core"] as Array).size()
			var core_id := String(_model.entrants[core]["id"])
			if not had_core_damage.has(core):
				had_core_damage[core] = true
				_add_turning_point(i, tick, entrant, actor, "core_damage", "t%d %s/%s WRITE %d: %s core damaged (%d/%d)" % [tick, actor, process, address, core_id, held, core_size])
			if held > 0 and held <= 2 and not in_critical.has(core):
				in_critical[core] = true
				_add_turning_point(i, tick, entrant, actor, "core_critical", "t%d %s/%s WRITE %d: %s core critical (%d/%d)" % [tick, actor, process, address, core_id, held, core_size])
		elif core >= 0 and after == core and before != core:
			record["core_change"] = "recovery"
			(last_core_read[core] as Dictionary)[address] = core
			var held := _count_core_held(core, owners)
			var core_size := (_model.entrants[core]["core"] as Array).size()
			var core_id := String(_model.entrants[core]["id"])
			if held > 2:
				in_critical.erase(core)
			if int(last_recovery_tick.get(core, -1)) != tick:
				last_recovery_tick[core] = tick
				_add_turning_point(i, tick, entrant, actor, "core_recovery", "t%d %s/%s WRITE %d: %s core recovered (%d/%d)" % [tick, actor, process, address, core_id, held, core_size])
		# A WRITE on the cell an opponent process stands on (recorded anchors).
		for anchor in frame["anchors"]:
			if anchor[0] != actor and int(anchor[2]) == address and (frame["alive"] as Array).has(anchor[0]):
				(record["hits"] as Array).append([anchor[0], anchor[1]])
	elif kind == "move" and applied:
		var from := _anchor(previous, actor, process)
		var to := _anchor(frame, actor, process)
		var delta := posmod(to - from, _model.arena_size)
		if frame["operand"] != null and int(frame["operand"]) < 0 and delta != 0:
			delta -= _model.arena_size
		record["from"] = from
		record["delta"] = delta
		var proc_key := "%s/%s" % [actor, process]
		if entrant >= 0 and not deployed.has(proc_key) and from == core_base[entrant] and to != core_base[entrant]:
			deployed[proc_key] = true
			record["deployment"] = true
			if not had_deployment.has(entrant):
				had_deployment[entrant] = true
				_add_turning_point(i, tick, entrant, actor, "deployment", "t%d %s/%s MOVE %d -> %d: deploys from core" % [tick, actor, process, from, to])
	elif kind == "sense" and applied:
		record["sensed"] = (frame["sensed"] as Array).duplicate()
	elif kind == "read" and applied:
		var address: int = record["address"]
		var core := core_of[address]
		record["core_owner"] = core
		if entrant >= 0 and core == entrant:
			if before != entrant:
				record["read_kind"] = "own_core_damaged"
				if int((last_core_read[entrant] as Dictionary).get(address, entrant)) == entrant:
					record["read_discovery"] = true
					var holder := String(_model.entrants[before]["id"]) if before >= 0 else "none"
					_add_turning_point(i, tick, entrant, actor, "read_own_core_damaged", "t%d %s/%s READ %d: own core cell held by %s" % [tick, actor, process, address, holder])
			else:
				record["read_kind"] = "routine"
			(last_core_read[entrant] as Dictionary)[address] = before
		elif entrant >= 0 and before >= 0 and before != entrant:
			var owner_id := String(_model.entrants[before]["id"])
			var read_key := "%d/%d" % [address, before]
			var is_new := not (seen_enemy_read[entrant] as Dictionary).has(read_key)
			(seen_enemy_read[entrant] as Dictionary)[read_key] = true
			if core == before:
				record["read_kind"] = "enemy_core"
				record["read_discovery"] = is_new
				if is_new and not (seen_enemy_core_owner[entrant] as Dictionary).has(before):
					(seen_enemy_core_owner[entrant] as Dictionary)[before] = true
					_add_turning_point(i, tick, entrant, actor, "read_enemy_core", "t%d %s/%s READ %d: found %s core cell" % [tick, actor, process, address, owner_id])
			else:
				record["read_kind"] = "enemy_cell"
				record["read_discovery"] = is_new
				if is_new:
					_add_turning_point(i, tick, entrant, actor, "read_enemy_cell", "t%d %s/%s READ %d: found %s-owned cell" % [tick, actor, process, address, owner_id])
		else:
			record["read_kind"] = "routine"
	return record


func _classify_delivery(
	i: int, frame: Dictionary, sense: Dictionary, cells: int,
	had_contact: Dictionary, active_contacts: Dictionary
) -> void:
	var actor := String(frame["actor"])
	var process := String(frame["process"])
	var tick := int(frame["t"])
	var entrant := int(sense["entrant"])
	var sensed: Array = sense["sensed"]
	var sensed_set := {}
	for addr in sensed:
		sensed_set[int(addr)] = true
	var active: Dictionary = active_contacts.get(actor, {})
	if half_width >= 0:
		var center := int(sense["address"])
		for prev_addr in active.keys():
			if _circular_distance(int(prev_addr), center, cells) <= half_width and not sensed_set.has(int(prev_addr)):
				active.erase(prev_addr)
	if sensed.is_empty():
		sense["sense_kind"] = "empty"
	else:
		if not had_contact.has(actor):
			had_contact[actor] = true
			sense["sense_kind"] = "first_contact"
			_add_turning_point(i, tick, entrant, actor, "first_contact", "t%d %s/%s SENSE delivered: first contact at %s" % [tick, actor, process, _cells_csv(sensed)])
		else:
			var all_known := true
			for addr in sensed:
				if not active.has(int(addr)):
					all_known = false
					break
			if all_known:
				sense["sense_kind"] = "confirm"
			else:
				sense["sense_kind"] = "reacquire"
				_add_turning_point(i, tick, entrant, actor, "reacquire", "t%d %s/%s SENSE delivered: reacquired at %s" % [tick, actor, process, _cells_csv(sensed)])
		for addr in sensed:
			active[int(addr)] = true
	active_contacts[actor] = active


func _end_of_tick(i: int, frame: Dictionary, owners: PackedInt32Array, previous_disrupted: Array) -> Array:
	var tick := int(frame["t"])
	var held := PackedInt32Array()
	for e in _model.entrants.size():
		held.append(_count_core_held(e, owners))
	_core_at_tick_end[tick] = held
	var disrupted: Array = []
	for pair in frame["disrupted"]:
		var d_actor := String(pair[0])
		var d_proc := String(pair[1])
		var d_anchor := _anchor(frame, d_actor, d_proc)
		disrupted.append([pair[0], pair[1], d_anchor])
		if not previous_disrupted.has(pair):
			var d_e := int(_model.entrant_index.get(d_actor, -1))
			_add_turning_point(i, tick, d_e, d_actor, "disruption", "t%d %s/%s disrupted at %d" % [tick, d_actor, d_proc, d_anchor])
	var next_disrupted := (frame["disrupted"] as Array).duplicate(true)
	var eliminated: Array = _model.eliminated_at(i)
	for entrant_id in eliminated:
		var e := int(_model.entrant_index.get(String(entrant_id), -1))
		var e_name := String(_model.entrants[e]["name"]) if e >= 0 else ""
		var c_size := (_model.entrants[e]["core"] as Array).size() if e >= 0 else 0
		var c_held := held[e] if e >= 0 and held.size() > e else 0
		_add_turning_point(i, tick, e, String(entrant_id), "elimination", "t%d %s %s eliminated (core %d/%d)" % [tick, entrant_id, e_name, c_held, c_size])
	if not disrupted.is_empty() or not eliminated.is_empty():
		_tick_event_frames.append(i)
		tick_events.append({"i": i, "t": tick, "disrupted": disrupted, "eliminated": eliminated})
	return next_disrupted


func _count_core_held(entrant: int, owners: PackedInt32Array) -> int:
	var count := 0
	for cell in _model.entrants[entrant]["core"]:
		if owners[int(cell)] == entrant:
			count += 1
	return count


func _add_turning_point(i: int, tick: int, entrant: int, actor: String, kind: String, text: String) -> void:
	_turning_points.append({"i": i, "t": tick, "entrant": entrant, "actor": actor, "kind": kind, "text": text})
	_turning_point_frames.append(i)


static func _circular_distance(a: int, b: int, arena: int) -> int:
	var d := posmod(a - b, arena)
	return mini(d, arena - d)


static func _cells_csv(cells: Array) -> String:
	var parts: PackedStringArray = []
	for cell in cells:
		parts.append(str(int(cell)))
	return ", ".join(parts)


## For each eliminated entrant, the last recorded WRITE that took one of its
## core cells before its elimination is the decisive capture. It is shown as
## decisive only from the elimination's TICK_END frame on, so no frame before
## the recorded elimination implies it.
func _mark_decisive() -> void:
	for event in tick_events:
		for entrant in event["eliminated"]:
			var e := int(_model.entrant_index[entrant])
			for k in range(actions.size() - 1, -1, -1):
				var action: Dictionary = actions[k]
				if int(action["i"]) < int(event["i"]) and action["core_owner"] == e and action["core_change"] == "damage":
					action["decisive_from"] = int(event["i"])
					break


func _anchor(frame: Dictionary, entrant: String, process: String) -> int:
	for anchor in frame["anchors"]:
		if anchor[0] == entrant and anchor[1] == process:
			return int(anchor[2])
	return -1


## First frame index of the oldest tick still shown at `tick`.
func _window_start(tick: int) -> int:
	var oldest := tick - EFFECT_TICKS
	return 0 if oldest < 0 else _model.index_for_tick_end(oldest) + 1


## First frame index of `tick` (its first OBSERVATION, or its TICK_END).
func tick_start(tick: int) -> int:
	return 0 if tick <= 0 else _model.index_for_tick_end(tick - 1) + 1


## Effects visible at frame `index`: recorded actions of the last EFFECT_TICKS
## ticks up to and including this frame, SENSE samples (pending until their
## recorded delivery, then delivered), and tick-end disruptions.
func at(index: int) -> Dictionary:
	var tick: int = _model.tick_of(index)
	var shown: Array = []
	for k in range(_action_frames.bsearch(_window_start(tick)), actions.size()):
		var action: Dictionary = actions[k]
		if int(action["i"]) > index:
			break
		if action["kind"] == "sense" and action["outcome"] == "applied":
			continue  # drawn as a sample below
		shown.append(_shown(action, tick, index))
	var senses: Array = []
	# A sample shown at `index` was delivered in the window or is still pending, so
	# its SENSE frame is at most _sense_span frames before the window start.
	for k in range(_sense_frames.bsearch(_window_start(tick) - _sense_span), _sense_frames.size()):
		if _sense_frames[k] > index:
			break
		var sense: Dictionary = actions[_sense_actions[k]]
		var delivered: int = sense["delivered"]
		var state := "pending"
		var age := tick - int(sense["t"])
		if delivered >= 0 and delivered <= index:
			state = "delivered"
			age = tick - _model.tick_of(delivered)
			if age >= EFFECT_TICKS:
				continue
		var shown_sense := _shown(sense, tick, index)
		if state == "pending":
			# Where and when it will be delivered is a later frame: not handed over yet.
			shown_sense["delivered"] = -1
			shown_sense["receiver"] = -1
			shown_sense["sense_kind"] = ""
		shown_sense["state"] = state
		shown_sense["age"] = age if state == "delivered" else 0
		shown_sense["current"] = int(sense["i"]) == index or delivered == index
		shown_sense["half_width"] = half_width
		senses.append(shown_sense)
	var disruptions: Array = []
	for k in range(_tick_event_frames.bsearch(_window_start(tick)), tick_events.size()):
		var event: Dictionary = tick_events[k]
		if int(event["i"]) > index:
			break
		for pair in event["disrupted"]:
			disruptions.append({"actor": pair[0], "process": pair[1], "anchor": pair[2], "age": tick - int(event["t"])})
	return {"actions": shown, "senses": senses, "disruptions": disruptions}


func _shown(action: Dictionary, tick: int, index: int) -> Dictionary:
	var shown := action.duplicate()
	shown["age"] = tick - int(action["t"])
	shown["current"] = int(action["i"]) == index
	shown["decisive"] = int(action["decisive_from"]) >= 0 and index >= int(action["decisive_from"])
	shown.erase("decisive_from")
	return shown


## The recorded action at `index` as shown there, or {} for an
## OBSERVATION/TICK_END frame.
func action_at(index: int) -> Dictionary:
	var k := _action_frames.bsearch(index)
	if k < actions.size() and _action_frames[k] == index:
		return _shown(actions[k], _model.tick_of(index), index)
	return {}


## At an elimination's TICK_END frame, its decisive captures, else [].
func decisive_at(index: int) -> Array:
	var out: Array = []
	if not _model.is_tick_end(index):
		return out
	for action in actions:
		if int(action["decisive_from"]) == index:
			out.append(_shown(action, _model.tick_of(index), index))
	return out


## The SENSE whose sample is delivered at OBSERVATION frame `index`, or {}.
func delivery_at(index: int) -> Dictionary:
	return _delivery_frames.get(index, {})


## Recent verified tactical turning points up to and including `index`, newest first.
func turning_points(index: int, limit: int = TURNING_POINT_LIMIT) -> Array:
	var end := _turning_point_frames.bsearch(index + 1)
	var out: Array = []
	for k in range(end - 1, maxi(-1, end - 1 - limit), -1):
		out.append(_turning_points[k])
	return out


## Most recent tactical turning point at or before `index` within `max_tick_age` ticks, or {}.
func latest_turning_point(index: int, max_tick_age: int = 1) -> Dictionary:
	var end := _turning_point_frames.bsearch(index + 1)
	if end <= 0:
		return {}
	var latest: Dictionary = _turning_points[end - 1]
	if _model.tick_of(index) - int(latest["t"]) > max_tick_age:
		return {}
	return latest


## Core integrity per entrant at `index`: cells held now, the change since the
## previous tick boundary, and a level (ok, low, critical or eliminated).
func cores(index: int) -> Array:
	var tick: int = _model.tick_of(index)
	var base: PackedInt32Array = _core_at_tick_end.get(tick - 1, PackedInt32Array())
	var alive: Array = _model.frames[index]["alive"]
	var out: Array = []
	for e in _model.entrants.size():
		var entrant: Dictionary = _model.entrants[e]
		var held: int = _model.core_cells_owned(index, e)
		var level := "ok"
		if not alive.has(entrant["id"]):
			level = "eliminated"
		elif held <= 2:
			level = "critical"
		elif held <= 4:
			level = "low"
		out.append({
			"id": entrant["id"], "held": held, "size": (entrant["core"] as Array).size(),
			"delta": held - (base[e] if base.size() > e else held), "level": level,
		})
	return out


## Counts per entrant of the recorded actions of the current tick up to `index`.
func tick_summary(index: int) -> Array:
	var tick: int = _model.tick_of(index)
	var out: Array = []
	for e in _model.entrants.size():
		out.append({"writes": 0, "took": 0, "core_hits": 0, "recovered": 0, "hits": 0, "moves": 0, "senses": 0, "reads": 0, "read_discoveries": 0, "refused": 0})
	for k in range(_action_frames.bsearch(tick_start(tick)), actions.size()):
		var action: Dictionary = actions[k]
		if int(action["i"]) > index:
			break
		if int(action["entrant"]) < 0:
			continue
		var counts: Dictionary = out[int(action["entrant"])]
		if action["outcome"] == "refused":
			counts["refused"] += 1
			continue
		match String(action["kind"]):
			"write":
				counts["writes"] += 1
				counts["took"] += 1 if action["outcome"] == "took" else 0
				counts["core_hits"] += 1 if action["core_change"] == "damage" else 0
				counts["recovered"] += 1 if action["core_change"] == "recovery" else 0
				counts["hits"] += (action["hits"] as Array).size()
			"move":
				counts["moves"] += 1
			"sense":
				counts["senses"] += 1
			"read":
				counts["reads"] += 1
				counts["read_discoveries"] += 1 if bool(action["read_discovery"]) else 0
	return out
