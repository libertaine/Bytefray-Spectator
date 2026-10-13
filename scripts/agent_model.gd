extends RefCounted
## Agent-perspective playback model over agent_a.json.
##
## agent_a.json is built only from Bytefray's receipt-only SensingView, so this
## model holds nothing beyond what the entrant was delivered: its own core and
## processes, delivered samples and reads, historical contacts and its own
## events. It never sees broadcast data.

const PHASE_TICK_END := 2
const RECENT_EVENT_LIMIT := 8
## How many ticks an own MOVE or WRITE stays drawn (the same as broadcast).
const EFFECT_TICKS := 3

var entrant_id: String
var entrant_name: String
var label: String
var arena_size: int
var core_base: int
var core_size: int
var opponent_activity: String
var frames: Array
var max_tick := 0

var _tick_end_index: Dictionary = {}
var _last_sample_index := PackedInt32Array()
var _own_actions: Array = []  # own MOVE, WRITE and SENSE events, in frame order
var _own_action_frames := PackedInt32Array()
var _sense_span := 0  # longest frame span from an own SENSE to its delivery (or the end)


func _init(document: Dictionary) -> void:
	entrant_id = String(document["entrant_id"])
	entrant_name = String(document["name"])
	label = String(document["label"])
	arena_size = int(document["arena_size"])
	core_base = int(document["core_base"])
	core_size = int(document["core_size"])
	opponent_activity = String(document["opponent_activity"])
	frames = document["frames"]
	_last_sample_index.resize(frames.size())
	var last := -1
	for i in frames.size():
		var frame: Dictionary = frames[i]
		if not (frame["samples"] as Array).is_empty():
			last = i
		_last_sample_index[i] = last
		if int(frame["p"]) == PHASE_TICK_END:
			var tick := int(frame["t"])
			_tick_end_index[tick] = i
			max_tick = maxi(max_tick, tick)
		for event in frame["events"]:
			if ["move", "write", "sense"].has(event["kind"]) and i > 0:
				_own_actions.append(_own_action(i, frame, frames[i - 1], event))
				_own_action_frames.append(i)
	_pair_samples()


## One own action, from Agent A's own record: the event, and for a MOVE the
## process anchor before and after it.
func _own_action(i: int, frame: Dictionary, previous: Dictionary, event: Dictionary) -> Dictionary:
	var process := String(event["process"])
	var record := {
		"i": i, "t": int(frame["t"]), "cb": frame["cb"], "kind": event["kind"], "process": process,
		"address": -1 if event["address"] == null else int(event["address"]),
		"status": event["status"], "source": _own_anchor(previous, process), "delta": 0, "delivered": -1,
	}
	if event["kind"] == "move" and event["status"] == "APPLIED":
		var to := _own_anchor(frame, process)
		var delta := posmod(to - int(record["source"]), arena_size)
		if event["operand"] != null and int(event["operand"]) < 0 and delta != 0:
			delta -= arena_size
		record["delta"] = delta
	return record


func _own_anchor(frame: Dictionary, process: String) -> int:
	for entry in frame["processes"]:
		if entry[0] == process:
			return int(entry[1])
	return -1


## An own SENSE is pending until the frame that delivers the sample recorded as
## taken at that SENSE (same tick, callback and process).
func _pair_samples() -> void:
	var by_point: Dictionary = {}
	for record in _own_actions:
		if record["kind"] == "sense":
			by_point[_point_key(record["t"], record["cb"], record["process"])] = record
	for i in frames.size():
		for sample in frames[i]["samples"]:
			var point: Array = sample["sampled"]
			var record: Dictionary = by_point.get(_point_key(point[0], point[1], point[2]), {})
			if not record.is_empty():
				record["delivered"] = i
	for record in _own_actions:
		if record["kind"] == "sense":
			var until: int = record["delivered"] if record["delivered"] >= 0 else frames.size()
			_sense_span = maxi(_sense_span, until - int(record["i"]))


static func _point_key(tick: Variant, callback: Variant, process: Variant) -> String:
	return "%d/%d/%s" % [int(tick), int(callback), process]


func frame_count() -> int:
	return frames.size()


func tick_of(index: int) -> int:
	return int(frames[index]["t"])


func is_tick_end(index: int) -> bool:
	return int(frames[index]["p"]) == PHASE_TICK_END


func index_for_tick_end(tick: int) -> int:
	return int(_tick_end_index[clampi(tick, 0, max_tick)])


## The latest own events, newest first, with their tick. A routine
## observation that delivered nothing is folded away; one that delivered a
## sample, and a delivered READ result, are kept.
func recent_events(index: int, limit: int = RECENT_EVENT_LIMIT) -> Array:
	var collected: Array = []
	var i := index
	while i >= 0 and collected.size() < limit:
		var frame: Dictionary = frames[i]
		var reads: Array = frame["reads"]
		for j in range(reads.size() - 1, -1, -1):
			var read: Dictionary = reads[j]
			collected.append({"t": int(frame["t"]), "kind": "read result", "process": read["received"][2], "address": read["address"], "status": null, "detail": "owner %s" % ("none" if read["owner"] == null else read["owner"])})
		var events: Array = frame["events"]
		for j in range(events.size() - 1, -1, -1):
			var event: Dictionary = events[j]
			if event["kind"] == "observation":
				if event["sample_status"] != "ABSENT":
					collected.append({"t": int(frame["t"]), "kind": "sample received", "process": event["process"], "address": null, "status": null, "detail": event["sample_status"]})
			else:
				collected.append({"t": int(frame["t"]), "kind": event["kind"], "process": event["process"], "address": event["address"], "status": event["status"], "detail": "result pending" if event["sample_status"] == "PENDING" else ""})
		i -= 1
	return collected.slice(0, limit)


## Own MOVE and WRITE indicators of the last EFFECT_TICKS ticks up to `index`,
## and own SENSE requests whose sample has not been delivered by `index`.
func own_actions(index: int) -> Dictionary:
	var tick := tick_of(index)
	var since := 0 if tick - EFFECT_TICKS < 0 else index_for_tick_end(tick - EFFECT_TICKS) + 1
	var moves: Array = []
	var writes: Array = []
	var pending: Array = []
	for k in range(_own_action_frames.bsearch(mini(since, index - _sense_span)), _own_actions.size()):
		var record: Dictionary = _own_actions[k]
		if int(record["i"]) > index:
			break
		if record["kind"] == "sense":
			var delivered := int(record["delivered"])
			if record["status"] == "APPLIED" and (delivered < 0 or delivered > index):
				pending.append([record["process"], record["address"]])
			continue
		if int(record["i"]) < since:
			continue
		var age := tick - int(record["t"])
		if record["kind"] == "move" and record["status"] == "APPLIED":
			moves.append([record["process"], record["source"], record["delta"], age])
		elif record["kind"] == "write":
			writes.append([record["process"], record["source"], record["address"], record["status"], age])
	return {"moves": moves, "writes": writes, "pending_senses": pending}


func state(index: int) -> Dictionary:
	var frame: Dictionary = frames[index]
	var sample: Variant = null
	if _last_sample_index[index] >= 0:
		sample = (frames[_last_sample_index[index]]["samples"] as Array).back()
	return {
		"mode": "agent",
		"tick": int(frame["t"]),
		"callback": frame["cb"],
		"phase": int(frame["p"]),
		"core_base": core_base,
		"core_size": core_size,
		"processes": frame["processes"],
		"contacts": frame["contacts"],
		"receipt": frame["receipt"],
		"latest_sample": sample,
		"recent_events": recent_events(index),
		"own_actions": own_actions(index),
	}
