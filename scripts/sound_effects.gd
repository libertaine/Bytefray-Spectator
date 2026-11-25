extends Node
## Reusable procedural sound-effects player.
##
## Plays the clips of SoundSynth and the Announcer (generated on first use and
## cached) through a small pool of voices on its own audio bus, behind a hard
## limiter, so the Sound toggle and volume govern the announcer too. It only
## ever plays what it is handed: it reads no match data and changes nothing
## outside itself, so it cannot affect playback, ordering or results.
##
## Throttling runs on a clock advanced only by play_cues(), so the same cues
## and time steps always start the same voices:
## - cues handed over together are merged per (sound, voice);
## - the same (sound, voice) does not restart within MIN_GAP of its last start;
## - at most MAX_STARTS_PER_UPDATE voices start per call, highest priority first;
## - overall, starts draw on a budget of RATE per second (bursts up to BURST);
##   tactical turning points (priority >= TACTICAL_PRIORITY) can draw down to 1.0
##   token while background texture cues (priority < TACTICAL_PRIORITY) leave
##   TACTICAL_RESERVE tokens for upcoming tactical events;
##   an elimination, victory or victory call (priority EXEMPT and above)
##   always plays;
## - with every voice busy, a new cue takes over the lowest-priority voice,
##   but never one of higher priority than itself.
##
## stop_all() is the cut every seek makes: voices stop, and the clock and
## throttle restart from nothing, so what is heard after a seek never depends
## on what came before it. pause() and resume() hold and continue the voices.
##
## The opening sequence plays on a voice of its own (play_intro()), which no
## cue can take over; pausing holds it and any cut stops it.
##
## On/off and volume are kept for the application session (not saved to disk):
## every instance shares them.

const Synth := preload("res://scripts/sound_synth.gd")
const Announcer := preload("res://scripts/announcer.gd")

const BUS := "SpectatorSFX"
const VOICES := 8
const MAX_STARTS_PER_UPDATE := 3
const RATE := 10.0  # starts per second, sustained
const BURST := 4.0
const EXEMPT := 6  # priorities at or above this ignore the budget
const TACTICAL_PRIORITY := 4  # priorities at or above this are tactical turning points
const TACTICAL_RESERVE := 1.5  # tokens reserved so routine texture never starves tactical cues
const DEFAULT_VOLUME := 0.6
## Higher wins when cues compete.
const PRIORITY := {
	"intro": 9, "announce": 8, "victory": 7, "elimination": 6,
	"core_damage": 5, "core_recovery": 5,
	"read_discovery": 4, "reacquire": 4, "disruption": 4, "contact": 4,
	"write": 2, "sense": 1, "receipt": 0, "move_up": 0, "move_down": 0,
}
## Shortest gap in seconds between two starts of the same (sound, voice).
const MIN_GAP := {
	"intro": 0.0, "announce": 0.0, "victory": 0.0, "elimination": 0.0,
	"core_damage": 0.22, "core_recovery": 0.22,
	"read_discovery": 0.18, "reacquire": 0.18, "disruption": 0.40, "contact": 0.18,
	"write": 0.28, "sense": 0.28, "receipt": 0.35, "move_up": 0.32, "move_down": 0.32,
}

static var session_enabled := true
static var session_volume := DEFAULT_VOLUME

## Voices started since the last take_played() or stop_all(), as
## {"i", "sound", "variant", "merged"} (merged = cues it stood for).
var played: Array = []

var _players: Array[AudioStreamPlayer] = []
var _intro_player: AudioStreamPlayer
var _intro: AudioStreamWAV
var _voice_priority := PackedInt32Array()
var _voice_end := PackedFloat64Array()  # clock time each voice finishes
var _streams: Dictionary = {}  # "sound/variant" (or "announce/name/seat") -> AudioStreamWAV or null
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
	_intro_player = AudioStreamPlayer.new()
	_intro_player.bus = BUS
	add_child(_intro_player)
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


## On, at a volume above zero.
func is_audible() -> bool:
	return _audible()


func is_paused() -> bool:
	return _paused


## The cached stream of `sound` voiced as `variant`.
func stream(sound: String, variant: int) -> AudioStreamWAV:
	var key := "%s/%d" % [sound, variant]
	if not _streams.has(key):
		_streams[key] = Synth.stream(sound, variant)
	return _streams[key]


## The stream a cue plays, or null if it has nothing to play (a victory call
## for which no verified clips exist).
func stream_for(cue: Dictionary) -> AudioStreamWAV:
	if cue["sound"] != "announce":
		return stream(cue["sound"], cue["variant"])
	var key := "announce/%s/%s" % [cue["name"], cue["seat"]]
	if not _streams.has(key):
		var call := Announcer.victory_call(String(cue["name"]), String(cue["seat"]))
		_streams[key] = null if call.is_empty() else Announcer.stream_of(call)
	return _streams[key]


## The opening sequence's stream (rumble, then FIGHT).
func intro_stream() -> AudioStreamWAV:
	if _intro == null:
		_intro = Announcer.stream_of(Announcer.intro())
	return _intro


## Starts the opening sequence at frame `index` and returns its length in
## seconds, or 0 (nothing started) when muted or at zero volume.
func play_intro(index: int) -> float:
	if not _audible():
		return 0.0
	_intro_player.stop()
	_intro_player.stream_paused = false
	_intro_player.stream = intro_stream()
	if _intro_player.is_inside_tree():
		_intro_player.play()
	played.append({"i": index, "sound": "intro", "variant": 0, "merged": 1})
	return _intro.get_length()


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
			if cue.has("name"):
				merged[key]["name"] = String(cue["name"])
				merged[key]["seat"] = String(cue["seat"])
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
		var prio: int = PRIORITY[cue["sound"]]
		var exempt: bool = prio >= EXEMPT
		var min_tokens: float = 1.0 if prio >= TACTICAL_PRIORITY else (1.0 + TACTICAL_RESERVE)
		if not exempt and _tokens < min_tokens:
			continue
		if _last_start.has(key) and _clock - float(_last_start[key]) < float(MIN_GAP[cue["sound"]]):
			continue
		var wav := stream_for(cue)
		if wav == null:
			continue
		var voice := _free_voice(prio)
		if voice < 0:
			continue
		_start(voice, cue, wav)
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


func _start(voice: int, cue: Dictionary, wav: AudioStreamWAV) -> void:
	var player := _players[voice]
	player.stop()
	player.stream = wav
	_voice_priority[voice] = int(PRIORITY[cue["sound"]])
	_voice_end[voice] = _clock + wav.get_length()
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
	for player in _players + [_intro_player]:
		player.stream_paused = true


func resume() -> void:
	_paused = false
	for player in _players + [_intro_player]:
		player.stream_paused = false


## Stops every voice (the opening sequence too) and restarts the clock and
## throttle from nothing.
func stop_all() -> void:
	for player in _players + [_intro_player]:
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
