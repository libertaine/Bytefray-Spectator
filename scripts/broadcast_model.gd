extends RefCounted
## Broadcast (omniscient) playback model over broadcast.json frames.
##
## Ownership is stored as deltas; keyframes every KEYFRAME_INTERVAL frames make
## seeking cheap, and sequential stepping reuses the previous board.

const KEYFRAME_INTERVAL := 1024
const PHASE_TICK_END := 2

var match_id: String
var ruleset_id: String
var arena_size: int
var entrants: Array = []
var entrant_index: Dictionary = {}
var result: Dictionary
var frames: Array
var max_tick := 0

var _keyframes: Array[PackedInt32Array] = []
var _tick_end_index: Dictionary = {}
var _cached_index := -1
var _cached_owners := PackedInt32Array()


func _init(document: Dictionary) -> void:
	match_id = String(document["match_id"])
	ruleset_id = String(document["ruleset_id"])
	arena_size = int(document["arena_size"])
	entrants = document["entrants"]
	for i in entrants.size():
		entrant_index[String(entrants[i]["id"])] = i
	result = document["result"]
	frames = document["frames"]
	var owners := PackedInt32Array()
	owners.resize(arena_size)
	owners.fill(-1)
	for i in frames.size():
		var frame: Dictionary = frames[i]
		if i == 0:
			var full: Array = frame["owners"]
			for cell in arena_size:
				owners[cell] = owner_code(full[cell])
		else:
			_apply_changes(owners, frame)
		if i % KEYFRAME_INTERVAL == 0:
			_keyframes.append(owners.duplicate())
		if int(frame["p"]) == PHASE_TICK_END:
			var tick := int(frame["t"])
			_tick_end_index[tick] = i
			max_tick = maxi(max_tick, tick)


func owner_code(owner: Variant) -> int:
	if owner == null:
		return -1
	return int(entrant_index.get(String(owner), -1))


func _apply_changes(owners: PackedInt32Array, frame: Dictionary) -> void:
	for change in frame.get("owner_changes", []):
		owners[int(change[0])] = owner_code(change[1])


func frame_count() -> int:
	return frames.size()


func tick_of(index: int) -> int:
	return int(frames[index]["t"])


func is_tick_end(index: int) -> bool:
	return int(frames[index]["p"]) == PHASE_TICK_END


## Index of the TICK_END frame of `tick`, clamped to the recorded range.
func index_for_tick_end(tick: int) -> int:
	return int(_tick_end_index[clampi(tick, 0, max_tick)])


func owners_at(index: int) -> PackedInt32Array:
	if index == _cached_index:
		return _cached_owners
	if _cached_index >= 0 and index == _cached_index + 1:
		_apply_changes(_cached_owners, frames[index])
	else:
		var key := index / KEYFRAME_INTERVAL
		_cached_owners = _keyframes[key].duplicate()
		for i in range(key * KEYFRAME_INTERVAL + 1, index + 1):
			_apply_changes(_cached_owners, frames[i])
	_cached_index = index
	return _cached_owners


func state(index: int) -> Dictionary:
	var frame: Dictionary = frames[index]
	return {
		"mode": "broadcast",
		"tick": int(frame["t"]),
		"phase": int(frame["p"]),
		"owners": owners_at(index),
		"anchors": frame["anchors"],
		"disrupted": frame["disrupted"],
		"alive": frame["alive"],
		"caption": caption(index),
	}


func caption(index: int) -> String:
	var frame: Dictionary = frames[index]
	match int(frame["p"]):
		PHASE_TICK_END:
			var text := "Tick %d ends" % int(frame["t"])
			for entrant in eliminated_at(index):
				var i := int(entrant_index[entrant])
				var core_size := (entrants[i]["core"] as Array).size()
				text += "  -  %s %s eliminated (core %d/%d)" % [entrant, entrants[i]["name"], core_cells_owned(index, i), core_size]
			return text
		0:
			return "%s/%s receives its observation" % [frame["actor"], frame["process"]]
	var text := "%s/%s %s" % [frame["actor"], frame["process"], String(frame["kind"]).to_upper()]
	if frame["operand"] != null:
		text += " %d" % int(frame["operand"])
	if frame["status"] != null:
		text += " -> %s" % frame["status"]
	if frame["sensed"] != null:
		text += " (sample taken; delivered next callback)"
	return text


## Entrants alive in the previous frame but not in this one.
func eliminated_at(index: int) -> Array:
	if index == 0:
		return []
	var before: Array = frames[index - 1]["alive"]
	var now: Array = frames[index]["alive"]
	return before.filter(func(entrant: Variant) -> bool: return not now.has(entrant))


## Cells of `entrant`'s own core it still owns at `index`.
func core_cells_owned(index: int, entrant: int) -> int:
	var owners := owners_at(index)
	var count := 0
	for cell in entrants[entrant]["core"]:
		if owners[int(cell)] == entrant:
			count += 1
	return count
