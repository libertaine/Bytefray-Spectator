extends SceneTree
## Headless playback smoke test.
##
## Run: godot --headless --path . --script res://tests/smoke_test.gd
## Exit code 0 = pass, 1 = failure (each failure is printed).

const FixtureLoader := preload("res://scripts/fixture_loader.gd")
const FIXTURE := "res://fixtures/dev/presentation"
const TAMPER_DIR := "user://smoke_tamper"
# The only state keys the ring view may hold in the agent perspective.
const AGENT_STATE_KEYS := [
	"mode", "tick", "callback", "phase", "core_base", "core_size", "processes",
	"contacts", "receipt", "latest_sample", "recent_events", "own_actions",
]

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
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)  # _ready (which loads the default fixture) runs once the tree starts


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 1:
		var started := Time.get_ticks_msec()
		_run(_main)
		print("smoke checks run in %d ms" % (Time.get_ticks_msec() - started))
	# Let a few more frames render (draw calls exercised on the dummy renderer).
	if _frame < 4:
		return false
	print("%d checks, %d failures" % [checks, failures.size()])
	print("SMOKE %s" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)
	return true


func _run(main: Node) -> void:
	var loaded := FixtureLoader.load_manifest(FIXTURE)
	check(not loaded.has("error"), "manifest loads: %s" % loaded.get("error", ""))
	if loaded.has("error"):
		return
	var manifest: Dictionary = loaded["manifest"]
	var match_info: Dictionary = manifest["match"]
	check(int(match_info["arena_size"]) == 512, "fixture arena is 512")
	check(int(match_info["seed"]) == 0, "fixture uses the declared seed 0")

	# The viewer opens the showcase fixture by default.
	var ready: bool = main.is_node_ready() and main.broadcast != null and main.agent != null
	check(ready and main.load_error == "", "main scene loads the default fixture: %s" % main.load_error)
	check(ready and int(main.manifest["match"]["seed"]) == 427, "the default fixture is the showcase")
	_check_launch_options(main)
	check(main.load_fixture(FIXTURE) == "", "the dev fixture loads")
	ready = main.broadcast != null and main.agent != null
	if not ready:
		return
	var ring: Control = main._ring

	# Broadcast: traverse every frame.
	check(main.perspective == "broadcast", "starts in broadcast")
	check(main.frame_count() == int(manifest["presentation"]["broadcast"]["frames"]), "broadcast frame count")
	main.restart()
	var last_tick := 0
	var monotonic := true
	for i in range(1, main.frame_count()):
		main.step_frame(1)
		monotonic = monotonic and main.current_tick() >= last_tick
		last_tick = main.current_tick()
	check(monotonic, "broadcast ticks are monotonic")
	check(main.index == main.frame_count() - 1, "broadcast reaches the final frame")
	check(main.current_tick() == int(match_info["ticks"]), "broadcast ends at tick %d" % int(match_info["ticks"]))
	check(ring.mode == "broadcast" and not ring.entrants.is_empty(), "ring draws broadcast state")
	var alive: Array = ring.state["alive"]
	check(alive.size() == 2, "both entrants alive at the end of the dev fixture (tick limit)")
	check(main._side.text.contains("Result: tie"), "broadcast shows the result at the end")
	check(int(main._timeline.max_value) == main.broadcast.max_tick, "broadcast timeline spans the recorded match")

	# Agent A: traverse every frame; the view may only hold agent-visible state.
	main.set_perspective("agent_a")
	check(main.current_tick() == int(match_info["ticks"]), "switch keeps the tick boundary")
	check(main.frame_count() == int(manifest["presentation"]["agent_a"]["frames"]), "agent frame count")
	main.restart()
	var keys_ok := true
	var processes_ok := true
	for i in range(main.frame_count()):
		if i:
			main.step_frame(1)
		keys_ok = keys_ok and ring.mode == "agent" and ring.entrants.is_empty()
		for key in ring.state:
			keys_ok = keys_ok and AGENT_STATE_KEYS.has(key)
		processes_ok = processes_ok and (ring.state["processes"] as Array).size() == 1
	check(keys_ok, "agent perspective holds no broadcast state")
	check(processes_ok, "agent perspective shows only its own process")
	check(not main._side.text.contains("Result:"), "agent perspective does not show the match result")
	check(not main._title.text.contains("Broadcast"), "agent perspective title")
	# Only the public tick limit, never the match length or a frame total.
	var label: String = main._position_label.text
	check(label.contains("(limit %d)" % main.tick_limit) and not label.contains("/"), "agent position label: %s" % label)
	check(int(main._timeline.max_value) == main.tick_limit, "agent timeline spans the public tick limit")

	# Perspective round trip on a tick boundary.
	main.seek_tick(500)
	main.set_perspective("broadcast")
	check(main.current_tick() == 500 and main.current_model().is_tick_end(main.index), "agent -> broadcast at tick 500")
	main.step_frame(3)  # mid-tick
	main.set_perspective("agent_a")
	check(main.current_tick() == 500, "mid-tick switch lands on the last completed tick boundary")

	# Playback.
	main.set_perspective("broadcast")
	main.seek_tick(0)
	main.ticks_per_second = 20.0
	main.set_playing(true)
	# Playing from tick 0 starts with the announcer, which holds the match clock.
	var intro_steps := 0
	while main.intro_left() > 0.0 and intro_steps < 100:
		main._process(0.1)
		intro_steps += 1
	check(intro_steps > 0 and main.current_tick() == 0 and main.index == main.broadcast.index_for_tick_end(0), "the opening sequence holds tick 0 (%d steps)" % intro_steps)
	for i in 10:
		main._process(0.1)
	check(main.current_tick() == 20, "play advances 20 ticks in 1 s at 20 ticks/s (got %d)" % main.current_tick())
	main.seek_tick(999)
	for i in 10:
		main._process(0.1)
	check(not main.playing and main.current_tick() == 1000, "play stops at the end")

	_check_controls(main)

	# Tampering: a one-byte change to a presentation file is rejected.
	_check_tamper(main)


func _key(main: Node, keycode: Key, shift: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	event.shift_pressed = shift
	main._unhandled_input(event)


## P1-4 controls: End, jump to tick, speed keys, legend, help and the key hint.
func _check_controls(main: Node) -> void:
	main.set_playing(false)
	main.set_perspective("broadcast")
	main.restart()
	_key(main, KEY_END)
	check(main.current_tick() == main.broadcast.max_tick and main.current_model().is_tick_end(main.index), "End jumps to the last tick (broadcast)")
	_key(main, KEY_HOME)
	check(main.index == 0, "Home restarts")
	check(main.jump_to_tick("250") and main.current_tick() == 250 and main.current_model().is_tick_end(main.index), "jump to tick 250")
	check(not main.jump_to_tick("abc") and not main.jump_to_tick("-4") and main.current_tick() == 250, "invalid tick entries are ignored")
	main._jump.text = "300"
	main._jump.text_submitted.emit("300")
	check(main.current_tick() == 300, "Enter in the tick box jumps")
	main.set_speed_index(2)
	_key(main, KEY_EQUAL)
	check(main.ticks_per_second == 10.0, "+ raises the speed to 10 ticks/s")
	_key(main, KEY_MINUS)
	_key(main, KEY_MINUS)
	check(main.ticks_per_second == 2.0, "- lowers the speed to 2 ticks/s")
	for i in 10:
		_key(main, KEY_MINUS)
	check(main.ticks_per_second == 1.0, "the speed stops at 1 tick/s")
	main.set_speed_index(2)
	var legend_visible: bool = main._legend.visible
	_key(main, KEY_L)
	check(main._legend.visible != legend_visible, "L toggles the legend")
	_key(main, KEY_L)
	check(not main._help.visible, "help starts hidden")
	_key(main, KEY_H)
	check(main._help.visible and (main._help.get_child(0) as Label).text.contains("Jump to a tick"), "H shows the keyboard help")
	_key(main, KEY_H)
	check(not main._help.visible, "H hides the help again")
	check(main._hint.text.contains("G jump to tick") and main._hint.text.contains("H help"), "the key hint line is shown")
	check(main._legend.text().contains("SENSE sample taken, not yet delivered"), "broadcast legend")
	# Paused: the caption describes the frame; playing mid-tick: the last tick's summary.
	main.seek_tick(10)
	main.step_frame(3)
	var paused_caption: String = main._caption.text
	main.set_playing(true)
	check(main._caption.text.begins_with("Tick 10 ends") and paused_caption != main._caption.text, "while playing, the caption holds the last tick's summary")
	main.set_playing(false)
	check(main._caption.text == paused_caption, "paused, the caption describes the frame again")
	# Agent A: End and the tick box land where any seek lands (the end of its own record).
	main.set_perspective("agent_a")
	check(main._legend.text().contains("Own WRITE target (outcome not delivered)"), "agent legend")
	_key(main, KEY_END)
	check(main.current_tick() == main.agent.max_tick, "End in Agent A lands on the last tick of its own record")
	main.set_perspective("broadcast")


func _check_launch_options(main: Node) -> void:
	var options: Dictionary = main.launch_options(PackedStringArray([
		"--fixture=dev", "--perspective=agent_a", "--tick=50", "--speed=20", "--play",
	]))
	check(options == {"fixture": FIXTURE, "perspective": "agent_a", "tick": 50, "speed": 4, "play": true}, "launch options parse: %s" % [options])
	check(main.SPEEDS == [1.0, 2.0, 5.0, 10.0, 20.0, 60.0, 200.0] and main.ticks_per_second == 5.0, "speed choices 1-200 ticks/s, default 5")
	check(main.launch_options(PackedStringArray(["--speed=2"]))["speed"] == 1 and main.launch_options(PackedStringArray(["--speed=10"]))["speed"] == 3, "the new 2 and 10 ticks/s speeds are accepted")
	var defaults: Dictionary = main.launch_options(PackedStringArray(["--perspective=omniscient", "--speed=7", "--tick=-3"]))
	check(defaults == {"fixture": main.DEFAULT_FIXTURE, "perspective": "broadcast", "tick": -1, "speed": -1, "play": false}, "invalid launch options are ignored")
	main.apply_launch_options(main.launch_options(PackedStringArray(["--perspective=agent_a", "--tick=100", "--speed=60"])))
	check(main.perspective == "agent_a" and main.current_tick() == 100 and main.ticks_per_second == 60.0 and not main.playing, "launch options apply")
	main.apply_launch_options(main.launch_options(PackedStringArray([])))
	check(main.perspective == "broadcast" and main.current_tick() == 100, "default launch options keep broadcast")


func _check_tamper(main: Node) -> void:
	var dir := ProjectSettings.globalize_path(TAMPER_DIR)
	DirAccess.make_dir_recursive_absolute(dir)
	for name in ["manifest.json", "broadcast.json", "agent_a.json"]:
		var bytes := FileAccess.get_file_as_bytes(FIXTURE.path_join(name))
		if name == "agent_a.json":
			var at := bytes.size() / 2
			bytes[at] = bytes[at] ^ 1
		var out := FileAccess.open(dir.path_join(name), FileAccess.WRITE)
		out.store_buffer(bytes)
		out.close()
	var error: String = main.load_fixture(dir)
	check(error.contains("SHA-256"), "tampered agent_a.json is rejected (%s)" % error)
	check(main.broadcast == null and main.agent == null, "nothing is kept from a rejected fixture")
	check(main._ring.state.is_empty(), "nothing is drawn from a rejected fixture")
	check(main.load_fixture(FIXTURE) == "", "the verified fixture loads again")
	for name in ["manifest.json", "broadcast.json", "agent_a.json"]:
		DirAccess.remove_absolute(dir.path_join(name))
	DirAccess.remove_absolute(dir)
