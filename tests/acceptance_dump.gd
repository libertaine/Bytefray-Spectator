extends SceneTree
## Records what the viewer shows for one presentation, for comparison with
## Bytefray's authoritative match records (exporter/tests/test_production_export.py).
##
## Run: godot --headless --path . --script res://tests/acceptance_dump.gd -- --fixture=<dir> --perspective=broadcast --out=<file.json>
##
## The presentation enters through the viewer's own launch options, exactly as
## Designer passes them; the viewer is then stepped frame by frame through its
## public navigation in both perspectives. Exit code 0 = dump written, 1 = the
## viewer rejected the presentation (the reason is printed).

var _main: Node
var _frame := 0
var _out := ""


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.substr("--out=".length())
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)  # _ready reads --fixture/--perspective like any launch


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 2:
		return false
	if not _main.load_error.is_empty():
		printerr("REJECTED: ", _main.load_error)
		quit(1)
		return true
	var dump := {
		"manifest_version": int(_main.manifest["schema_version"]),
		"window_title": _main.get_window().title,
		"footer": _main._footer.text,
		"broadcast": _broadcast(_main),
		"agent_a": _agent(_main),
	}
	var file := FileAccess.open(_out, FileAccess.WRITE)
	file.store_string(JSON.stringify(dump))
	file.close()
	print("ACCEPTANCE DUMP WRITTEN")
	quit(0)
	return true


func _broadcast(main: Node) -> Dictionary:
	main.set_perspective("broadcast")
	main.restart()
	var actions: Array = []
	var tick_ends: Array = []
	for i in main.frame_count():
		if i > 0:
			main.step_frame(1)
		var frame: Dictionary = main.broadcast.frames[main.index]
		if int(frame["p"]) == 1:
			actions.append([int(frame["t"]), frame["actor"], frame["process"], frame["kind"], frame["status"], frame["address"]])
		elif int(frame["p"]) == 2:
			tick_ends.append([int(frame["t"]), frame["alive"]])
	return {
		"actions": actions,
		"tick_ends": tick_ends,
		"result": main.broadcast.result,
		"banner": main._ring.banner,
		"end_tick": main.current_tick(),
		"panel_result_line": Array(main._side.text.split("\n")).filter(func(l: String) -> bool: return l.begins_with("Result:")),
	}


func _agent(main: Node) -> Dictionary:
	main.set_perspective("agent_a")
	main.restart()
	var events: Array = []
	var samples: Array = []
	var reads: Array = []
	for i in main.frame_count():
		if i > 0:
			main.step_frame(1)
		var frame: Dictionary = main.agent.frames[main.index]
		for event in frame["events"]:
			if event["status"] != null:
				events.append([int(frame["t"]), event["process"], event["kind"], event["status"], event["address"]])
		for sample in frame["samples"]:
			samples.append([int(sample["sampled"][0]), int(sample["received"][0]), int(sample["center"]), sample["status"], sample["addresses"]])
		for read in frame["reads"]:
			reads.append([int(read["sampled"][0]), int(read["address"]), int(read["value"]), read["owner"]])
	return {
		"name": main.agent.entrant_name,
		"events": events,
		"samples": samples,
		"reads": reads,
		"position_label": main._position_label.text,
		"panel": main._side.text,
	}
