extends SceneTree
## Records everything the Agent A perspective shows, for differential tests.
##
## Run: godot --headless --path . --script res://tests/agent_view_trace.gd -- --fixture=<dir> --out=<file>
##
## Each line is one observation of the visible agent-perspective outputs (title,
## caption, side panel, position label, timeline value and range, footer and the
## ring view's state) after a viewer operation: stepping every frame, stepping
## ticks backwards, seeking every tick, dragging the timeline, playing at a fixed
## frame rate, and switching in from every broadcast frame. Switching lines are
## run-length collapsed, because how many broadcast frames map to one agent
## position is broadcast data, not agent data.

var _main: Node
var _frame := 0
var _out := ""


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)  # main reads --fixture= itself in _ready


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 2:
		return false
	var lines := PackedStringArray()
	if _main.load_error != "":
		lines.append("LOAD ERROR " + _main.load_error)
	else:
		_record(lines)
	var file := FileAccess.open(_out, FileAccess.WRITE)
	file.store_string("\n".join(lines) + "\n")
	file.close()
	print("agent view trace: %d lines" % lines.size())
	quit(0 if _main.load_error == "" else 1)
	return true


func _observe(tag: String) -> String:
	var m := _main
	return "|".join([
		tag, m.perspective, m._title.text, m._caption.text, m._side.text.replace("\n", "\\n"),
		m._position_label.text, "%d/%d" % [int(m._timeline.value), int(m._timeline.max_value)],
		m._footer.text, JSON.stringify(m._ring.state),
	])


func _record(lines: PackedStringArray) -> void:
	var m := _main
	m.set_perspective("agent_a")
	m.restart()
	lines.append(_observe("step"))
	for i in range(1, m.frame_count()):
		m.step_frame(1)
		lines.append(_observe("step"))
	while m.current_tick() > 0:
		m.step_tick(-1)
		lines.append(_observe("tick-back"))
	for tick in range(0, m.tick_limit + 2):
		m.seek_tick(tick)
		lines.append(_observe("seek"))
	for tick in range(0, m.tick_limit + 1):
		m._timeline.value = tick
		lines.append(_observe("slider"))
	m.restart()
	m.ticks_per_second = 20.0
	m.set_playing(true)
	var guard := 0
	while m.playing and guard < 100000:
		m._process(0.037)
		lines.append(_observe("play"))
		guard += 1
	m.set_playing(false)
	var last := ""
	m.set_perspective("broadcast")
	for i in range(m.broadcast.frame_count()):
		m.set_perspective("broadcast")
		m.index = i
		m._refresh()
		m.set_perspective("agent_a")
		var seen := _observe("switch")
		if seen != last:
			lines.append(seen)
			last = seen
