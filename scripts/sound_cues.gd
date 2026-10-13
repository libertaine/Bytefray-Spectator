extends RefCounted
## Sound cues derived from recorded presentation frames.
##
## Every function is a pure function of a model and a frame range (from, to]:
## the frames playback has just passed. Nothing here plays audio, and nothing
## here changes playback or the models. A cue is {"i": frame, "sound": name,
## "variant": voice}, in frame order.
##
## Broadcast cues come from broadcast.json through the broadcast model and its
## effects. Agent A cues come from agent_a.json through the agent model alone:
## its own applied SENSE, WRITE and MOVE and its delivered samples, voiced as
## Agent A. Agent A is never delivered a WRITE's outcome, an opponent action,
## a disruption, an elimination or the result, so none of those has an Agent A
## cue.

const PHASE_OBSERVATION := 0
const PHASE_ACTION := 1
const PHASE_TICK_END := 2
## Sounds the Agent A perspective can produce.
const AGENT_SOUNDS := ["sense", "receipt", "contact", "write", "move_up", "move_down"]
## Agent A's voice, matching its ring colour (RingView.agent_color, entrant colour 0).
const AGENT_VARIANT := 0


## Broadcast cues of the frames in (from, to].
static func broadcast_cues(model, effects, from: int, to: int) -> Array:
	var cues: Array = []
	for i in range(maxi(from + 1, 1), mini(to, model.frame_count() - 1) + 1):
		var frame: Dictionary = model.frames[i]
		match int(frame["p"]):
			PHASE_ACTION:
				var action: Dictionary = effects.action_at(i)
				if action.is_empty() or action["outcome"] == "refused":
					continue
				match String(action["kind"]):
					"write":
						# A core cell lost is heard in the core owner's voice.
						if action["core_change"] == "damage":
							cues.append(_cue(i, "core_damage", int(action["core_owner"])))
						else:
							cues.append(_cue(i, "write", int(action["entrant"])))
					"move":
						cues.append(_cue(i, "move_down" if _backward(frame) else "move_up", int(action["entrant"])))
					"sense":
						cues.append(_cue(i, "sense", int(action["entrant"])))
			PHASE_OBSERVATION:
				var sense: Dictionary = effects.delivery_at(i)
				if not sense.is_empty():
					var found := not (sense["sensed"] as Array).is_empty()
					cues.append(_cue(i, "contact" if found else "receipt", int(sense["entrant"])))
			PHASE_TICK_END:
				cues.append_array(_tick_end_cues(model, i))
	return cues


## A process newly disrupted at this tick end (not disrupted at the previous
## one), each entrant eliminated here, and at the recorded end the winner.
static func _tick_end_cues(model, i: int) -> Array:
	var cues: Array = []
	var tick: int = model.tick_of(i)
	var before: Array = model.frames[model.index_for_tick_end(tick - 1)]["disrupted"] if tick > 0 else []
	for pair in model.frames[i]["disrupted"]:
		if not before.has(pair):
			cues.append(_cue(i, "disruption", int(model.entrant_index.get(String(pair[0]), -1))))
	for entrant in model.eliminated_at(i):
		cues.append(_cue(i, "elimination", int(model.entrant_index[entrant])))
	var winner := String(model.result["winner"])
	if tick >= model.max_tick and i == model.index_for_tick_end(model.max_tick) and model.entrant_index.has(winner):
		cues.append(_cue(i, "victory", int(model.entrant_index[winner])))
	return cues


## Agent A cues of the frames in (from, to], from agent_a.json alone.
static func agent_cues(model, from: int, to: int) -> Array:
	var cues: Array = []
	for i in range(maxi(from + 1, 1), mini(to, model.frame_count() - 1) + 1):
		var frame: Dictionary = model.frames[i]
		for sample in frame["samples"]:
			cues.append(_cue(i, "contact" if not (sample["addresses"] as Array).is_empty() else "receipt", AGENT_VARIANT))
		for event in frame["events"]:
			if event["status"] != "APPLIED":
				continue
			match String(event["kind"]):
				"sense", "write":
					cues.append(_cue(i, String(event["kind"]), AGENT_VARIANT))
				"move":
					cues.append(_cue(i, "move_down" if _backward(event) else "move_up", AGENT_VARIANT))
	return cues


## A MOVE falls in pitch when its recorded operand is negative (counter-clockwise).
static func _backward(record: Dictionary) -> bool:
	return record["operand"] != null and int(record["operand"]) < 0


static func _cue(i: int, sound: String, entrant: int) -> Dictionary:
	return {"i": i, "sound": sound, "variant": maxi(entrant, 0)}
