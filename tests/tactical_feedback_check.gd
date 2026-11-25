extends SceneTree
## Headless qualification check for the R1-A Spectator Tactical-Feedback Prototype.
##
## Run (bundled fixtures + synthetic checks only):
##   godot --headless --path . --script res://tests/tactical_feedback_check.gd
##
## Run with optional external qualification presentations:
##   SPECTATOR_R02_DIR=<path> SPECTATOR_PROTO_DIR=<path> \
##     godot --headless --path . --script res://tests/tactical_feedback_check.gd -- --out=<dump.json>
## Exit code 0 = pass, 1 = failure.

const FixtureLoader := preload("res://scripts/fixture_loader.gd")
const BroadcastModel := preload("res://scripts/broadcast_model.gd")
const BroadcastEffects := preload("res://scripts/broadcast_effects.gd")
const AgentModel := preload("res://scripts/agent_model.gd")
const SoundCues := preload("res://scripts/sound_cues.gd")
const SoundEffects := preload("res://scripts/sound_effects.gd")

const SAMPLE_DIR := "res://fixtures/production_sample/presentation"
const FPS := 60.0

var failures: PackedStringArray = []
var checks := 0
var _main: Node
var _frame := 0
var _out := ""
var _r02_dir := ""
var _proto_pres_dir := ""


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("FAIL: ", message)


func _initialize() -> void:
	_r02_dir = OS.get_environment("SPECTATOR_R02_DIR").strip_edges()
	_proto_pres_dir = OS.get_environment("SPECTATOR_PROTO_DIR").strip_edges()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.substr("--out=".length())
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 1:
		var started := Time.get_ticks_msec()
		var report := _run(_main)
		if _out != "":
			var file := FileAccess.open(_out, FileAccess.WRITE)
			file.store_string(JSON.stringify(report, "  "))
			file.close()
		print("tactical feedback checks run in %d ms" % (Time.get_ticks_msec() - started))
	if _frame < 3:
		return false
	print("%d checks, %d failures" % [checks, failures.size()])
	print("TACTICAL FEEDBACK CHECK %s" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)
	return true


func _run(main: Node) -> Dictionary:
	var report := {}
	var matches := {}
	if _r02_dir != "":
		matches["s202_ph_vs_ss"] = _r02_dir.path_join("s202_v6_pulse_hunter_vs_v6_sonar_squad")
		matches["s303_ph_vs_ss"] = _r02_dir.path_join("s303_v6_pulse_hunter_vs_v6_sonar_squad")
		matches["s606_ph_vs_ss"] = _r02_dir.path_join("s606_v6_pulse_hunter_vs_v6_sonar_squad")
		matches["s202_ss_vs_ph"] = _r02_dir.path_join("s202_v6_sonar_squad_vs_v6_pulse_hunter")
	else:
		print("SKIP: external R02 matches (set SPECTATOR_R02_DIR)")
	if _proto_pres_dir != "":
		matches["s101_ph_vs_ss"] = _proto_pres_dir.path_join("s101_v6_pulse_hunter_vs_v6_sonar_squad")
		matches["s404_ph_vs_ss"] = _proto_pres_dir.path_join("s404_v6_pulse_hunter_vs_v6_sonar_squad")
	else:
		print("SKIP: external short-match presentations (set SPECTATOR_PROTO_DIR)")

	# 1. Default playback speed adaptation (<= 60 ticks -> 2.0 tps; > 60 ticks -> 5.0 tps).
	check(main.load_fixture("res://fixtures/showcase/presentation") == "", "showcase loads")
	check(main.broadcast.max_tick == 477 and is_equal_approx(main.ticks_per_second, 5.0), "477-tick showcase defaults to 5.0 ticks/s")
	check(main.load_fixture("res://fixtures/production_sample/presentation") == "", "sample loads")
	check(main.broadcast.max_tick == 120 and is_equal_approx(main.ticks_per_second, 5.0), "120-tick sample defaults to 5.0 ticks/s")
	check(main.load_fixture("res://fixtures/dev/presentation") == "", "dev loads")
	check(main.broadcast.max_tick == 1000 and is_equal_approx(main.ticks_per_second, 5.0), "1000-tick dev defaults to 5.0 ticks/s")
	# Check repeat-READ suppression in dev (1 discovery out of 13,992 READs).
	var dev_discoveries: Array = main.effects.actions.filter(func(a: Dictionary) -> bool: return a["kind"] == "read" and bool(a["read_discovery"]))
	check(dev_discoveries.size() == 1 and int(dev_discoveries[0]["t"]) == 2 and int(dev_discoveries[0]["address"]) == 91, "dev suppresses 7,991 repeat READs on cell 91, keeping only the t2 discovery (%d)" % dev_discoveries.size())

	for label in matches:
		var dir: String = matches[label]
		check(main.open_presentation(dir) == "", "%s opens cleanly: %s" % [label, main.load_error])
		if main.load_error != "":
			continue
		check(main.broadcast.max_tick <= 60 and is_equal_approx(main.ticks_per_second, 2.0), "%s (%d ticks) defaults to 2.0 ticks/s" % [label, main.broadcast.max_tick])
		report[label] = _verify_match(main, label)

	_check_s202_exact(report.get("s202_ph_vs_ss", {}))
	_check_s303_exact(report.get("s303_ph_vs_ss", {}))
	_check_s606_exact(report.get("s606_ph_vs_ss", {}))
	_check_s202_reverse_exact(report.get("s202_ss_vs_ph", {}))
	_check_short_matches_exact(report.get("s101_ph_vs_ss", {}), report.get("s404_ph_vs_ss", {}))
	_check_agent_core_recovery_receipt()
	_check_launch_speed_isolation(main, matches)
	var nav_dir: String = matches.get("s202_ph_vs_ss", SAMPLE_DIR)
	_check_tab_focus_and_seek_consistency(main, nav_dir)
	_check_real_key_tab(main, nav_dir)
	return report


func _press(main: Node, code: int) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.pressed = pressed
		main.get_viewport().push_input(e)


## Key events pushed through the viewport, so Godot's GUI focus navigation runs
## first (calling _unhandled_input directly would skip it): every Tab press must
## switch perspective and none may leave focus parked in a control.
func _check_real_key_tab(main: Node, s202_dir: String) -> void:
	main.open_presentation(s202_dir)
	main.get_viewport().gui_release_focus()
	var tab_focusable: PackedStringArray = []
	var stack: Array = [main]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Control and (n as Control).focus_mode == Control.FOCUS_ALL and (n as Control).is_visible_in_tree():
			tab_focusable.append(String(n.name))
		stack.append_array(n.get_children())
	check(tab_focusable.is_empty(), "no visible control takes Tab focus (%s)" % [tab_focusable])
	var expected := "broadcast"
	for press in 4:
		_press(main, KEY_TAB)
		expected = "agent_a" if expected == "broadcast" else "broadcast"
		check(main.perspective == expected and main.get_viewport().gui_get_focus_owner() == null, "real Tab press %d switches to %s and leaves no focus (%s, focus %s)" % [press + 1, expected, main.perspective, main.get_viewport().gui_get_focus_owner()])
	var before: int = main.index
	_press(main, KEY_RIGHT)
	check(main.index == before + 1, "Right still steps a frame after Tab presses (%d -> %d)" % [before, main.index])
	_press(main, KEY_G)
	check(main.get_viewport().gui_get_focus_owner() == main._jump, "G still focuses the jump field")
	_press(main, KEY_TAB)
	check(main.perspective == "agent_a" and main.get_viewport().gui_get_focus_owner() == null, "Tab inside the jump field switches perspective and releases it")
	_press(main, KEY_G)
	_press(main, KEY_ESCAPE)
	check(main.get_viewport().gui_get_focus_owner() == null, "Escape releases the jump field")
	before = main.index
	_press(main, KEY_RIGHT)
	check(main.index == before + 1, "Right steps again after Escape")
	main.set_perspective("broadcast")


## Report §5.3: a view opened directly as Agent A must not choose its default
## speed from the Broadcast match length, which Agent A was never delivered.
## All of these matches share the public tick limit 1000 but last 2 to 1000 ticks.
func _check_launch_speed_isolation(main: Node, matches: Dictionary) -> void:
	var cases := {
		"showcase": "res://fixtures/showcase/presentation",
		"dev": "res://fixtures/dev/presentation",
	}
	for label in matches:
		cases[label] = matches[label]
	var agent_speeds := {}
	var durations := {}
	for label in cases:
		var dir: String = cases[label]
		# Direct Agent A launch, no --speed: same as `-- --fixture=<dir> --perspective=agent_a`.
		check(main.load_fixture(dir) == "", "%s loads for launch-speed check" % label)
		check(main.tick_limit == 1000, "%s has public tick limit 1000 (%d)" % [label, main.tick_limit])
		durations[label] = main.broadcast.max_tick
		var broadcast_default: float = main.ticks_per_second
		check(is_equal_approx(broadcast_default, 2.0 if main.broadcast.max_tick <= 60 else 5.0), "%s Broadcast keeps adaptive default (%d ticks -> %.1f tps)" % [label, main.broadcast.max_tick, broadcast_default])
		main.apply_launch_options(main.launch_options(PackedStringArray(["--perspective=agent_a"])))
		check(main.perspective == "agent_a", "%s launches directly into Agent A" % label)
		agent_speeds[label] = main.ticks_per_second
		check(is_equal_approx(main.ticks_per_second, 5.0), "%s direct Agent A launch defaults from tick limit 1000 to 5.0 tps, not from %d actual ticks (got %.1f)" % [label, main.broadcast.max_tick, main.ticks_per_second])
		check(main._speed_button.selected == main.SPEEDS.find(main.ticks_per_second), "%s speed selector shows the Agent A default" % label)
		# Explicit overrides still win in both perspectives.
		main.load_fixture(dir)
		main.apply_launch_options(main.launch_options(PackedStringArray(["--perspective=agent_a", "--speed=2"])))
		check(main.perspective == "agent_a" and is_equal_approx(main.ticks_per_second, 2.0), "%s Agent A --speed=2 override is kept" % label)
		main.load_fixture(dir)
		main.apply_launch_options(main.launch_options(PackedStringArray(["--perspective=broadcast", "--speed=10"])))
		check(main.perspective == "broadcast" and is_equal_approx(main.ticks_per_second, 10.0), "%s Broadcast --speed=10 override is kept" % label)
		main.load_fixture(dir)
		main.apply_launch_options(main.launch_options(PackedStringArray(["--perspective=broadcast"])))
		check(is_equal_approx(main.ticks_per_second, broadcast_default), "%s Broadcast launch without --speed keeps the adaptive default" % label)
	var distinct_durations := {}
	for label in durations:
		distinct_durations[durations[label]] = true
	var min_distinct := 5 if not matches.is_empty() else 2
	check(distinct_durations.size() >= min_distinct, "launch-speed cases cover several actual durations under one tick limit (%s)" % [durations])
	var distinct_speeds := {}
	for label in agent_speeds:
		distinct_speeds[agent_speeds[label]] = true
	check(distinct_speeds.size() == 1, "direct Agent A default speed is identical whatever the hidden match length (%s)" % [agent_speeds])

	# The Agent A rule itself, on the public tick limit only.
	var has_s202 := cases.has("s202_ph_vs_ss")
	var sample_case: String = cases["s202_ph_vs_ss"] if has_s202 else cases["showcase"]
	main.load_fixture(sample_case)
	var saved_limit: int = main.tick_limit
	main.tick_limit = 60
	check(main.default_speed_index("agent_a") == main.SHORT_MATCH_SPEED, "Agent A default is 2 tps when the public tick limit is <= 60")
	main.tick_limit = 61
	check(main.default_speed_index("agent_a") == main.DEFAULT_SPEED, "Agent A default is 5 tps when the public tick limit is > 60")
	main.tick_limit = saved_limit
	var expected_bcast_idx: int = main.SHORT_MATCH_SPEED if has_s202 else main.DEFAULT_SPEED
	check(main.default_speed_index() == expected_bcast_idx and main.default_speed_index("broadcast") == expected_bcast_idx, "Broadcast default still follows the actual match length")

	# Tab after a Broadcast start keeps the speed already chosen (the viewer saw
	# the Broadcast length there); Tab after a direct Agent A start keeps 5 tps.
	var tab_event := InputEventKey.new()
	tab_event.keycode = KEY_TAB
	tab_event.pressed = true
	main.load_fixture(sample_case)
	var start_speed: float = main.ticks_per_second
	main._unhandled_input(tab_event)
	check(main.perspective == "agent_a" and is_equal_approx(main.ticks_per_second, start_speed), "Tab from Broadcast does not change speed")
	main.load_fixture(sample_case)
	main.apply_launch_options(main.launch_options(PackedStringArray(["--perspective=agent_a"])))
	main._unhandled_input(tab_event)
	check(main.perspective == "broadcast" and is_equal_approx(main.ticks_per_second, 5.0), "Tab from a direct Agent A launch does not change speed")


func _verify_match(main: Node, label: String) -> Dictionary:
	var b_reads: Array = []
	var b_routine_reads := 0
	var b_recoveries: Array = []
	var b_deliveries: Array = []
	for action in main.effects.actions:
		if action["kind"] == "read" and action["outcome"] == "applied":
			if bool(action["read_discovery"]):
				b_reads.append({
					"i": int(action["i"]), "t": int(action["t"]),
					"actor": action["actor"], "process": action["process"],
					"address": int(action["address"]), "read_kind": action["read_kind"],
					"before_owner": int(action["before_owner"]), "core_owner": int(action["core_owner"]),
					"caption": main.frame_caption(int(action["i"])),
				})
			else:
				b_routine_reads += 1
		elif action["kind"] == "write" and action["core_change"] == "recovery":
			b_recoveries.append({
				"i": int(action["i"]), "t": int(action["t"]),
				"actor": action["actor"], "process": action["process"],
				"address": int(action["address"]), "core_owner": int(action["core_owner"]),
				"caption": main.frame_caption(int(action["i"])),
			})
		elif action["kind"] == "sense" and int(action["delivered"]) >= 0:
			var s_list: Array = action["sensed"]
			if not s_list.is_empty():
				var d_idx := int(action["delivered"])
				b_deliveries.append({
					"i": d_idx, "t": main.broadcast.tick_of(d_idx),
					"sampled_t": int(action["t"]), "actor": action["actor"],
					"process": action["process"], "center": int(action["address"]),
					"sensed": s_list, "sense_kind": action["sense_kind"],
					"caption": main.frame_caption(d_idx),
				})
	var b_all_tps: Array = main.effects.turning_points(main.broadcast.frame_count() - 1, 100)
	b_all_tps.reverse()
	var a_all_tps: Array = main.agent.turning_points(main.agent.frame_count() - 1, 100)
	a_all_tps.reverse()
	var a_reads: Array = main.agent._notable_reads.duplicate(true)

	# Information boundary check across every Agent A frame.
	main.set_perspective("agent_a")
	main.restart()
	var leak_free := true
	var opponent_name := String(main.broadcast.entrants[1]["name"])
	for i in main.agent.frame_count():
		if i > 0:
			main.step_frame(1)
		var text: String = main._caption.text + "\n" + main._side.text + "\n" + main._position_label.text + "\n" + main.get_window().title
		if text.contains("B core") or text.contains("enemy core") or text.contains("Result:") or text.contains("eliminated") or text.contains(opponent_name):
			leak_free = false
			break
	check(leak_free, "%s: Agent A perspective leaks zero Broadcast core/winner/opponent facts" % label)
	var a_cues := SoundCues.agent_cues(main.agent, 0, main.agent.frame_count() - 1)
	var a_sounds_ok := a_cues.all(func(c: Dictionary) -> bool: return SoundCues.AGENT_SOUNDS.has(c["sound"]) and int(c["variant"]) == 0)
	check(a_sounds_ok, "%s: Agent A emits only allowed AGENT_SOUNDS in variant 0" % label)

	# Audio priority verification at 2.0 ticks/s and 5.0 ticks/s in Broadcast.
	var playback_stats := {}
	for speed in [2.0, 5.0]:
		main.set_perspective("broadcast")
		main.seek_tick(0)
		main.ticks_per_second = speed
		main.set_sound_enabled(true)
		main.set_playing(true)
		while main.intro_left() > 0.0:
			main._process(1.0 / FPS)
		main.sound.take_played()
		var started_cues: Array = []
		var match_seconds := 0.0
		while main.playing:
			main._process(1.0 / FPS)
			match_seconds += 1.0 / FPS
			started_cues.append_array(main.sound.take_played())
		var started_sounds: Array = started_cues.map(func(c: Dictionary) -> String: return String(c["sound"]))
		for r in b_reads:
			check(started_cues.any(func(c: Dictionary) -> bool: return c["sound"] == "read_discovery"), "%s at %.1f tps: read_discovery cue is audible (not starved)" % [label, speed])
		for rec in b_recoveries:
			check(started_cues.any(func(c: Dictionary) -> bool: return c["sound"] == "core_recovery"), "%s at %.1f tps: core_recovery cue is audible (not starved)" % [label, speed])
		playback_stats["%.1f_tps" % speed] = {
			"seconds": snappedf(match_seconds, 0.01),
			"started_count": started_cues.size(),
			"started_sounds": started_sounds,
		}
	main.set_perspective("broadcast")
	return {
		"ticks": main.broadcast.max_tick,
		"winner": main.broadcast.result["winner"],
		"broadcast_frames": main.broadcast.frame_count(),
		"agent_a_frames": main.agent.frame_count(),
		"broadcast_notable_reads": b_reads,
		"broadcast_routine_reads": b_routine_reads,
		"broadcast_core_recoveries": b_recoveries,
		"broadcast_positive_deliveries": b_deliveries,
		"broadcast_turning_points": b_all_tps,
		"agent_a_notable_reads": a_reads,
		"agent_a_turning_points": a_all_tps,
		"playback_stats": playback_stats,
	}


func _check_s202_exact(info: Dictionary) -> void:
	if info.is_empty():
		return
	var reads: Array = info["broadcast_notable_reads"]
	check(reads.size() == 2 and int(info["broadcast_routine_reads"]) == 102, "s202: 2 discovery READs and 102 routine READs")
	if reads.size() == 2:
		check(int(reads[0]["t"]) == 11 and reads[0]["actor"] == "A" and int(reads[0]["address"]) == 88 and reads[0]["read_kind"] == "enemy_core", "s202: T11 A/striker READ 88 is enemy_core discovery")
		check(int(reads[1]["t"]) == 12 and reads[1]["actor"] == "B" and int(reads[1]["address"]) == 336 and reads[1]["read_kind"] == "enemy_core", "s202: T12 B/sonar READ 336 is enemy_core discovery")
	var recs: Array = info["broadcast_core_recoveries"]
	check(recs.size() == 1 and int(recs[0]["t"]) == 14 and int(recs[0]["address"]) == 87, "s202: T14 B/warden WRITE 87 is core_recovery")
	var a_reads: Array = info["agent_a_notable_reads"]
	check(a_reads.size() == 1 and int(a_reads[0]["t"]) == 11 and int(a_reads[0]["address"]) == 88 and a_reads[0]["read_kind"] == "enemy_owned", "s202 Agent A: T11 striker READ 88 is enemy_owned (never enemy_core)")


func _check_s303_exact(info: Dictionary) -> void:
	if info.is_empty():
		return
	var reads: Array = info["broadcast_notable_reads"]
	check(reads.size() == 1 and int(info["broadcast_routine_reads"]) == 95, "s303: 1 discovery READ and 95 routine READs")
	if reads.size() == 1:
		check(int(reads[0]["t"]) == 13 and reads[0]["actor"] == "A" and int(reads[0]["address"]) == 48 and reads[0]["read_kind"] == "enemy_core", "s303: T13 A/striker READ 48 is enemy_core discovery")
	var recs: Array = info["broadcast_core_recoveries"]
	check(recs.size() == 2 and int(recs[0]["t"]) == 16 and int(recs[1]["t"]) == 17, "s303: T16 and T17 B/warden core recoveries")
	var deliveries: Array = info["broadcast_positive_deliveries"]
	var a_confirms: Array = deliveries.filter(func(d: Dictionary) -> bool: return d["actor"] == "A" and d["sense_kind"] == "confirm")
	check(a_confirms.size() == 3, "s303: A's repeated scans of stationary decoy cell 31 are classified as confirm (3), not false reacquire")


func _check_s606_exact(info: Dictionary) -> void:
	if info.is_empty():
		return
	var reads: Array = info["broadcast_notable_reads"]
	check(reads.size() == 3 and int(info["broadcast_routine_reads"]) == 131, "s606: 3 discovery READs and 131 routine READs")
	if reads.size() == 3:
		check(int(reads[0]["t"]) == 16 and reads[0]["actor"] == "B" and int(reads[0]["address"]) == 288 and reads[0]["read_kind"] == "enemy_core", "s606: T16 B/raider READ 288 is enemy_core discovery")
		check(int(reads[1]["t"]) == 17 and reads[1]["actor"] == "A" and int(reads[1]["address"]) == 16 and reads[1]["read_kind"] == "enemy_core", "s606: T17 A/striker READ 16 is enemy_core discovery")
		check(int(reads[2]["t"]) == 18 and reads[2]["actor"] == "B" and int(reads[2]["address"]) == 18 and reads[2]["read_kind"] == "own_core_damaged", "s606: T18 B/warden READ 18 is own_core_damaged discovery")
	var recs: Array = info["broadcast_core_recoveries"]
	check(recs.size() == 1 and int(recs[0]["t"]) == 18 and int(recs[0]["address"]) == 18, "s606: T18 B/warden WRITE 18 is core_recovery")


func _check_s202_reverse_exact(info: Dictionary) -> void:
	if info.is_empty():
		return
	var reads: Array = info["broadcast_notable_reads"]
	check(reads.size() == 5 and int(info["broadcast_routine_reads"]) == 164, "s202_ss_vs_ph: 5 discovery READs (3 enemy_cell, 1 enemy_core, 1 own_core_damaged) and 164 routine READs")
	var a_reads: Array = info["agent_a_notable_reads"]
	check(a_reads.size() == 3 and a_reads[2]["read_kind"] == "own_core_damaged", "s202_ss_vs_ph Agent A: 2 enemy_owned READs and 1 own_core_damaged READ at T30")


func _check_short_matches_exact(s101: Dictionary, s404: Dictionary) -> void:
	if not s101.is_empty():
		check(int(s101["ticks"]) == 3 and (s101["broadcast_notable_reads"] as Array).size() == 3 and (s101["broadcast_core_recoveries"] as Array).size() == 2, "s101 (3 ticks): 3 own_core_damaged READs and 2 core_recovery WRITEs")
	if not s404.is_empty():
		check(int(s404["ticks"]) == 2 and (s404["broadcast_notable_reads"] as Array).size() == 1, "s404 (2 ticks): 1 own_core_damaged READ")


func _check_agent_core_recovery_receipt() -> void:
	# Synthetic Agent A document where own core cell 0 is read as owned by B on t2,
	# then read as owned by A on t4: only the delivered t4 READ receipt emits core_recovery.
	var doc := {
		"entrant_id": "A", "name": "test_agent", "label": "Agent A",
		"arena_size": 512, "core_base": 0, "core_size": 8, "opponent_activity": "present",
		"frames": [
			{"t": 0, "p": 2, "cb": null, "processes": [["main", 0, 64]], "contacts": [], "receipt": "NONE", "samples": [], "reads": [], "events": []},
			{"t": 1, "p": 1, "cb": 1, "processes": [["main", 0, 64]], "contacts": [], "receipt": "NONE", "samples": [], "reads": [], "events": [{"kind": "read", "process": "main", "address": 0, "operand": 0, "status": "APPLIED", "sample_status": "ABSENT"}]},
			{"t": 2, "p": 0, "cb": 1, "processes": [["main", 0, 64]], "contacts": [], "receipt": "APPLIED", "samples": [], "reads": [{"address": 0, "value": 1, "owner": "B", "sampled": [1, 1, "main"], "received": [2, 1, "main"]}], "events": []},
			{"t": 2, "p": 1, "cb": 1, "processes": [["main", 0, 64]], "contacts": [], "receipt": "APPLIED", "samples": [], "reads": [], "events": [{"kind": "write", "process": "main", "address": 0, "operand": 0, "status": "APPLIED", "sample_status": "ABSENT"}]},
			{"t": 3, "p": 1, "cb": 1, "processes": [["main", 0, 64]], "contacts": [], "receipt": "APPLIED", "samples": [], "reads": [], "events": [{"kind": "read", "process": "main", "address": 0, "operand": 0, "status": "APPLIED", "sample_status": "ABSENT"}]},
			{"t": 4, "p": 0, "cb": 1, "processes": [["main", 0, 64]], "contacts": [], "receipt": "APPLIED", "samples": [], "reads": [{"address": 0, "value": 2, "owner": "A", "sampled": [3, 1, "main"], "received": [4, 1, "main"]}], "events": []},
			{"t": 4, "p": 2, "cb": null, "processes": [["main", 0, 64]], "contacts": [], "receipt": "APPLIED", "samples": [], "reads": [], "events": []},
		],
	}
	var model := AgentModel.new(doc)
	var cues := SoundCues.agent_cues(model, 0, model.frame_count() - 1)
	check(cues.has({"i": 2, "sound": "read_discovery", "variant": 0}), "Agent A emits read_discovery when delivered READ shows own core damaged")
	check(cues.has({"i": 3, "sound": "write", "variant": 0}) and not cues.has({"i": 3, "sound": "core_recovery", "variant": 0}), "Agent A WRITE on own core emits write, never unconfirmed core_recovery")
	check(cues.has({"i": 5, "sound": "core_recovery", "variant": 0}), "Agent A emits core_recovery when delivered READ confirms own core recovered")


func _check_tab_focus_and_seek_consistency(main: Node, fixture_dir: String) -> void:
	main.open_presentation(fixture_dir)
	check(main._play_button.focus_mode == Control.FOCUS_NONE and main._perspective_button.focus_mode == Control.FOCUS_NONE and main._speed_button.focus_mode == Control.FOCUS_NONE and main._timeline.focus_mode == Control.FOCUS_NONE, "playback controls use FOCUS_NONE so Tab is never trapped by button focus")
	var tab_event := InputEventKey.new()
	tab_event.keycode = KEY_TAB
	tab_event.pressed = true
	main._unhandled_input(tab_event)
	check(main.perspective == "agent_a", "Tab switches Broadcast -> Agent A")
	main._unhandled_input(tab_event)
	check(main.perspective == "broadcast", "Tab switches Agent A -> Broadcast")

	# Seek / step / pause / resume consistency of turning_points and captions.
	var expected_tps := {}
	var expected_captions := {}
	main.restart()
	for i in main.frame_count():
		if i > 0:
			main.step_frame(1)
		expected_tps[i] = main.effects.turning_points(i).duplicate(true)
		expected_captions[i] = main._caption.text
	var max_t: int = main.broadcast.max_tick
	var seek_ticks: Array = [14, 11, 4, 12, 0, 13, 7, 11] if max_t == 14 else [max_t, max_t * 3 / 4, max_t / 4, max_t / 2, 0, max_t - 1, max_t / 8, max_t / 2]
	for target_tick in seek_ticks:
		main.seek_tick(target_tick)
		var idx: int = main.index
		check(main.effects.turning_points(idx) == expected_tps[idx] and main._caption.text == expected_captions[idx], "seek to tick %d reconstructs identical turning points and caption" % target_tick)
