extends Node
## Reusable procedural sound-effects player.
##
## Plays the clips of SoundSynth (generated on first use and cached) through a
## small pool of voices on its own audio bus, behind a hard limiter. It only
## ever plays what it is handed: it reads no match data and changes nothing
## outside itself, so it cannot affect playback, ordering or results.
##
## Throttling runs on a clock advanced only by play_cues(), so the same cues
## and time steps always start the same voices:
## - cues handed over together are merged per (sound, voice);
## - the same (sound, voice) does not restart within MIN_GAP of its last start;
## - at most MAX_STARTS_PER_UPDATE voices start per call, highest priority first;
## - overall, starts draw on a budget of RATE per second (bursts up to BURST);
##   an elimination or victory (priority EXEMPT and above) always plays;
## - with every voice busy, a new cue takes over the lowest-priority voice,
##   but never one of higher priority than itself.
##
## stop_all() is the cut every seek makes: voices stop, and the clock and
## throttle restart from nothing, so what is heard after a seek never depends
## on what came before it. pause() and resume() hold and continue the voices.
##
## On/off and volume are kept for the application session (not saved to disk):
## every instance shares them.

const Synth := preload("res://scripts/sound_synth.gd")

const BUS := "SpectatorSFX"
const VOICES := 8
const MAX_STARTS_PER_UPDATE := 3
const RATE := 10.0  # starts per second, sustained
const BURST := 4.0
const EXEMPT := 6  # priorities at or above this ignore the budget
const DEFAULT_VOLUME := 0.6
## Higher wins when cues compete.
const PRIORITY := {
	"victory": 7, "elimination": 6, "core_damage": 5, "disruption": 4, "write": 3,
	"contact": 2, "receipt": 2, "sense": 1, "move_up": 0, "move_down": 0,
}
## Shortest gap in seconds between two starts of the same (sound, voice).
const MIN_GAP := {
	"victory": 0.0, "elimination": 0.0, "core_damage": 0.25, "disruption": 0.45, "write": 0.15,
	"contact": 0.18, "receipt": 0.18, "sense": 0.2, "move_up": 0.2, "move_down": 0.2,
}

static var session_enabled := true
static var session_volume := DEFAULT_VOLUME

## Voices started since the last take_played() or stop_all(), as
## {"i", "sound", "variant", "merged"} (merged = cues it stood for).
var played: Array = []

var _players: Array[AudioStreamPlayer] = []
var _voice_priority := PackedInt32Array()
var _voice_end := PackedFloat64Array()  # clock time each voice finishes
var _streams: Dictionary = {}  # "sound/variant" -> AudioStreamWAV
var _last_start: Dictionary = {}  # "sound/variant" -> clock time
var _clock := 0.0
var _tokens := BURST
var _paused := false


func _init() -> void:
	name = "SoundEffects"
	var bus := AudioServer.get_bus_index(BUS)
	if bus < 0:
		AudioServer.add_bus()
		bus = AudioServer.bus_count - 1
		AudioServer.set_bus_name(bus, BUS)
		AudioServer.set_bus_send(bus, "Master")
		AudioServer.add_bus_effect(bus, AudioEffectHardLimiter.new())
	for v in VOICES:
		var player := AudioStreamPlayer.new()
		player.bus = BUS
		add_child(player)
		_players.append(player)
	_voice_priority.resize(VOICES)
	_voice_end.resize(VOICES)
	_voice_end.fill(0.0)
	_apply_settings()


func is_enabled() -> bool:
	return session_enabled


func volume() -> float:
	return session_volume


func set_enabled(value: bool) -> void:
	session_enabled = value
	if not value:
		stop_all()
	_apply_settings()


## Master volume, 0 to 1 (linear).
func set_volume(value: float) -> void:
	session_volume = clampf(value, 0.0, 1.0)
	_apply_settings()


func _apply_settings() -> void:
	var bus := AudioServer.get_bus_index(BUS)
	AudioServer.set_bus_mute(bus, not _audible())
	AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(session_volume, 0.0001)))


func _audible() -> bool:
	return session_enabled and session_volume > 0.0


func is_paused() -> bool:
	return _paused


## The cached stream of `sound` voiced as `variant`.
func stream(sound: String, variant: int) -> AudioStreamWAV:
	var key := "%s/%d" % [sound, variant]
	if not _streams.has(key):
		_streams[key] = Synth.stream(sound, variant)
	return _streams[key]


## Plays one sound now (subject to the same throttle).
func play(sound: String, variant: int = 0) -> bool:
	return not play_cues([{"i": -1, "sound": sound, "variant": variant}], 0.0).is_empty()


## Advances the clock by `elapsed` seconds, then starts voices for `cues` as
## throttled above. Returns the voices started. Muted, at zero volume or
## paused, nothing starts.
func play_cues(cues: Array, elapsed: float) -> Array:
	_clock += maxf(elapsed, 0.0)
	_tokens = minf(BURST, _tokens + RATE * maxf(elapsed, 0.0))
	if cues.is_empty() or not _audible() or _paused:
		return []
	var merged: Dictionary = {}
	var order: Array = []
	for cue in cues:
		var key := "%s/%d" % [cue["sound"], int(cue["variant"])]
		if merged.has(key):
			merged[key]["merged"] += 1
		else:
			merged[key] = {"i": int(cue["i"]), "sound": String(cue["sound"]), "variant": int(cue["variant"]), "merged": 1}
			order.append(key)
	# Highest priority first; equal priorities keep the order the cues came in.
	var rank: Dictionary = {}
	for k in order.size():
		rank[order[k]] = k
	order.sort_custom(func(a: String, b: String) -> bool:
		var pa: int = PRIORITY[merged[a]["sound"]]
		var pb: int = PRIORITY[merged[b]["sound"]]
		return pa > pb if pa != pb else int(rank[a]) < int(rank[b])
	)
	var started: Array = []
	for key in order:
		if started.size() >= MAX_STARTS_PER_UPDATE:
			break
		var cue: Dictionary = merged[key]
		var exempt: bool = PRIORITY[cue["sound"]] >= EXEMPT
		if not exempt and _tokens < 1.0:
			continue
		if _last_start.has(key) and _clock - float(_last_start[key]) < float(MIN_GAP[cue["sound"]]):
			continue
		var voice := _free_voice(int(PRIORITY[cue["sound"]]))
		if voice < 0:
			continue
		_start(voice, cue)
		_last_start[key] = _clock
		if not exempt:
			_tokens -= 1.0
		started.append(cue)
	played.append_array(started)
	return started


func _free_voice(priority: int) -> int:
	var lowest := -1
	for v in VOICES:
		if _voice_end[v] <= _clock:
			return v
		if _voice_priority[v] <= priority and (lowest < 0 or _voice_priority[v] < _voice_priority[lowest] or (_voice_priority[v] == _voice_priority[lowest] and _voice_end[v] < _voice_end[lowest])):
			lowest = v
	return lowest


func _start(voice: int, cue: Dictionary) -> void:
	var player := _players[voice]
	player.stop()
	player.stream = stream(cue["sound"], cue["variant"])
	_voice_priority[voice] = int(PRIORITY[cue["sound"]])
	_voice_end[voice] = _clock + Synth.length(cue["sound"])
	if player.is_inside_tree():
		player.play()


## Voices still sounding by the throttle clock.
func active_voices() -> int:
	var count := 0
	for v in VOICES:
		count += 1 if _voice_end[v] > _clock else 0
	return count


func pause() -> void:
	_paused = true
	for player in _players:
		player.stream_paused = true


func resume() -> void:
	_paused = false
	for player in _players:
		player.stream_paused = false


## Stops every voice and restarts the clock and throttle from nothing.
func stop_all() -> void:
	for player in _players:
		player.stop()
		player.stream_paused = false
	_paused = false
	_voice_end.fill(0.0)
	_last_start.clear()
	_clock = 0.0
	_tokens = BURST
	played.clear()


## The voices started since the last call (or the last stop_all()), then forgets them.
func take_played() -> Array:
	var out := played
	played = []
	return out
