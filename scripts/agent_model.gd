extends RefCounted
## Agent-perspective playback model over agent_a.json.
##
## agent_a.json is built only from Bytefray's receipt-only SensingView, so this
## model holds nothing beyond what the entrant was delivered: its own core and
## processes, delivered samples and reads, historical contacts and its own
## events. It never sees broadcast data.

const PHASE_TICK_END := 2
const RECENT_EVENT_LIMIT := 8
const TURNING_POINT_LIMIT := 6
## How many ticks an own MOVE, WRITE or notable delivered READ stays drawn (the same as broadcast).
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
var _notable_reads: Array = []  # delivered discovery READ receipts, in frame order
var _notable_read_frames := PackedInt32Array()
var _sample_kinds: Dictionary = {}  # "frame/sample_index" -> "first_contact" | "confirm" | "reacquire" | "empty"
var _frame_sample_kind: Dictionary = {}  # frame -> latest positive sample kind at that frame
var _frame_read_kinds: Dictionary = {}  # frame -> Array of discovery read_kinds delivered at that frame
var _read_event_notes: Dictionary = {}  # "frame/read_index" -> factual detail suffix
var _sample_event_notes: Dictionary = {}  # "frame/process" -> factual sample delivery classification
var _turning_points: Array = []  # receipt-only turning points {"i", "t", "kind", "text"}
var _turning_point_frames := PackedInt32Array()


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
	var last_core_read: Dictionary = {}
	for offset in core_size:
		last_core_read[posmod(core_base + offset, arena_size)] = entrant_id
	var seen_enemy_read: Dictionary = {}
	var deployed: Dictionary = {}
	var had_deployment := false
	var had_contact := false
	var active_contacts: Dictionary = {}
	var last := -1
	for i in frames.size():
		var frame: Dictionary = frames[i]
		var tick := int(frame["t"])
		var samples: Array = frame["samples"]
		if not samples.is_empty():
			last = i
			for s_idx in samples.size():
				_classify_sample(i, tick, s_idx, samples[s_idx], had_contact, active_contacts)
				if not (samples[s_idx]["addresses"] as Array).is_empty():
					had_contact = true
		_last_sample_index[i] = last
		var reads: Array = frame["reads"]
		if not reads.is_empty():
			_classify_reads(i, tick, frame, reads, last_core_read, seen_enemy_read)
		if int(frame["p"]) == PHASE_TICK_END:
			_tick_end_index[tick] = i
			max_tick = maxi(max_tick, tick)
		for event in frame["events"]:
			if ["move", "write", "sense"].has(event["kind"]) and i > 0:
				var record := _own_action(i, frame, frames[i - 1], event, deployed)
				if bool(record["deployment"]) and not had_deployment:
					had_deployment = true
					var from := int(record["source"])
					var to := posmod(from + int(record["delta"]), arena_size)
					_add_turning_point(i, tick, "deployment", "t%d %s MOVE %d -> %d: deploys from core" % [tick, record["process"], from, to])
				_own_actions.append(record)
				_own_action_frames.append(i)
	_pair_samples()


func _classify_sample(
	i: int, tick: int, s_idx: int, sample: Dictionary,
	had_contact: bool, active_contacts: Dictionary
) -> void:
	var center := int(sample["center"])
	var half_w := int(sample["half_width"])
	var addresses: Array = sample["addresses"]
	var addr_set := {}
	for addr in addresses:
		addr_set[int(addr)] = true
	var process := String(sample["received"][2])
	for prev_addr in active_contacts.keys():
		if _circular_distance(int(prev_addr), center, arena_size) <= half_w and not addr_set.has(int(prev_addr)):
			active_contacts.erase(prev_addr)
	var sample_key := "%d/%d" % [i, s_idx]
	if addresses.is_empty():
		_sample_kinds[sample_key] = "empty"
		return
	var kind := "confirm"
	if not had_contact:
		kind = "first_contact"
		_add_turning_point(i, tick, "first_contact", "t%d %s SENSE delivered: first contact at %s" % [tick, process, _cells_csv(addresses)])
	else:
		var all_known := true
		for addr in addresses:
			if not active_contacts.has(int(addr)):
				all_known = false
				break
		if not all_known:
			kind = "reacquire"
			_add_turning_point(i, tick, "reacquire", "t%d %s SENSE delivered: reacquired at %s" % [tick, process, _cells_csv(addresses)])
	for addr in addresses:
		active_contacts[int(addr)] = true
	_sample_kinds[sample_key] = kind
	_frame_sample_kind[i] = kind
	_sample_event_notes["%d/%s" % [i, process]] = kind


func _classify_reads(
	i: int, tick: int, frame: Dictionary, reads: Array,
	last_core_read: Dictionary, seen_enemy_read: Dictionary
) -> void:
	var discovery_kinds: Array = []
	for r_idx in reads.size():
		var read: Dictionary = reads[r_idx]
		var address := posmod(int(read["address"]), arena_size)
		var owner := "" if read["owner"] == null else String(read["owner"])
		var owner_label := "none" if owner == "" else owner
		var process := String(read["received"][2])
		var source := _own_anchor(frame, process)
		var read_kind := "routine"
		var is_discovery := false
		var note := "owner %s" % owner_label
		if _is_own_core(address):
			if owner != entrant_id:
				read_kind = "own_core_damaged"
				note = "owner %s (own core damaged)" % owner_label
				if String(last_core_read.get(address, entrant_id)) == entrant_id:
					is_discovery = true
					_add_turning_point(i, tick, "read_own_core_damaged", "t%d %s READ %d delivered: own core cell held by %s" % [tick, process, address, owner_label])
			else:
				if String(last_core_read.get(address, entrant_id)) != entrant_id:
					read_kind = "own_core_recovered"
					note = "owner %s (own core recovered)" % owner_label
					is_discovery = true
					_add_turning_point(i, tick, "read_own_core_recovered", "t%d %s READ %d delivered: own core cell recovered" % [tick, process, address])
			last_core_read[address] = owner
		else:
			if owner != "" and owner != entrant_id:
				read_kind = "enemy_owned"
				note = "owner %s (enemy cell)" % owner_label
				var read_key := "%d/%s" % [address, owner]
				if not seen_enemy_read.has(read_key):
					seen_enemy_read[read_key] = true
					is_discovery = true
					_add_turning_point(i, tick, "read_enemy_owned", "t%d %s READ %d delivered: owned by %s" % [tick, process, address, owner_label])
		_read_event_notes["%d/%d" % [i, r_idx]] = note
		if is_discovery:
			_notable_reads.append({
				"i": i, "t": tick, "process": process, "source": source,
				"address": address, "read_kind": read_kind, "owner": owner_label,
			})
			_notable_read_frames.append(i)
			discovery_kinds.append(read_kind)
	if not discovery_kinds.is_empty():
		_frame_read_kinds[i] = discovery_kinds


func _is_own_core(address: int) -> bool:
	var offset := posmod(address - core_base, arena_size)
	return offset >= 0 and offset < core_size


func _add_turning_point(i: int, tick: int, kind: String, text: String) -> void:
	_turning_points.append({"i": i, "t": tick, "kind": kind, "text": text})
	_turning_point_frames.append(i)


static func _circular_distance(a: int, b: int, arena: int) -> int:
	var d := posmod(a - b, arena)
	return mini(d, arena - d)


static func _cells_csv(cells: Array) -> String:
	var parts: PackedStringArray = []
	for cell in cells:
		parts.append(str(int(cell)))
	return ", ".join(parts)


## One own action, from Agent A's own record: the event, and for a MOVE the
## process anchor before and after it.
func _own_action(i: int, frame: Dictionary, previous: Dictionary, event: Dictionary, deployed: Dictionary) -> Dictionary:
	var process := String(event["process"])
	var source := _own_anchor(previous, process)
	var record := {
		"i": i, "t": int(frame["t"]), "cb": frame["cb"], "kind": event["kind"], "process": process,
		"address": -1 if event["address"] == null else int(event["address"]),
		"status": event["status"], "source": source, "delta": 0, "delivered": -1, "deployment": false,
	}
	if event["kind"] == "move" and event["status"] == "APPLIED":
		var to := _own_anchor(frame, process)
		var delta := posmod(to - source, arena_size)
		if event["operand"] != null and int(event["operand"]) < 0 and delta != 0:
			delta -= arena_size
		record["delta"] = delta
		if not deployed.has(process) and source == core_base and to != core_base:
			deployed[process] = true
			record["deployment"] = true
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


## Classification of delivered sample `s_idx` at frame `index`.
func sample_kind_at(index: int, s_idx: int) -> String:
	return String(_sample_kinds.get("%d/%d" % [index, s_idx], "confirm"))


## Discovery READ kinds delivered at frame `index` (empty for routine/repeat reads).
func read_discovery_kinds_at(index: int) -> Array:
	return _frame_read_kinds.get(index, [])


## Recent receipt-only turning points up to and including `index`, newest first.
func turning_points(index: int, limit: int = TURNING_POINT_LIMIT) -> Array:
	var end := _turning_point_frames.bsearch(index + 1)
	var out: Array = []
	for k in range(end - 1, maxi(-1, end - 1 - limit), -1):
		out.append(_turning_points[k])
	return out


## Most recent receipt-only turning point at or before `index` within `max_tick_age` ticks, or {}.
func latest_turning_point(index: int, max_tick_age: int = 1) -> Dictionary:
	var end := _turning_point_frames.bsearch(index + 1)
	if end <= 0:
		return {}
	var latest: Dictionary = _turning_points[end - 1]
	if tick_of(index) - int(latest["t"]) > max_tick_age:
		return {}
	return latest


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
			var note := String(_read_event_notes.get("%d/%d" % [i, j], "owner %s" % ("none" if read["owner"] == null else read["owner"])))
			collected.append({"t": int(frame["t"]), "kind": "read result", "process": read["received"][2], "address": read["address"], "status": null, "detail": note})
		var events: Array = frame["events"]
		for j in range(events.size() - 1, -1, -1):
			var event: Dictionary = events[j]
			if event["kind"] == "observation":
				if event["sample_status"] != "ABSENT":
					var detail := String(event["sample_status"])
					var sample_kind := String(_sample_event_notes.get("%d/%s" % [i, event["process"]], ""))
					if sample_kind == "reacquire":
						detail += " (reacquired)"
					elif sample_kind == "first_contact":
						detail += " (first contact)"
					collected.append({"t": int(frame["t"]), "kind": "sample received", "process": event["process"], "address": null, "status": null, "detail": detail})
			else:
				collected.append({"t": int(frame["t"]), "kind": event["kind"], "process": event["process"], "address": event["address"], "status": event["status"], "detail": "result pending" if event["sample_status"] == "PENDING" else ""})
		i -= 1
	return collected.slice(0, limit)


## Own MOVE and WRITE indicators of the last EFFECT_TICKS ticks up to `index`,
## own SENSE requests whose sample has not been delivered by `index`, and
## delivered notable READ discoveries of the last EFFECT_TICKS ticks.
func own_actions(index: int) -> Dictionary:
	var tick := tick_of(index)
	var since := 0 if tick - EFFECT_TICKS < 0 else index_for_tick_end(tick - EFFECT_TICKS) + 1
	var moves: Array = []
	var writes: Array = []
	var pending: Array = []
	var notable_reads: Array = []
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
			moves.append([record["process"], record["source"], record["delta"], age, 1 if bool(record["deployment"]) else 0])
		elif record["kind"] == "write":
			writes.append([record["process"], record["source"], record["address"], record["status"], age])
	for k in range(_notable_read_frames.bsearch(since), _notable_reads.size()):
		var r: Dictionary = _notable_reads[k]
		if int(r["i"]) > index:
			break
		var r_age := tick - int(r["t"])
		if r_age < EFFECT_TICKS:
			notable_reads.append([r["process"], r["source"], r["address"], r["read_kind"], r["owner"], r_age])
	return {"moves": moves, "notable_reads": notable_reads, "pending_senses": pending, "writes": writes}


func state(index: int) -> Dictionary:
	var frame: Dictionary = frames[index]
	var sample: Variant = null
	if _last_sample_index[index] >= 0:
		var s_frame := _last_sample_index[index]
		var latest: Dictionary = (frames[s_frame]["samples"] as Array).back()
		sample = latest.duplicate()
		sample["sample_kind"] = String(_frame_sample_kind.get(s_frame, ""))
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
