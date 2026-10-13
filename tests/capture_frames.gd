extends SceneTree
## Renders viewer screenshots of a fixture at chosen ticks, in both perspectives.
##
## Needs a real renderer (not --headless):
##   godot --path . --script res://tests/capture_frames.gd -- --fixture=<dir> --out=<dir> --ticks=0,100,200
## Writes <out>/<perspective>-tick-<n>.png for each tick and perspective.

var _main: Node
var _out := ""
var _jobs: Array = []
var _frame := 0


func _initialize() -> void:
	var ticks: Array = []
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg.begins_with("--ticks="):
			for part in arg.trim_prefix("--ticks=").split(","):
				ticks.append(int(part))
	for perspective in ["broadcast", "agent_a"]:
		for tick in ticks:
			_jobs.append([perspective, tick])
	DirAccess.make_dir_recursive_absolute(_out)
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)  # main reads --fixture= itself in _ready


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 3:
		return false
	if _main.load_error != "":
		printerr("fixture rejected: ", _main.load_error)
		quit(1)
		return true
	# Even frames set the view; odd frames save what the previous frame drew.
	var step := _frame - 3
	var job_index := step / 2
	if job_index >= _jobs.size():
		quit(0)
		return true
	var job: Array = _jobs[job_index]
	if step % 2 == 0:
		_main.set_perspective(job[0])
		_main.seek_tick(job[1])
	else:
		var path: String = _out.path_join("%s-tick-%04d.png" % [job[0], job[1]])
		root.get_texture().get_image().save_png(path)
		print("saved ", path)
	return false
