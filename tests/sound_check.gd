extends SceneTree
## Headless check of the procedural sound effects and the announcer. Nothing needs to be audible:
## it checks the generated clips, the cues against references this script
## builds itself from the raw presentation files, and what the viewer starts
## during playback, seeking, pausing, muting and switching.
##
## Run: godot --headless --path . --script res://tests/sound_check.gd
## Exit code 0 = pass, 1 = failure (each failure is printed).

const FixtureLoader := preload("res://scripts/fixture_loader.gd")
const BroadcastModel := preload("res://scripts/broadcast_model.gd")
const BroadcastEffects := preload("res://scripts/broadcast_effects.gd")
const AgentModel := preload("res://scripts/agent_model.gd")
const Synth := preload("res://scripts/sound_synth.gd")
const Cues := preload("res://scripts/sound_cues.gd")
const SoundEffects := preload("res://scripts/sound_effects.gd")
const Announcer := preload("res://scripts/announcer.gd")
const SHOWCASE := "res://fixtures/showcase/presentation"
const DEV := "res://fixtures/dev/presentation"
const FPS := 60.0

var failures: PackedStringArray = []
var checks := 0
var _main: Node
var _frame := 0


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("FAIL: ", message)


func _initialize() -> void:
	# Session defaults, before anything changes them.
	check(SoundEffects.session_enabled and is_equal_approx(SoundEffects.session_volume, 0.6), "sound defaults to on at 60%")
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 1:
		var started := Time.get_ticks_msec()
		_check_synth()
		var heard := {}
		for dir in [SHOWCASE, DEV]:
			_check_cues(dir, heard)
		for sound in Synth.SOUNDS:
			check(heard.has(sound), "the fixtures exercise the %s sound" % sound)
		_check_announcer_assets()
		if _main.load_error == "":
			_check_viewer(_main)
			_check_announcer(_main)
		else:
			check(false, "main loads the showcase: %s" % _main.load_error)
		print("sound checks run in %d ms" % (Time.get_ticks_msec() - started))
	if _frame < 3:
		return false
	print("%d checks, %d failures" % [checks, failures.size()])
	print("SOUND CHECK %s" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)
	return true


# ---------------------------------------------------------------------------
# Generated clips
# ---------------------------------------------------------------------------

func _check_synth() -> void:
	var started := Time.get_ticks_msec()
	var all_bytes: Dictionary = {}
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	for sound in Synth.SOUNDS:
		var lead := int(round(float(Synth.LEAD_IN.get(sound, 0.0)) * Synth.MIX_RATE))
		var audible: float = Synth.DURATION[sound]
		check(audible >= 0.1 and audible <= 0.4, "%s lasts 0.1-0.4 s (%.2f)" % [sound, audible])
		for variant in Synth.VARIANTS.size():
			var samples := Synth.render(sound, variant)
			var wav := Synth.stream(sound, variant)
			var name := "%s/%d" % [sound, variant]
			check(wav.format == AudioStreamWAV.FORMAT_16_BITS and wav.mix_rate == Synth.MIX_RATE and not wav.stereo, "%s is 16-bit mono PCM" % name)
			check(wav.data.size() == samples.size() * 2 and is_equal_approx(wav.get_length(), Synth.length(sound)), "%s length %.3f s" % [name, wav.get_length()])
			check(wav.data == Synth.stream(sound, variant).data, "%s is byte-identical when generated again" % name)
			var peak := 0.0
			for n in samples.size():
				peak = maxf(peak, absf(samples[n]))
			check(peak > 0.05 and peak <= 1.0, "%s is audible and unclipped (peak %.3f)" % [name, peak])
			var silent_lead := true
			for n in lead:
				silent_lead = silent_lead and samples[n] == 0.0
			check(silent_lead, "%s lead-in is silent" % name)
			check(absf(samples[lead]) < 0.02 and absf(samples[samples.size() - 1]) < 0.02, "%s starts and ends without a click" % name)
			all_bytes[name] = wav.data
			digest.update(wav.data)
		check(all_bytes["%s/0" % sound] != all_bytes["%s/1" % sound], "%s differs between the two competitors" % sound)
	var distinct := {}
	for data in all_bytes.values():
		distinct[data] = true
	check(distinct.size() == all_bytes.size(), "every sound and voice is distinct")
	print("synth: %d clips in %d ms, sha256 %s" % [all_bytes.size(), Time.get_ticks_msec() - started, digest.finish().hex_encode()])


# ---------------------------------------------------------------------------
# Cues against references built from the raw files
# ---------------------------------------------------------------------------

func _check_cues(dir: String, heard: Dictionary) -> void:
	var loaded := FixtureLoader.load_manifest(dir)
	var manifest: Dictionary = loaded["manifest"]
	var b: Dictionary = FixtureLoader.load_presentation(dir, manifest, "broadcast")["document"]
	var a: Dictionary = FixtureLoader.load_presentation(dir, manifest, "agent_a")["document"]
	var model := BroadcastModel.new(b)
	var effects := BroadcastEffects.new(model)
	var agent := AgentModel.new(a)
	var name := dir.get_base_dir().get_file()

	var reference := _broadcast_reference(b)
	check(reference[0].is_empty(), "%s: frame 0 (never passed by playback) has no broadcast cue" % name)
	var expected := _flatten(reference)
	var actual := Cues.broadcast_cues(model, effects, 0, model.frame_count() - 1)
	check(actual == expected, "%s: broadcast cues equal the reference (%d vs %d)" % [name, actual.size(), expected.size()])
	_first_difference(name + " broadcast", actual, expected)
	check(_chunked(func(f: int, t: int) -> Array: return Cues.broadcast_cues(model, effects, f, t), model.frame_count()) == actual, "%s: broadcast cues do not depend on how playback splits the frames" % name)

	var agent_reference := _agent_reference(a)
	check(agent_reference[0].is_empty(), "%s: Agent A frame 0 has no cue" % name)
	var agent_expected := _flatten(agent_reference)
	var agent_actual := Cues.agent_cues(agent, 0, agent.frame_count() - 1)
	check(agent_actual == agent_expected, "%s: Agent A cues equal the reference (%d vs %d)" % [name, agent_actual.size(), agent_expected.size()])
	_first_difference(name + " agent", agent_actual, agent_expected)
	check(_chunked(func(f: int, t: int) -> Array: return Cues.agent_cues(agent, f, t), agent.frame_count()) == agent_actual, "%s: Agent A cues do not depend on how playback splits the frames" % name)
	var agent_only := true
	for cue in agent_actual:
		agent_only = agent_only and Cues.AGENT_SOUNDS.has(cue["sound"]) and cue["variant"] == Cues.AGENT_VARIANT
	check(agent_only and not agent_actual.is_empty(), "%s: Agent A has only its own sounds, in its own voice" % name)

	# The call names whoever the record says won: in a copy whose recorded winner is
	# the other entrant (or a tie), the call follows the record, not the showcase.
	if name == "showcase":
		for winner in ["A", "tie"]:
			var other: Dictionary = b.duplicate(true)
			other["result"]["winner"] = winner
			var other_model := BroadcastModel.new(other)
			var last := other_model.frame_count() - 1
			var calls := Cues.broadcast_cues(other_model, BroadcastEffects.new(other_model), last - 1, last).filter(func(cue: Dictionary) -> bool: return cue["sound"] in ["announce", "victory"])
			var expected_calls: Array = [] if winner == "tie" else [{"i": last, "sound": "victory", "variant": 0}, {"i": last, "sound": "announce", "variant": 0, "name": "spectator_harrier", "seat": "A"}]
			check(calls == expected_calls, "a record won by %s gets %s" % [winner, expected_calls])

	# Neither fixture records a refused action, so refuse one of each in a copy.
	var refused_doc: Dictionary = b.duplicate(true)
	var k := 1
	while not (int(refused_doc["frames"][k]["p"]) == 1 and refused_doc["frames"][k]["kind"] == "write"):
		k += 1
	refused_doc["frames"][k]["status"] = "REFUSED"
	var refused_model := BroadcastModel.new(refused_doc)
	check(Cues.broadcast_cues(refused_model, BroadcastEffects.new(refused_model), k - 1, k).is_empty() and _broadcast_reference(refused_doc)[k].is_empty(), "%s: a refused WRITE makes no sound" % name)
	var refused_agent: Dictionary = a.duplicate(true)
	var j := 1
	while (refused_agent["frames"][j]["events"] as Array).filter(func(e: Dictionary) -> bool: return e["kind"] == "write").is_empty():
		j += 1
	for event in refused_agent["frames"][j]["events"]:
		event["status"] = "REFUSED"
	check(Cues.agent_cues(AgentModel.new(refused_agent), j - 1, j).filter(func(cue: Dictionary) -> bool: return cue["sound"] != "receipt" and cue["sound"] != "contact").is_empty(), "%s: a refused Agent A action makes no sound" % name)

	var counts := {}
	for cue in actual + agent_actual:
		counts[cue["sound"]] = int(counts.get(cue["sound"], 0)) + 1
		heard[cue["sound"]] = true
	print("%s cues: broadcast %d, agent %d, %s" % [name, actual.size(), agent_actual.size(), counts])
	if name == "showcase":
		var last := model.frame_count() - 1
		var ending: Array = actual.filter(func(cue: Dictionary) -> bool: return cue["i"] == last)
		check(ending.map(func(cue: Dictionary) -> String: return "%s/%d" % [cue["sound"], cue["variant"]]).has("elimination/0") and ending.has({"i": last, "sound": "victory", "variant": 1}), "showcase: A's elimination and B's victory sound at the recorded end only")
		check(actual.filter(func(cue: Dictionary) -> bool: return cue["sound"] in ["elimination", "victory"]).size() == ending.filter(func(cue: Dictionary) -> bool: return cue["sound"] in ["elimination", "victory"]).size(), "showcase: no elimination or victory sound before the end")


## Expected broadcast cues per frame, from broadcast.json alone: ownership is
## replayed from the recorded owners and owner_changes here.
func _broadcast_reference(doc: Dictionary) -> Array:
	var index := {}
	for e in doc["entrants"].size():
		index[String(doc["entrants"][e]["id"])] = e
	var arena := int(doc["arena_size"])
	var core_of := {}
	for e in doc["entrants"].size():
		for cell in doc["entrants"][e]["core"]:
			core_of[int(cell)] = e
	var frames: Array = doc["frames"]
	var owners := []
	var pending := {}
	var previous_disrupted: Array = []
	var last_tick := 0
	for frame in frames:
		if int(frame["p"]) == 2:
			last_tick = maxi(last_tick, int(frame["t"]))
	var out: Array = []
	for i in frames.size():
		var frame: Dictionary = frames[i]
		var cues: Array = []
		var before := -2
		if i == 0:
			owners = (frame["owners"] as Array).map(func(o: Variant) -> int: return -1 if o == null else int(index[String(o)]))
		if int(frame["p"]) == 1 and frame["address"] != null:
			before = owners[int(frame["address"]) % arena]
		if i > 0:
			for change in frame.get("owner_changes", []):
				owners[int(change[0])] = -1 if change[1] == null else int(index[String(change[1])])
		match int(frame["p"]):
			1:
				if frame["kind"] != null and frame["status"] == "APPLIED":
					var actor := int(index[String(frame["actor"])])
					match String(frame["kind"]):
						"write":
							var cell := int(frame["address"]) % arena
							var core := int(core_of.get(cell, -1))
							if core >= 0 and before == core and owners[cell] != core:
								cues.append({"i": i, "sound": "core_damage", "variant": core})
							else:
								cues.append({"i": i, "sound": "write", "variant": actor})
						"move":
							var down: bool = frame["operand"] != null and int(frame["operand"]) < 0
							cues.append({"i": i, "sound": "move_down" if down else "move_up", "variant": actor})
						"sense":
							cues.append({"i": i, "sound": "sense", "variant": actor})
							pending["%s/%s" % [frame["actor"], frame["process"]]] = frame["sensed"]
			0:
				var key := "%s/%s" % [frame["actor"], frame["process"]]
				if frame["sensed"] != null and pending.has(key) and pending[key] == frame["sensed"]:
					var found := not (frame["sensed"] as Array).is_empty()
					cues.append({"i": i, "sound": "contact" if found else "receipt", "variant": int(index[String(frame["actor"])])})
					pending.erase(key)
			2:
				for pair in frame["disrupted"]:
					if not previous_disrupted.has(pair):
						cues.append({"i": i, "sound": "disruption", "variant": int(index[String(pair[0])])})
				previous_disrupted = frame["disrupted"]
				if i > 0:
					for entrant in frames[i - 1]["alive"]:
						if not (frame["alive"] as Array).has(entrant):
							cues.append({"i": i, "sound": "elimination", "variant": int(index[String(entrant)])})
				var winner := String(doc["result"]["winner"])
				if int(frame["t"]) == last_tick and index.has(winner):
					cues.append({"i": i, "sound": "victory", "variant": int(index[winner])})
					cues.append({"i": i, "sound": "announce", "variant": int(index[winner]), "name": String(doc["entrants"][int(index[winner])]["name"]), "seat": winner})
		out.append(cues)
	return out


## Expected Agent A cues per frame, from agent_a.json alone.
func _agent_reference(doc: Dictionary) -> Array:
	var out: Array = []
	var frames: Array = doc["frames"]
	for i in frames.size():
		var cues: Array = []
		for sample in frames[i]["samples"]:
			cues.append({"i": i, "sound": "receipt" if (sample["addresses"] as Array).is_empty() else "contact", "variant": 0})
		for event in frames[i]["events"]:
			if event["status"] == "APPLIED" and event["kind"] in ["sense", "write", "move"]:
				var sound := String(event["kind"])
				if sound == "move":
					sound = "move_down" if event["operand"] != null and int(event["operand"]) < 0 else "move_up"
				cues.append({"i": i, "sound": sound, "variant": 0})
		out.append(cues)
	return out


func _flatten(per_frame: Array) -> Array:
	var out: Array = []
	for i in range(1, per_frame.size()):
		out.append_array(per_frame[i])
	return out


## The cues of (0, count - 1] gathered in random-sized steps, as playback at
## any speed would gather them.
func _chunked(cues_of: Callable, count: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 6131
	var out: Array = []
	var at := 0
	while at < count - 1:
		var to := mini(at + rng.randi_range(0, 120), count - 1)
		out.append_array(cues_of.call(at, to))
		at = to
	return out


func _first_difference(label: String, actual: Array, expected: Array) -> void:
	for k in mini(actual.size(), expected.size()):
		if actual[k] != expected[k]:
			printerr("  %s first difference at %d: %s vs %s" % [label, k, actual[k], expected[k]])
			return


# ---------------------------------------------------------------------------
# The viewer: playback, seeking, pausing, muting, switching
# ---------------------------------------------------------------------------

## Plays `steps` display frames of 1/FPS s; returns [index before, index after, started] per step.
func _play(m: Node, steps: int) -> Array:
	var out: Array = []
	for s in steps:
		if not m.playing:
			break
		var before: int = m.index
		m._process(1.0 / FPS)
		out.append([before, m.index, m.sound.take_played()])
	return out


func _check_viewer(m: Node) -> void:
	var sound: Node = m.sound
	check(m._sound_toggle.button_pressed and int(m._volume.value) == 60, "the Sound toggle starts on and the volume at 60")
	check(m._hint.text.contains("M sound") and (m._help.get_child(0) as Label).text.contains("Sound effects and arcade cues on / off"), "the key hint and help name the sound key")
	sound.take_played()

	# Seeking, stepping, jumping and dragging start nothing.
	m.set_perspective("broadcast")
	m.seek_tick(477)
	m.jump_to_end()
	m.step_frame(-5)
	m.step_frame(3)
	m.step_tick(-1)
	m.step_tick(1)
	m._timeline.value = 476
	m.jump_to_tick("477")
	m.restart()
	m.set_perspective("agent_a")
	m.seek_tick(200)
	m.set_perspective("broadcast")
	check(sound.take_played().is_empty() and sound.active_voices() == 0, "seeking, stepping, jumping and dragging start no sound")

	# Playback: every voice belongs to a frame playback has just passed (in sync, never historical).
	m.seek_tick(100)
	m.ticks_per_second = 5.0
	m.set_playing(true)
	var start: int = m.index
	var steps := _play(m, 120)
	var total := 0
	var in_sync := true
	for step in steps:
		for cue in step[2]:
			total += 1
			in_sync = in_sync and int(cue["i"]) > int(step[0]) and int(cue["i"]) <= int(step[1]) and int(cue["i"]) > start
	check(total > 0 and in_sync, "playback sounds only frames it has just passed (%d voices)" % total)
	# A seek while playing cuts and never sounds the frames jumped over or before.
	m._timeline.value = 300
	var landed: int = m.index
	check(sound.active_voices() == 0, "a seek while playing cuts the sound")
	steps = _play(m, 60)
	var after_seek := true
	for step in steps:
		for cue in step[2]:
			after_seek = after_seek and int(cue["i"]) > landed
	check(after_seek, "after a seek while playing, only frames after the new position sound")

	# Pause holds; resume at the same position continues; anything else starts from silence.
	_play(m, 2)
	m.set_playing(false)
	check(sound.is_paused(), "pausing holds the sound")
	var voices: int = sound.active_voices()
	m.set_playing(true)
	check(not sound.is_paused() and sound.active_voices() == voices, "resuming at the same position continues it (%d voices)" % voices)
	m.set_playing(false)
	m.step_frame(1)
	m.set_playing(true)
	check(not sound.is_paused() and sound.active_voices() == 0, "playing again after a step starts from silence")
	m.set_playing(false)

	# Mute and zero volume suppress everything.
	_key(m, KEY_M)
	check(not sound.is_enabled() and not m._sound_toggle.button_pressed and AudioServer.is_bus_mute(AudioServer.get_bus_index(SoundEffects.BUS)), "M mutes and unticks the Sound toggle")
	m.seek_tick(440)
	m.set_playing(true)
	var muted := 0
	for step in _play(m, 400):
		muted += (step[2] as Array).size()
	check(muted == 0 and sound.active_voices() == 0, "muted playback starts no sound")
	m.set_playing(false)
	m._sound_toggle.button_pressed = true
	check(sound.is_enabled() and not AudioServer.is_bus_mute(AudioServer.get_bus_index(SoundEffects.BUS)), "the Sound toggle turns sound back on")
	m._volume.value = 0
	m.seek_tick(440)
	m.set_playing(true)
	var silent := 0
	for step in _play(m, 200):
		silent += (step[2] as Array).size()
	check(silent == 0, "zero volume starts no sound")
	m.set_playing(false)

	# Session persistence: the settings outlive a fixture load and a new player.
	m._volume.value = 30
	check(is_equal_approx(sound.volume(), 0.3), "the volume slider sets the master volume")
	var other := SoundEffects.new()
	check(is_equal_approx(other.volume(), 0.3) and other.is_enabled(), "a new player in this session has the same settings")
	other.free()
	m.load_fixture(DEV)
	m.load_fixture(SHOWCASE)
	check(is_equal_approx(sound.volume(), 0.3) and int(m._volume.value) == 30 and m._sound_toggle.button_pressed, "settings survive a fixture load")
	m._volume.value = 60

	# The recorded end: elimination and victory sound on the final frame and ring out.
	m.set_perspective("broadcast")
	m.seek_tick(476)
	m.ticks_per_second = 5.0
	m.set_playing(true)
	var final := []
	while m.playing:
		final = _play(m, 1)[0]
	var ending: Array = (final[2] as Array).map(func(cue: Dictionary) -> String: return cue["sound"])
	check(ending.has("elimination") and ending.has("victory") and int(final[1]) == m.frame_count() - 1, "the recorded end sounds the elimination and the victory (%s)" % [ending])
	check(not sound.is_paused() and sound.active_voices() >= 2, "the last sounds ring out after playback stops")

	_check_rapid(m)
	_check_determinism(m)
	_check_agent(m)
	sound.stop_all()


## Fast playback through the whole showcase stays within the throttle.
func _check_rapid(m: Node) -> void:
	for speed in [5.0, 20.0, 200.0]:
		m.set_perspective("broadcast")
		m.restart()
		m.ticks_per_second = speed
		m.set_playing(true)
		var clock := 0.0
		var last := {}
		var worst_gap := INF
		var most := 0
		var voices := 0
		var started := 0
		var cues := 0
		var seconds := 0.0
		var budgeted := PackedFloat64Array()  # start times of sounds the budget covers
		while m.playing:
			var before: int = m.index
			m._process(1.0 / FPS)
			clock += 1.0 / FPS
			seconds += 1.0 / FPS
			cues += Cues.broadcast_cues(m.broadcast, m.effects, before, m.index).size()
			var step: Array = m.sound.take_played()
			most = maxi(most, step.size())
			voices = maxi(voices, m.sound.active_voices())
			started += step.size()
			for cue in step:
				var key := "%s/%d" % [cue["sound"], cue["variant"]]
				if last.has(key) and SoundEffects.MIN_GAP[cue["sound"]] > 0.0:
					worst_gap = minf(worst_gap, (clock - float(last[key])) / SoundEffects.MIN_GAP[cue["sound"]])
				last[key] = clock
				if SoundEffects.PRIORITY[cue["sound"]] < SoundEffects.EXEMPT:
					budgeted.append(clock)
		check(most <= SoundEffects.MAX_STARTS_PER_UPDATE and voices <= SoundEffects.VOICES and worst_gap >= 1.0 - 1e-9, "%d ticks/s: throttled (at most %d starts per frame, %d voices, gap ratio %.2f)" % [speed, most, voices, worst_gap])
		# Any one-second window holds at most RATE + BURST budgeted starts.
		var busiest := 0
		var first := 0
		for k in budgeted.size():
			while budgeted[k] - budgeted[first] >= 1.0 - 1e-9:
				first += 1
			busiest = maxi(busiest, k - first + 1)
		check(busiest <= int(SoundEffects.RATE + SoundEffects.BURST), "%d ticks/s: at most %d sounds in any second (busiest %d)" % [speed, int(SoundEffects.RATE + SoundEffects.BURST), busiest])
		var bound := SoundEffects.BURST + SoundEffects.RATE * seconds
		check(started > 0 and budgeted.size() <= bound, "%d ticks/s: %d of %d cues started in %.1f s (%d budgeted, bound %.0f)" % [speed, started, cues, seconds, budgeted.size(), bound])
		print("rapid %d ticks/s: %d cues, %d started, %.1f s, %.1f/s" % [speed, cues, started, seconds, started / seconds])


## Sound never changes playback; the same playback starts the same sounds.
func _check_determinism(m: Node) -> void:
	var runs: Array = []
	for enabled in [true, true, false]:
		m.set_sound_enabled(enabled)
		m.set_perspective("broadcast")
		m.seek_tick(380)
		m.ticks_per_second = 20.0
		m.set_playing(true)
		var positions := PackedInt32Array()
		var heard: Array = []
		var captions := PackedStringArray()
		while m.playing:
			m._process(1.0 / FPS)
			positions.append(m.index)
			captions.append(m._caption.text)
			heard.append(m.sound.take_played())
		runs.append([positions, heard, captions])
	m.set_sound_enabled(true)
	check(runs[0] == runs[1], "the same playback starts the same sounds")
	check(runs[0][0] == runs[2][0] and runs[0][2] == runs[2][2], "playback positions and captions are the same with sound on and off")
	check(runs[2][1].all(func(step: Array) -> bool: return step.is_empty()), "with sound off nothing starts")


## Agent A: only its own sounds, from its own record, and nothing carried over from Broadcast.
func _check_agent(m: Node) -> void:
	m.set_perspective("broadcast")
	m.seek_tick(400)
	m.ticks_per_second = 20.0
	m.set_playing(true)
	_play(m, 30)
	m.set_perspective("agent_a")
	check(m.sound.active_voices() == 0 and m.sound.take_played().is_empty(), "switching to Agent A cuts every broadcast sound")
	# What Agent A hears after the switch equals a fresh start at the same position,
	# so nothing of the broadcast playback (not even the throttle) carries over.
	var tick: int = m.current_tick()
	var after_switch := _play(m, 90).map(func(step: Array) -> Array: return step[2])
	m.set_playing(false)
	m.seek_tick(tick)
	m.set_playing(true)
	var fresh := _play(m, 90).map(func(step: Array) -> Array: return step[2])
	check(after_switch == fresh and not after_switch.all(func(s: Array) -> bool: return s.is_empty()), "Agent A sounds after a switch equal a fresh start there")
	var heard := {}
	var own := true
	while m.playing:
		var before: int = m.index
		m._process(1.0 / FPS)
		for cue in m.sound.take_played():
			heard[cue["sound"]] = true
			own = own and Cues.AGENT_SOUNDS.has(cue["sound"]) and cue["variant"] == Cues.AGENT_VARIANT and int(cue["i"]) > before and int(cue["i"]) <= m.index
	check(own and not heard.is_empty(), "Agent A playback sounds only its own actions and samples (%s)" % [heard.keys()])
	check(m.current_tick() == m.agent.max_tick, "Agent A playback stops at the end of its record")
	m.set_perspective("broadcast")


func _key(m: Node, keycode: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	m._unhandled_input(event)


# ---------------------------------------------------------------------------
# The announcer: voice clips, names, the opening sequence and the victory call
# ---------------------------------------------------------------------------

func _check_announcer_assets() -> void:
	var clips := Announcer.voice()
	var record: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Announcer.VOICE_DIR.path_join("voice.json")))
	check(Announcer.load_problems.is_empty() and clips.size() == (record["words"] as Dictionary).size(), "every announcer clip verifies against voice.json (%s)" % [Announcer.load_problems])
	for word in ["FIGHT", "WINS", "PLAYER", "A", "B", "BASTION", "HARRIER"]:
		check(clips.has(word), "the announcer has a clip for %s" % word)
	# A clip whose bytes differ from voice.json is never used.
	var dir := ProjectSettings.globalize_path("user://announcer_tamper")
	DirAccess.make_dir_recursive_absolute(dir)
	for word in record["words"]:
		var name := String(record["words"][word]["file"])
		var bytes := FileAccess.get_file_as_bytes(Announcer.VOICE_DIR.path_join(name))
		if word == "BASTION":
			bytes[bytes.size() / 2] = bytes[bytes.size() / 2] ^ 1
		var out := FileAccess.open(dir.path_join(name), FileAccess.WRITE)
		out.store_buffer(bytes)
		out.close()
	var voice_json := FileAccess.open(dir.path_join("voice.json"), FileAccess.WRITE)
	voice_json.store_string(JSON.stringify(record))
	voice_json.close()
	var tampered := Announcer.load_voice(dir)
	check(not tampered.has("BASTION") and tampered.has("WINS") and Announcer.load_problems.size() == 1, "a tampered clip is left out (%s)" % [Announcer.load_problems])
	for name in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(name))
	DirAccess.remove_absolute(dir)
	Announcer.load_problems = []
	check(Announcer.parse_wav(PackedByteArray([1, 2, 3])).is_empty(), "a file that is not 16-bit mono WAV gives no samples")

	# Names: from the agent name, with no winner written into the logic.
	check(Announcer.spoken_words("spectator_bastion") == PackedStringArray(["BASTION"]), "spectator_bastion is spoken BASTION")
	check(Announcer.spoken_words("v6_window_scout") == PackedStringArray(["WINDOW", "SCOUT"]), "v6_window_scout is spoken WINDOW SCOUT")
	check(Announcer.spoken_words("spectator_v2_iron-fist") == PackedStringArray(["IRON", "FIST"]), "prefixes and separators are dropped")
	check(Announcer.victory_words("spectator_bastion", "B") == PackedStringArray(["BASTION", "WINS"]), "the showcase winner is called BASTION WINS")
	check(Announcer.victory_words("spectator_harrier", "A") == PackedStringArray(["HARRIER", "WINS"]), "Harrier would be called HARRIER WINS")
	check(Announcer.victory_words("spectator_newcomer", "A") == PackedStringArray(["PLAYER", "A", "WINS"]), "a name without clips falls back to PLAYER A WINS")
	check(Announcer.victory_words("spectator_newcomer", "Z").is_empty() and Announcer.victory_call("spectator_newcomer", "Z").is_empty(), "with no clip for any form of the name there is no call")

	# The opening sequence: about 3 s, rising in intensity and pitch, ending with FIGHT.
	var rumble := Announcer.rumble()
	var intro := Announcer.intro()
	var seconds := intro.size() / float(Announcer.MIX_RATE)
	check(seconds > 2.5 and seconds < 3.3, "the opening sequence lasts about 3 s (%.2f s)" % seconds)
	var quarter := rumble.size() / 4
	var early := _rms(rumble, 0, quarter)
	var late := _rms(rumble, quarter * 3, quarter * 4)
	var crossings_early := _crossings(rumble, quarter / 2, quarter)
	var crossings_late := _crossings(rumble, quarter * 3, quarter * 3 + quarter / 2)
	check(late > 2.0 * early, "the rumble grows in intensity (rms %.3f -> %.3f)" % [early, late])
	check(crossings_late > 2 * crossings_early, "the rumble rises in pitch (%d -> %d zero crossings)" % [crossings_early, crossings_late])
	var fight: PackedFloat32Array = Announcer.voice()["FIGHT"]
	var at := int(round(Announcer.VOICE_AT * Announcer.MIX_RATE))
	check(intro.size() == at + fight.size() and _rms(intro, at, intro.size()) > 0.1, "the sequence ends with the original nonverbal FIGHT cue")
	check(Announcer.intro() == intro and Announcer.rumble() == rumble, "the opening sequence is the same every time")
	var call := Announcer.victory_call("spectator_bastion", "B")
	var delay := int(round(Announcer.CALL_DELAY * Announcer.MIX_RATE))
	check(_rms(call, 0, delay) == 0.0 and _rms(call, delay, call.size()) > 0.05, "the victory call waits for the victory sting, then plays nonverbal motifs (rms %.3f, %.2f s)" % [_rms(call, delay, call.size()), call.size() / float(Announcer.MIX_RATE)])


func _rms(samples: PackedFloat32Array, from: int, to: int) -> float:
	var total := 0.0
	for n in range(from, to):
		total += samples[n] * samples[n]
	return sqrt(total / maxf(1.0, to - from))


func _crossings(samples: PackedFloat32Array, from: int, to: int) -> int:
	var count := 0
	for n in range(from + 1, to):
		if (samples[n - 1] < 0.0) != (samples[n] < 0.0):
			count += 1
	return count


func _sounds(steps: Array) -> Array:
	var out: Array = []
	for step in steps:
		for cue in step[2]:
			out.append(cue["sound"])
	return out


func _check_announcer(m: Node) -> void:
	var sound: Node = m.sound
	m.set_sound_enabled(true)
	m._volume.value = 60
	for perspective in ["broadcast", "agent_a"]:
		# From the beginning: the opening sequence plays and holds the match clock.
		m.set_playing(false)
		m.set_perspective(perspective)
		m.restart()
		m.ticks_per_second = 20.0
		m.set_playing(true)
		var started: Array = sound.take_played()
		var length: float = m.intro_left()
		check(length > 2.5 and started.size() == 1 and started[0]["sound"] == "intro", "%s: playing from the start begins with the opening sequence (%.2f s)" % [perspective, length])
		check(m._caption.text == m.INTRO_CAPTION, "%s: the caption says the match starts after the opening cue" % perspective)
		var held := true
		var elapsed := 0.0
		for k in 30:  # 0.5 s
			m._process(1.0 / FPS)
			elapsed += 1.0 / FPS
			held = held and m.index == 0
		# Pausing holds the sequence: no time passes, and playing again continues it.
		m.set_playing(false)
		var left: float = m.intro_left()
		check(sound.is_paused() and sound._intro_player.stream_paused and left > 0.0, "%s: pausing during the opening sequence holds it" % perspective)
		m.set_playing(true)
		check(not sound.is_paused() and is_equal_approx(m.intro_left(), left) and sound.take_played().is_empty(), "%s: playing again continues the sequence without restarting it" % perspective)
		var sounds_during: Array = []
		while m.intro_left() > 0.0:
			var before: int = m.index
			m._process(1.0 / FPS)
			elapsed += 1.0 / FPS
			held = held and m.index == before and m.index == 0
			sounds_during.append_array(sound.take_played())
		check(held and sounds_during.is_empty(), "%s: the opening sequence never advances the match (%.2f s at index 0)" % [perspective, elapsed])
		check(absf(elapsed - length) < 1.0 / FPS + 1e-6, "%s: the match starts when the sequence ends (%.3f vs %.3f s)" % [perspective, elapsed, length])
		_play(m, 30)
		check(m.index > 0 and m._caption.text != m.INTRO_CAPTION, "%s: then the match plays" % perspective)
		m.set_playing(false)

	# Any later tick skips it; so does a seek during it.
	m.set_perspective("broadcast")
	m.seek_tick(5)
	m.set_playing(true)
	check(m.intro_left() == 0.0 and not _sounds([[0, 0, sound.take_played()]]).has("intro"), "playing from a later tick skips the opening sequence")
	m.set_playing(false)
	m.restart()
	m.set_playing(true)
	_play(m, 20)
	m._timeline.value = 50
	check(m.intro_left() == 0.0 and sound.active_voices() == 0, "a seek during the opening sequence ends it")
	m.step_frame(0)
	_play(m, 20)
	check(m.current_tick() > 50, "after the seek the match plays from the new position")
	m.set_playing(false)
	# Sound off (or volume 0) skips it, and turning sound off during it starts the match.
	m.set_sound_enabled(false)
	m.restart()
	m.set_playing(true)
	check(m.intro_left() == 0.0, "with sound off there is no opening sequence")
	m.set_playing(false)
	m.set_sound_enabled(true)
	m._volume.value = 0
	m.restart()
	m.set_playing(true)
	check(m.intro_left() == 0.0, "at zero volume there is no opening sequence")
	m.set_playing(false)
	m._volume.value = 60
	m.restart()
	m.set_playing(true)
	_play(m, 10)
	_key(m, KEY_M)
	check(m.intro_left() == 0.0 and sound.active_voices() == 0, "turning sound off during the opening sequence ends it")
	_play(m, 30)
	check(m.index > 0, "and the match starts")
	m.set_playing(false)
	_key(m, KEY_M)

	# Playback with and without the opening sequence visits the same positions.
	var runs: Array = []
	for enabled in [true, false]:
		m.set_sound_enabled(enabled)
		m.restart()
		m.ticks_per_second = 20.0
		m.set_playing(true)
		var positions := PackedInt32Array()
		var guard := 0
		while m.playing and positions.size() < 900 and guard < 2000:
			guard += 1
			var in_intro: bool = m.intro_left() > 0.0
			m._process(1.0 / FPS)
			if not in_intro:
				positions.append(m.index)
		runs.append(positions)
		m.set_playing(false)
	m.set_sound_enabled(true)
	check(runs[0] == runs[1], "the match plays the same positions with or without the opening sequence")

	# The victory call: once, at the recorded end, naming the verified winner.
	m.set_perspective("broadcast")
	var winner := String(m.broadcast.result["winner"])
	var entrant := int(m.broadcast.entrant_index[winner])
	check(winner == String(m.manifest["match"]["winner"]), "the broadcast winner is the manifest's verified winner (%s)" % winner)
	m.seek_tick(470)
	m.ticks_per_second = 5.0
	m.set_playing(true)
	var heard: Array = []
	var before_end := true
	while m.playing:
		for step in _play(m, 1):
			for cue in step[2]:
				heard.append(cue)
				before_end = before_end and (cue["sound"] != "announce" or int(cue["i"]) == m.frame_count() - 1)
	var calls: Array = heard.filter(func(cue: Dictionary) -> bool: return cue["sound"] == "announce")
	check(calls.size() == 1 and before_end and calls[0]["name"] == m.broadcast.entrants[entrant]["name"] and calls[0]["seat"] == winner, "one victory call, at the recorded end, for %s" % [calls])
	check(not calls.is_empty() and Announcer.victory_words(calls[0]["name"], calls[0]["seat"]) == PackedStringArray(["BASTION", "WINS"]), "the showcase cue sequence is BASTION then WINS")
	check(m._side.text.contains("Result: B spectator_bastion wins"), "the result shown is unchanged")
	# Seeking to the end, End, and playing again from the end never call again.
	var again: Array = []
	for k in 3:
		m.jump_to_end()
		m.seek_tick(477)
		m.set_playing(true)
		again.append_array(_sounds(_play(m, 5)))
		again.append_array(_sounds([[0, 0, sound.take_played()]]))
		m.set_playing(false)
	check(not again.has("announce") and not again.has("victory"), "repeated seeking to the end never repeats the call (%s)" % [again])
	# Muted, the end is silent; at zero volume too.
	for setting in ["off", "zero"]:
		if setting == "off":
			m.set_sound_enabled(false)
		else:
			m._volume.value = 0
		m.seek_tick(476)
		m.set_playing(true)
		var silent := _sounds(_play(m, 400))
		check(silent.is_empty(), "with sound %s the end has no call (%s)" % [setting, silent])
		m.set_playing(false)
		m.set_sound_enabled(true)
		m._volume.value = 60

	# A tie never names a winner, and Agent A never hears the call.
	m.load_fixture(DEV)
	m.seek_tick(995)
	m.ticks_per_second = 5.0
	m.set_playing(true)
	var tie := _sounds(_play(m, 400))
	check(not tie.has("announce") and not tie.has("victory") and m._side.text.contains("Result: tie"), "the tie at the end of the dev fixture has no victory call (%s)" % [tie])
	m.set_playing(false)
	m.load_fixture(SHOWCASE)
	m.set_perspective("agent_a")
	m.seek_tick(400)
	m.ticks_per_second = 60.0
	m.set_playing(true)
	var agent_heard := []
	while m.playing:
		agent_heard.append_array(_sounds(_play(m, 1)))
	var outcome := agent_heard.filter(func(s: String) -> bool: return s in ["announce", "victory", "elimination", "core_damage", "disruption"])
	check(outcome.is_empty() and not agent_heard.is_empty(), "Agent A hears no outcome and no victory call (%s)" % [outcome])
	m.set_perspective("broadcast")
	sound.stop_all()
