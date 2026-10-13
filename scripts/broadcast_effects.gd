extends RefCounted
## Broadcast-only transient effects, core status and tick summaries, derived
## from the recorded broadcast.json frames. The Agent A perspective never uses
## this model.
##
## Every query is a pure function of the frame index. An effect is shown at
## index i only if its recorded frame is at or before i, so nothing can show a
## future event, and only while it is younger than EFFECT_TICKS ticks. Seeking,
## restarting or switching perspective therefore rebuilds exactly the same
## effects, and nothing stale can survive a jump.
##
## Nothing is simulated. A SENSE sample's contents are the recorded `sensed`
## anchors of its ACTION frame. Its delivery is the recorded `sensed` field of
## the same process's next OBSERVATION frame. Ownership changes are the recorded
## owner_changes, a disruption is the recorded tick-end `disrupted` set and an
## elimination is the recorded `alive` set. The only rule constant is the
## ruleset's public SENSE half-width, used to draw the sampled window; the
## exporter tests check it against the pinned Bytefray ruleset.

const PHASE_OBSERVATION := 0
const PHASE_ACTION := 1
const PHASE_TICK_END := 2
const EFFECT_TICKS := 3
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


func _init(model) -> void:
	_model = model
	half_width = int(SENSE_HALF_WIDTH.get(model.ruleset_id, -1))
	var frames: Array = model.frames
	var cells: int = model.arena_size
	var entrant_count: int = model.entrants.size()
	var core_of := PackedInt32Array()
	core_of.resize(cells)
	core_of.fill(-1)
	for e in entrant_count:
		for cell in model.entrants[e]["core"]:
			core_of[int(cell)] = e
	var owners := PackedInt32Array()
	owners.resize(cells)
	owners.fill(-1)
	var pending: Dictionary = {}  # "entrant/process" -> SENSE action record
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
			var record := _action_record(i, frame, frames[i - 1], owners, before, core_of)
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
				_delivery_frames[i] = sense
				pending.erase(key)
		elif phase == PHASE_TICK_END:
			_end_of_tick(i, frame, owners)
	for k in _sense_actions.size():
		var sense: Dictionary = actions[_sense_actions[k]]
		var until: int = sense["delivered"] if sense["delivered"] >= 0 else frames.size()
		_sense_span = maxi(_sense_span, until - int(sense["i"]))
	_mark_decisive()


func _action_record(i: int, frame: Dictionary, previous: Dictionary, owners: PackedInt32Array, before: int, core_of: PackedInt32Array) -> Dictionary:
	var actor := String(frame["actor"])
	var process := String(frame["process"])
	var kind := String(frame["kind"])
	var applied: bool = frame["status"] == "APPLIED"
	var record := {
		"i": i, "t": int(frame["t"]), "entrant": int(_model.entrant_index.get(actor, -1)),
		"actor": actor, "process": process, "kind": kind, "status": frame["status"],
		"address": -1 if frame["address"] == null else int(frame["address"]),
		"source": _anchor(previous, actor, process),
		"outcome": "applied" if applied else "refused",
		"core_owner": -1, "core_change": "", "hits": [], "decisive": false,
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
		elif core >= 0 and after == core and before != core:
			record["core_change"] = "recovery"
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
	elif kind == "sense" and applied:
		record["sensed"] = (frame["sensed"] as Array).duplicate()
	return record


func _end_of_tick(i: int, frame: Dictionary, owners: PackedInt32Array) -> void:
	var tick := int(frame["t"])
	var held := PackedInt32Array()
	for e in _model.entrants.size():
		var count := 0
		for cell in _model.entrants[e]["core"]:
			if owners[int(cell)] == e:
				count += 1
		held.append(count)
	_core_at_tick_end[tick] = held
	var disrupted: Array = []
	for pair in frame["disrupted"]:
		disrupted.append([pair[0], pair[1], _anchor(frame, String(pair[0]), String(pair[1]))])
	var eliminated: Array = _model.eliminated_at(i)
	if disrupted.is_empty() and eliminated.is_empty():
		return
	_tick_event_frames.append(i)
	tick_events.append({"i": i, "t": tick, "disrupted": disrupted, "eliminated": eliminated})


## For each eliminated entrant, the last recorded WRITE that took one of its
## core cells at or before its elimination is the decisive capture.
func _mark_decisive() -> void:
	for event in tick_events:
		for entrant in event["eliminated"]:
			var e := int(_model.entrant_index[entrant])
			for k in range(actions.size() - 1, -1, -1):
				var action: Dictionary = actions[k]
				if int(action["i"]) < int(event["i"]) and action["core_owner"] == e and action["core_change"] == "damage":
					action["decisive"] = true
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
	for k in range(_sense_frames.bsearch(index - _sense_span), _sense_frames.size()):
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
	return shown


## The recorded action at `index`, or {} for an OBSERVATION/TICK_END frame.
func action_at(index: int) -> Dictionary:
	var k := _action_frames.bsearch(index)
	if k < actions.size() and _action_frames[k] == index:
		return actions[k]
	return {}


## The SENSE whose sample is delivered at OBSERVATION frame `index`, or {}.
func delivery_at(index: int) -> Dictionary:
	return _delivery_frames.get(index, {})


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
		out.append({"writes": 0, "took": 0, "core_hits": 0, "recovered": 0, "hits": 0, "moves": 0, "senses": 0, "reads": 0, "refused": 0})
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
	return out
