extends RefCounted
## Agent-perspective playback model over agent_a.json.
##
## agent_a.json is built only from Bytefray's receipt-only SensingView, so this
## model holds nothing beyond what the entrant was delivered: its own core and
## processes, delivered samples and reads, historical contacts and its own
## events. It never sees broadcast data.

const PHASE_TICK_END := 2
const RECENT_EVENT_LIMIT := 10

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


func frame_count() -> int:
	return frames.size()


func tick_of(index: int) -> int:
	return int(frames[index]["t"])


func is_tick_end(index: int) -> bool:
	return int(frames[index]["p"]) == PHASE_TICK_END


func index_for_tick_end(tick: int) -> int:
	return int(_tick_end_index[clampi(tick, 0, max_tick)])


func recent_events(index: int, limit: int = RECENT_EVENT_LIMIT) -> Array:
	var collected: Array = []
	var i := index
	while i >= 0 and collected.size() < limit:
		var events: Array = frames[i]["events"]
		for j in range(events.size() - 1, -1, -1):
			collected.append(events[j])
			if collected.size() >= limit:
				break
		i -= 1
	return collected


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
	}
