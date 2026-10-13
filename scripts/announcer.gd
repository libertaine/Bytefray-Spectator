extends RefCounted
## The arcade announcer: the opening sequence and the victory call.
##
## The opening is a procedural rumble that rises in pitch, harmonics, intensity
## and distortion, cuts out, and then the announcer says FIGHT (about 2.9 s in all).
## The victory call is "<NAME> WINS", spoken after the elimination burst and
## victory sting.
##
## The voice is the word clips under audio/announcer. They are made offline by
## exporter/make_announcer_voice.py (a Windows SAPI voice, then deterministic
## arcade processing), and nothing is synthesised as speech at run time. Each
## clip is checked against its SHA-256 in voice.json, and a clip that does not
## verify is never played.
##
## The winner is named from the verified broadcast record: the entrant whose id
## is the recorded winner. Its spoken name is its agent name without a leading
## "spectator" or version word (spectator_bastion -> BASTION, v6_window_scout
## -> WINDOW SCOUT; the same rule as the generator). If a word has no clip, the
## call falls back to "PLAYER <seat> WINS". Without those clips, only the
## victory sting is heard. A tie has no winner and no call.

const Synth := preload("res://scripts/sound_synth.gd")

const VOICE_DIR := "res://audio/announcer"
const MIX_RATE := 22050
const RUMBLE := 2.35  # seconds of rising rumble
const VOICE_AT := 2.41  # FIGHT starts here, after a 60 ms cut so the word stands clear
const WORD_GAP := 0.07  # seconds between words of a call
## The call waits for the elimination burst (0.4 s) and victory sting (0.3 s lead-in + 0.4 s).
const CALL_DELAY := 0.75
const VOICE_GAIN := 0.9

static var _voice: Dictionary = {}  # word -> PackedFloat32Array, verified
static var _loaded := false
static var load_problems: PackedStringArray = []


## Spoken words of an agent name (upper case, letters and digits only).
static func spoken_words(agent_name: String) -> PackedStringArray:
	var words := PackedStringArray()
	for part in agent_name.replace("-", "_").replace(" ", "_").split("_", false):
		words.append(part.to_upper())
	var version := RegEx.create_from_string("^V\\d+$")
	while not words.is_empty() and (words[0] == "SPECTATOR" or version.search(words[0]) != null):
		words.remove_at(0)
	var plain := RegEx.create_from_string("^[A-Z0-9]+$")
	var out := PackedStringArray()
	for word in words:
		if plain.search(word) != null:
			out.append(word)
	return out


## The verified word clips, loaded once.
static func voice() -> Dictionary:
	if not _loaded:
		_loaded = true
		_voice = load_voice(VOICE_DIR)
	return _voice


## Loads and verifies every clip listed in `dir`/voice.json. Problems are kept
## in load_problems; a clip with a problem is left out.
static func load_voice(dir: String) -> Dictionary:
	load_problems = []
	var out := {}
	var text := FileAccess.get_file_as_string(dir.path_join("voice.json"))
	var record: Variant = JSON.parse_string(text) if text != "" else null
	if not (record is Dictionary and record.get("words") is Dictionary and int(record.get("mix_rate", 0)) == MIX_RATE):
		load_problems.append("voice.json missing or unreadable")
		return out
	for word in record["words"]:
		var entry: Dictionary = record["words"][word]
		var bytes := FileAccess.get_file_as_bytes(dir.path_join(String(entry["file"])))
		var hashing := HashingContext.new()
		hashing.start(HashingContext.HASH_SHA256)
		hashing.update(bytes)
		if bytes.is_empty() or hashing.finish().hex_encode() != String(entry["sha256"]):
			load_problems.append("%s: digest does not match voice.json" % word)
			continue
		var samples := parse_wav(bytes)
		if samples.is_empty():
			load_problems.append("%s: not 22050 Hz 16-bit mono PCM" % word)
			continue
		out[String(word)] = samples
	return out


## Samples of a 22050 Hz 16-bit mono PCM WAV file, or [] for anything else.
static func parse_wav(bytes: PackedByteArray) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if bytes.size() < 12 or bytes.slice(0, 4).get_string_from_ascii() != "RIFF" or bytes.slice(8, 12).get_string_from_ascii() != "WAVE":
		return out
	var at := 12
	var format_ok := false
	while at + 8 <= bytes.size():
		var id := bytes.slice(at, at + 4).get_string_from_ascii()
		var size := bytes.decode_u32(at + 4)
		var body := at + 8
		if id == "fmt ":
			format_ok = bytes.decode_u16(body) == 1 and bytes.decode_u16(body + 2) == 1 and bytes.decode_u32(body + 4) == MIX_RATE and bytes.decode_u16(body + 14) == 16
		elif id == "data" and format_ok:
			var count := mini(size, bytes.size() - body) / 2
			out.resize(count)
			for n in count:
				out[n] = bytes.decode_s16(body + n * 2) / 32768.0
			return out
		at = body + size + (size & 1)
	return out


## The words of the victory call for the winner `agent_name` in seat `seat`,
## or [] if there is no clip for any form of it.
static func victory_words(agent_name: String, seat: String) -> PackedStringArray:
	var clips := voice()
	var words := spoken_words(agent_name)
	if not words.is_empty():
		words.append("WINS")
		if Array(words).all(func(w: String) -> bool: return clips.has(w)):
			return words
	var fallback := PackedStringArray(["PLAYER", seat.to_upper(), "WINS"])
	if Array(fallback).all(func(w: String) -> bool: return clips.has(w)):
		return fallback
	return PackedStringArray()


## The victory call as samples: CALL_DELAY of silence, then the words.
static func victory_call(agent_name: String, seat: String) -> PackedFloat32Array:
	var words := victory_words(agent_name, seat)
	var out := PackedFloat32Array()
	if words.is_empty():
		return out
	out.resize(int(round(CALL_DELAY * MIX_RATE)))
	var gap := PackedFloat32Array()
	gap.resize(int(round(WORD_GAP * MIX_RATE)))
	for k in words.size():
		if k > 0:
			out.append_array(gap)
		for sample in voice()[words[k]]:
			out.append(sample * VOICE_GAIN)
	return out


## The opening sequence as samples: the rising rumble, then FIGHT.
static func intro() -> PackedFloat32Array:
	var out := rumble()
	var fight: PackedFloat32Array = voice().get("FIGHT", PackedFloat32Array())
	var at := int(round(VOICE_AT * MIX_RATE))
	if out.size() < at + fight.size():
		out.resize(at + fight.size())
	for n in fight.size():
		out[at + n] = clampf(out[at + n] + fight[n] * VOICE_GAIN, -1.0, 1.0)
	return out


## A low electronic rumble that rises in pitch (38 to about 170 Hz), gains
## harmonics, intensity and distortion, and speeds up its pulse. Deterministic.
static func rumble() -> PackedFloat32Array:
	var count := int(round(RUMBLE * MIX_RATE))
	var out := PackedFloat32Array()
	out.resize(count)
	var noise := Synth._Noise.new(4277)
	var phase := 0.0
	var pulse := 0.0
	var lowpass := 0.0
	for n in count:
		var t := float(n) / MIX_RATE
		var u := t / RUMBLE
		phase += TAU * 38.0 * pow(4.5, pow(u, 1.6)) / MIX_RATE
		pulse += TAU * lerpf(6.0, 18.0, u * u) / MIX_RATE
		# Harmonics fade in one by one as it rises.
		var tone := 0.0
		for k in range(1, 8):
			var weight := 1.0 if k == 1 else clampf(7.0 * u - (k - 1), 0.0, 1.0)
			tone += weight * sin(k * phase) / k
		var cutoff := lerpf(150.0, 1200.0, u)
		lowpass += (1.0 - exp(-TAU * cutoff / MIX_RATE)) * (noise.next() - lowpass)
		var drive := 1.2 + 2.8 * u
		var x := (tone + 1.5 * lowpass) * (0.75 + 0.25 * sin(pulse))
		var level := 0.12 + 0.6 * pow(u, 1.3)
		var fade := minf(1.0, minf(t / 0.05, (RUMBLE - t) / 0.08))
		out[n] = level * tanh(drive * x) / tanh(drive) * fade
	return out


static func stream_of(samples: PackedFloat32Array) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = Synth.encode(samples)
	return wav
