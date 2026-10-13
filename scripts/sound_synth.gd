extends RefCounted
## Procedural sound effects: short 16-bit mono PCM clips synthesised from
## waveforms, envelopes, noise and pitch glides. No audio files are used.
##
## A clip is a pure function of (sound, variant). Noise comes from a fixed
## seeded generator, so the same request always gives the same bytes. Each
## variant voices one competitor: a pitch factor and how much odd-harmonic
## edge its tones carry.

const MIX_RATE := 22050
const SOUNDS := [
	"sense", "receipt", "contact", "write", "disruption",
	"move_up", "move_down", "core_damage", "elimination", "victory",
]
## Entrant voicing by entrant index (wrapping): A brighter and higher, B lower and rounder.
const VARIANTS := [{"pitch": 1.0, "edge": 0.35}, {"pitch": 0.84, "edge": 0.12}]
## Audible length of each sound in seconds.
const DURATION := {
	"sense": 0.22, "receipt": 0.14, "contact": 0.18, "write": 0.10, "disruption": 0.24,
	"move_up": 0.26, "move_down": 0.26, "core_damage": 0.34, "elimination": 0.40, "victory": 0.40,
}
## Silence before the sound starts. The victory sting waits for the elimination
## burst it is recorded with, so both can start on the same frame.
const LEAD_IN := {"victory": 0.30}
const FADE := 0.004  # seconds of fade-in and fade-out against clicks

const _VICTORY_STEPS := [0, 4, 7, 12]  # semitones: major arpeggio to the octave


## A playable stream of `sound` voiced as `variant`.
static func stream(sound: String, variant: int) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = encode(render(sound, variant))
	return wav


## Total clip length in seconds (lead-in included).
static func length(sound: String) -> float:
	return float(LEAD_IN.get(sound, 0.0)) + float(DURATION[sound])


static func encode(samples: PackedFloat32Array) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for n in samples.size():
		bytes.encode_s16(n * 2, int(round(clampf(samples[n], -1.0, 1.0) * 32767.0)))
	return bytes


## Samples in [-1, 1] of `sound` voiced as `variant`.
static func render(sound: String, variant: int) -> PackedFloat32Array:
	var voice: Dictionary = VARIANTS[posmod(variant, VARIANTS.size())]
	var pitch: float = voice["pitch"]
	var edge: float = voice["edge"]
	var duration: float = DURATION[sound]
	var count := int(round(duration * MIX_RATE))
	var out := PackedFloat32Array()
	out.resize(count)
	var rng := _Noise.new(hash(sound) ^ (variant * 7919))
	var phase := 0.0
	var phase2 := 0.0
	var lowpass := 0.0
	for n in count:
		var t := float(n) / MIX_RATE
		var u := t / duration
		var s := 0.0
		match sound:
			"sense":  # radar sweep: rising glide with a fast tremolo
				phase += TAU * 500.0 * pitch * pow(3.2, u) / MIX_RATE
				var tremolo := 1.0 - 0.3 * (0.5 + 0.5 * sin(TAU * 28.0 * t))
				s = 0.35 * _tone(phase, edge * 0.5) * tremolo * pow(1.0 - u, 1.5)
			"receipt":  # confirmation ping
				phase += TAU * 1568.0 * pitch / MIX_RATE
				s = 0.3 * (sin(phase) + 0.3 * sin(2.01 * phase)) * exp(-t * 30.0)
			"contact":  # two-note ping: the delivered sample found anchors
				var second := t >= 0.07
				var tn := t - 0.07 if second else t
				phase += TAU * (2093.0 if second else 1568.0) * pitch / MIX_RATE
				s = 0.3 * (sin(phase) + 0.3 * sin(2.01 * phase)) * exp(-tn * 32.0)
			"write":  # sharp energy pulse: fast pitch drop plus a noise click
				phase += TAU * (110.0 + 880.0 * exp(-t * 30.0)) * pitch / MIX_RATE
				var click := rng.next() * maxf(0.0, 1.0 - t / 0.012)
				s = 0.32 * (_tone(phase, 0.25 + edge) + 0.6 * click) * exp(-t * 35.0)
			"disruption":  # gated, bit-crushed crackle over a low buzz
				var gate := 1.0 if hash(int(t / 0.008) * 31 + variant) % 10 < 6 else 0.15
				var crackle := snappedf(rng.next(), 0.25) * gate
				phase += TAU * 60.0 * pitch / MIX_RATE
				var buzz := 0.4 * signf(sin(phase))
				s = 0.28 * (crackle + buzz) * (1.0 - u)
			"move_up", "move_down":  # swoosh: swept low-passed noise and a soft glide
				var rising := sound == "move_up"
				var sweep := u if rising else 1.0 - u
				var cutoff := 400.0 * pow(7.5, sweep)
				lowpass += (1.0 - exp(-TAU * cutoff / MIX_RATE)) * (rng.next() - lowpass)
				phase += TAU * 330.0 * pitch * pow(2.0, sweep) / MIX_RATE
				s = 0.25 * (lowpass * 1.6 + 0.35 * sin(phase)) * pow(sin(PI * u), 2.0)
			"core_damage":  # deep impact with a descending tone
				phase += TAU * 220.0 * pitch * pow(0.25, u) / MIX_RATE
				lowpass += 0.15 * (rng.next() - lowpass)
				var thump := lowpass * 3.0 * maxf(0.0, 1.0 - t / 0.03)
				s = 0.45 * tanh(1.8 * (_tone(phase, 0.5) + thump)) * exp(-t * 9.0)
			"elimination":  # low-frequency burst: sub glide, detuned fifth, rumble
				var f := 90.0 * pitch * pow(1.0 / 3.0, u)
				phase += TAU * f / MIX_RATE
				phase2 += TAU * f * 1.505 / MIX_RATE
				lowpass += (1.0 - exp(-TAU * 600.0 / MIX_RATE)) * (rng.next() - lowpass)
				var rumble := lowpass * 2.5 * exp(-t * 12.0)
				s = 0.55 * tanh(2.5 * (sin(phase) + 0.5 * sin(phase2) + rumble)) * pow(1.0 - u, 1.2)
			"victory":  # rising arpeggio, the last note held
				var step := mini(int(t / 0.08), _VICTORY_STEPS.size() - 1)
				var tn := t - step * 0.08
				var f := 523.25 * pitch * pow(2.0, _VICTORY_STEPS[step] / 12.0)
				phase += TAU * f / MIX_RATE
				var decay := 6.0 if step == _VICTORY_STEPS.size() - 1 else 8.0
				s = 0.3 * (_tone(phase, 0.25 + edge) + 0.2 * sin(2.0 * phase)) * exp(-tn * decay) * minf(1.0, tn / FADE)
		out[n] = clampf(s, -1.0, 1.0) * _fade(t, duration)
	var lead := int(round(float(LEAD_IN.get(sound, 0.0)) * MIX_RATE))
	if lead > 0:
		var silence := PackedFloat32Array()
		silence.resize(lead)
		silence.append_array(out)
		out = silence
	return out


## Sine with odd harmonics mixed in by `edge` (0 = pure sine, larger = squarer).
static func _tone(phase: float, edge: float) -> float:
	return sin(phase) + edge * (sin(3.0 * phase) / 3.0 + sin(5.0 * phase) / 5.0)


static func _fade(t: float, duration: float) -> float:
	return minf(1.0, minf(t / FADE, (duration - t) / FADE))


## Deterministic white noise in [-1, 1] (a 31-bit linear congruential generator).
class _Noise:
	var _state: int

	func _init(seed_value: int) -> void:
		_state = seed_value & 0x7fffffff

	func next() -> float:
		_state = (_state * 1103515245 + 12345) & 0x7fffffff
		return float(_state) / float(0x3fffffff) - 1.0
