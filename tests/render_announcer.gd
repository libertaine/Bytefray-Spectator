extends SceneTree
## Renders the announcer as the viewer plays it, to WAV files for listening.
##
## Run: godot --headless --path . --script res://tests/render_announcer.gd -- --out=<dir>
##
## Writes the opening sequence, the showcase ending as heard (A's elimination
## burst, B's victory sting and the victory call started together, mixed and
## limited like the sound bus), and each victory call alone, including the
## PLAYER fallback for a name without clips.

const Synth := preload("res://scripts/sound_synth.gd")
const Announcer := preload("res://scripts/announcer.gd")


func _initialize() -> void:
	var out := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
	if out == "" or not Announcer.load_problems.is_empty() or Announcer.voice().is_empty():
		printerr("usage: -- --out=<dir> (and the announcer clips must verify): ", Announcer.load_problems)
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(out)
	_save(out, "01_intro.wav", Announcer.intro())
	var ending := _mix([Synth.render("elimination", 0), Synth.render("victory", 1), Announcer.victory_call("spectator_bastion", "B")])
	_save(out, "02_showcase_ending.wav", ending)
	_save(out, "03_call_bastion.wav", Announcer.victory_call("spectator_bastion", "B"))
	_save(out, "04_call_harrier.wav", Announcer.victory_call("spectator_harrier", "A"))
	_save(out, "05_call_fallback_player_a.wav", Announcer.victory_call("spectator_newcomer", "A"))
	quit(0)


func _mix(parts: Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for part in parts:
		if out.size() < part.size():
			out.resize(part.size())
		for n in part.size():
			out[n] += part[n]
	for n in out.size():
		out[n] = clampf(out[n], -1.0, 1.0)
	return out


func _save(dir: String, name: String, samples: PackedFloat32Array) -> void:
	var path := dir.path_join(name)
	Announcer.stream_of(samples).save_to_wav(path)
	print("%s  %.2f s" % [path, samples.size() / float(Announcer.MIX_RATE)])
