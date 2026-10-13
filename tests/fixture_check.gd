extends SceneTree
## Generic headless playback check for any verified presentation fixture.
##
## Run: godot --headless --path . --script res://tests/fixture_check.gd -- --fixture=<dir>
## Exit code 0 = pass, 1 = failure (each failure is printed).
##
## Checks: the manifest and both files load and verify; every frame of both
## perspectives plays in tick order to the recorded end; the broadcast's final
## alive set, eliminations, core display and result text match the manifest's
## verified outcome; the Agent A perspective holds only agent state, never
## shows the result or the match length; perspective switches land on tick
## boundaries; playback runs at the chosen rate and stops at the end.

const FixtureLoader := preload("res://scripts/fixture_loader.gd")
const AGENT_STATE_KEYS := [
	"mode", "tick", "callback", "phase", "core_base", "core_size", "processes",
	"contacts", "receipt", "latest_sample", "recent_events",
]

var failures: PackedStringArray = []
var checks := 0
var _main: Node
var _frame := 0
var _fixture := ""


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("FAIL: ", message)


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--fixture="):
			_fixture = arg.trim_prefix("--fixture=")
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)  # main reads --fixture= itself in _ready


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 1:
		_run(_main)
	if _frame < 4:
		return false
	print("%d checks, %d failures" % [checks, failures.size()])
	print("FIXTURE CHECK %s" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)
	return true


func _run(main: Node) -> void:
	check(_fixture != "", "a --fixture= argument is given")
	var loaded := FixtureLoader.load_manifest(_fixture)
	check(not loaded.has("error"), "manifest loads: %s" % loaded.get("error", ""))
	check(main.load_error == "", "main scene loads the fixture: %s" % main.load_error)
	if loaded.has("error") or main.load_error != "":
		return
	var match_info: Dictionary = loaded["manifest"]["match"]
	var ticks := int(match_info["ticks"])
	var winner := String(match_info["winner"])
	var ring: Control = main._ring

	# Broadcast: every frame, in tick order, to the recorded end.
	main.restart()
	var last_tick := 0
	var monotonic := true
	var alive_counts: Dictionary = {}
	for i in range(1, main.frame_count()):
		main.step_frame(1)
		monotonic = monotonic and main.current_tick() >= last_tick
		last_tick = main.current_tick()
		alive_counts[(ring.state["alive"] as Array).size()] = true
	check(monotonic, "broadcast ticks are monotonic")
	check(main.current_tick() == ticks, "broadcast ends at tick %d" % ticks)
	var alive: Array = ring.state["alive"]
	if String(match_info["termination_reason"]) == "last_agent_standing":
		check(alive == [winner], "only the winner is alive at the end (%s)" % [alive])
		check(main._side.text.contains("eliminated"), "the loser is shown eliminated")
		var loser := 1 - int(main.broadcast.entrant_index[winner])
		check(main.broadcast.core_cells_owned(main.index, loser) == 0, "the loser's core shows 0/8 at the end")
	check(main._side.text.contains("Result: %s" % winner), "broadcast shows the verified result")
	check(int(main._timeline.max_value) == ticks, "broadcast timeline spans the recorded match")
	for i in range(main.frame_count() - 1):
		main.step_frame(-1)
	check(main.index == 0 and not main._side.text.contains("Result:"), "no result is shown before the end")

	# Agent A: every frame; only agent state; no result and no match length.
	main.set_perspective("agent_a")
	main.restart()
	var keys_ok := true
	var label_ok := true
	var hidden_ok := true
	for i in range(main.frame_count()):
		if i:
			main.step_frame(1)
		keys_ok = keys_ok and ring.mode == "agent" and ring.entrants.is_empty()
		for key in ring.state:
			keys_ok = keys_ok and AGENT_STATE_KEYS.has(key)
		var label: String = main._position_label.text
		label_ok = label_ok and label.contains("(limit %d)" % main.tick_limit) and not label.contains("/")
		label_ok = label_ok and int(main._timeline.max_value) == main.tick_limit
		hidden_ok = hidden_ok and not main._side.text.contains("Result") and not main._side.text.contains("eliminated")
	check(keys_ok, "agent perspective holds no broadcast state")
	check(label_ok, "agent perspective shows only the public tick limit")
	check(hidden_ok, "agent perspective never shows the result or eliminations")
	check(main.current_tick() == ticks, "agent perspective ends at the recorded end")

	# Switching lands on tick boundaries in both directions.
	var middle := ticks / 2
	main.seek_tick(middle)
	main.set_perspective("broadcast")
	check(main.current_tick() == middle and main.current_model().is_tick_end(main.index), "agent -> broadcast on a boundary")
	main.step_frame(3)
	main.set_perspective("agent_a")
	check(main.current_tick() == middle and main.current_model().is_tick_end(main.index), "mid-tick switch lands on the last boundary")

	# Playback at a fixed rate, stopping at the end, in both perspectives.
	for perspective in ["broadcast", "agent_a"]:
		main.set_perspective(perspective)
		main.seek_tick(0)
		main.ticks_per_second = 20.0
		main.set_playing(true)
		for i in 10:
			main._process(0.1)
		check(main.current_tick() == 20, "%s plays 20 ticks in 1 s at 20 ticks/s (got %d)" % [perspective, main.current_tick()])
		main.seek_tick(ticks - 1)
		for i in 10:
			main._process(0.1)
		check(not main.playing and main.current_tick() == ticks, "%s playback stops at the end" % perspective)
