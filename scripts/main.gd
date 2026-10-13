extends Control
## Bytefray Spectator main screen: loads a verified fixture and plays it back
## in the broadcast or Agent A perspective.
##
## Perspectives are separate models built from separate files. Switching maps
## the position on tick boundaries only (never a global decision index), so the
## agent perspective cannot be positioned by hidden opponent activity. The agent
## perspective shows only the public tick limit, never when the match ends.

const FixtureLoader := preload("res://scripts/fixture_loader.gd")
const BroadcastModel := preload("res://scripts/broadcast_model.gd")
const AgentModel := preload("res://scripts/agent_model.gd")
const RingView := preload("res://scripts/ring_view.gd")

const DEFAULT_FIXTURE := "res://fixtures/dev/presentation"
const SPEEDS := [1.0, 5.0, 20.0, 60.0, 200.0]  # ticks per second
const PHASE_NAMES := ["OBSERVATION", "ACTION", "TICK_END"]
const PERSPECTIVES := ["broadcast", "agent_a"]

var manifest: Dictionary = {}
var tick_limit := 0
var broadcast: BroadcastModel
var agent: AgentModel
var perspective := "broadcast"
var index := 0
var playing := false
var ticks_per_second: float = SPEEDS[1]
var load_error := ""

var _accumulator := 0.0
var _syncing_slider := false

var _ring: RingView
var _title: Label
var _position_label: Label
var _caption: Label
var _side: RichTextLabel
var _footer: Label
var _play_button: Button
var _perspective_button: OptionButton
var _speed_button: OptionButton
var _timeline: HSlider
var _controls: Array[Control] = []


func _ready() -> void:
	_build_ui()
	var fixture := DEFAULT_FIXTURE
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--fixture="):
			fixture = arg.trim_prefix("--fixture=")
	load_fixture(fixture)


func load_fixture(dir: String) -> String:
	playing = false
	broadcast = null
	agent = null
	manifest = {}
	load_error = _load(dir)
	for control in _controls:
		control.set("disabled", not load_error.is_empty())
	if load_error.is_empty():
		perspective = "broadcast"
		_perspective_button.select(0)
		index = 0
		_refresh()
	else:
		_ring.clear()
		_title.text = "Fixture rejected"
		_position_label.text = ""
		_caption.text = load_error
		_side.text = ""
		_footer.text = "Nothing is shown from an unverified fixture."
	return load_error


func _load(dir: String) -> String:
	var loaded := FixtureLoader.load_manifest(dir)
	if loaded.has("error"):
		return loaded["error"]
	var candidate: Dictionary = loaded["manifest"]
	var b := FixtureLoader.load_presentation(dir, candidate, "broadcast")
	if b.has("error"):
		return b["error"]
	var a := FixtureLoader.load_presentation(dir, candidate, "agent_a")
	if a.has("error"):
		return a["error"]
	manifest = candidate
	tick_limit = int(candidate["match"]["tick_limit"])
	broadcast = BroadcastModel.new(b["document"])
	agent = AgentModel.new(a["document"])
	return ""


func current_model():  # BroadcastModel or AgentModel (same duck-typed API)
	return broadcast if perspective == "broadcast" else agent


func frame_count() -> int:
	return current_model().frame_count()


func current_tick() -> int:
	return current_model().tick_of(index)


func set_perspective(target: String) -> void:
	if not load_error.is_empty() or target == perspective or not PERSPECTIVES.has(target):
		return
	var model = current_model()
	# Land on the other model's last completed tick boundary at or before here.
	var tick: int = model.tick_of(index)
	var boundary: int = tick if model.is_tick_end(index) else tick - 1
	perspective = target
	_perspective_button.select(PERSPECTIVES.find(target))
	index = current_model().index_for_tick_end(boundary)
	_refresh()


func restart() -> void:
	index = 0
	_refresh()


func step_frame(delta: int) -> void:
	index = clampi(index + delta, 0, frame_count() - 1)
	_refresh()


func step_tick(delta: int) -> void:
	var model = current_model()
	seek_tick(model.tick_of(index) + delta if model.is_tick_end(index) or delta < 0 else model.tick_of(index))


func seek_tick(tick: int) -> void:
	index = current_model().index_for_tick_end(tick)
	_refresh()


func set_playing(value: bool) -> void:
	playing = value and load_error.is_empty()
	_accumulator = 0.0
	if _play_button:
		_play_button.text = "Pause" if playing else "Play"


func _process(delta: float) -> void:
	if not playing:
		return
	_accumulator += delta * ticks_per_second
	while _accumulator >= 1.0:
		_accumulator -= 1.0
		var model = current_model()
		if model.tick_of(index) >= model.max_tick and model.is_tick_end(index):
			set_playing(false)
			return
		seek_tick(model.tick_of(index) + (1 if model.is_tick_end(index) else 0))


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed) or not load_error.is_empty():
		return
	match event.keycode:
		KEY_SPACE:
			set_playing(not playing)
		KEY_RIGHT, KEY_LEFT:
			var direction := 1 if event.keycode == KEY_RIGHT else -1
			if event.shift_pressed:
				step_tick(direction)
			else:
				step_frame(direction)
		KEY_HOME:
			restart()
		KEY_TAB:
			set_perspective("agent_a" if perspective == "broadcast" else "broadcast")
		_:
			return
	get_viewport().set_input_as_handled()


func _refresh() -> void:
	if not load_error.is_empty():
		return
	var model = current_model()
	var state: Dictionary = model.state(index)
	var tick := int(state["tick"])
	var phase: String = PHASE_NAMES[int(state["phase"])]
	if perspective == "broadcast":
		_ring.show_broadcast(state, broadcast.entrants, broadcast.arena_size)
		_title.text = "Broadcast - full world state"
		_caption.text = state["caption"]
		_side.text = _broadcast_panel(tick)
	else:
		_ring.show_agent(state, agent.arena_size)
		_title.text = "Agent %s (%s) - delivered information only" % [agent.entrant_id, agent.entrant_name]
		_caption.text = "Receipt: %s   Opponent activity: %s" % [state["receipt"], agent.opponent_activity]
		_side.text = _agent_panel(state)
	if perspective == "broadcast":
		_position_label.text = "Tick %d / %d   %s   frame %d / %d" % [tick, model.max_tick, phase, index + 1, model.frame_count()]
	else:
		# No match length or frame total: either would reveal when the match ends.
		_position_label.text = "Tick %d (limit %d)   %s   step %d" % [tick, tick_limit, phase, index + 1]
	_syncing_slider = true
	_timeline.max_value = broadcast.max_tick if perspective == "broadcast" else tick_limit
	_timeline.value = tick
	_syncing_slider = false
	var match_info: Dictionary = manifest["match"]
	_footer.text = "Verified fixture  |  Bytefray %s  |  %s  |  arena %d  |  seed %d  |  manifest digests OK" % [
		String(manifest["bytefray"]["commit"]).substr(0, 7), match_info["ruleset_id"],
		int(match_info["arena_size"]), int(match_info["seed"]),
	]


func _broadcast_panel(tick: int) -> String:
	var lines: PackedStringArray = []
	var alive: Array = broadcast.state(index)["alive"]
	for i in broadcast.entrants.size():
		var entrant: Dictionary = broadcast.entrants[i]
		var color := RingView.ENTRANT_COLORS[i % RingView.ENTRANT_COLORS.size()].to_html(false)
		lines.append("[color=#%s]%s[/color] %s  %s  core %d/8" % [
			color, entrant["id"], entrant["name"],
			"alive" if alive.has(entrant["id"]) else "eliminated",
			broadcast.core_cells_owned(index, i),
		])
	if tick >= broadcast.max_tick and broadcast.is_tick_end(index):
		lines.append("")
		lines.append("Result: %s (%s, %d ticks)" % [
			broadcast.result["winner"], broadcast.result["termination_reason"], int(broadcast.result["ticks"]),
		])
	return "\n".join(lines)


func _agent_panel(state: Dictionary) -> String:
	var lines: PackedStringArray = ["Own core: cells %d-%d" % [
		int(state["core_base"]), (int(state["core_base"]) + int(state["core_size"]) - 1) % agent.arena_size,
	]]
	for process in state["processes"]:
		lines.append("Process %s at %d (reach %d)" % [process[0], int(process[1]), int(process[2])])
	lines.append("Contacts (historical, anonymous): %d" % (state["contacts"] as Array).size())
	for contact in state["contacts"]:
		lines.append("  cell %d, sampled tick %d, age %d ticks%s" % [
			int(contact["address"]), int(contact["sampled"][0]), int(contact["age_ticks"]),
			" (absent in a newer sample)" if contact["stale_since"] != null else "",
		])
	lines.append("")
	lines.append("Recent own events:")
	for event in state["recent_events"]:
		var text := String(event["kind"])
		if event["address"] != null:
			text += " %d" % int(event["address"])
		if event["status"] != null:
			text += " -> %s" % event["status"]
		lines.append("  %s  %s" % [text, event["message"]])
	return "\n".join(lines)


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 6)
	add_child(root)

	var header := HBoxContainer.new()
	root.add_child(header)
	_title = Label.new()
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.add_theme_font_size_override("font_size", 20)
	header.add_child(_title)
	_perspective_button = OptionButton.new()
	_perspective_button.add_item("Broadcast")
	_perspective_button.add_item("Agent A")
	_perspective_button.item_selected.connect(func(i: int) -> void: set_perspective(PERSPECTIVES[i]))
	header.add_child(_perspective_button)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)
	_ring = RingView.new()
	_ring.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ring.size_flags_stretch_ratio = 2.0
	body.add_child(_ring)
	_side = RichTextLabel.new()
	_side.bbcode_enabled = true
	_side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(_side)

	_caption = Label.new()
	root.add_child(_caption)
	_position_label = Label.new()
	root.add_child(_position_label)

	_timeline = HSlider.new()
	_timeline.step = 1
	_timeline.value_changed.connect(
		func(value: float) -> void:
			if not _syncing_slider:
				seek_tick(int(value))
	)
	root.add_child(_timeline)

	var controls := HBoxContainer.new()
	root.add_child(controls)
	_add_button(controls, "Restart", restart)
	_add_button(controls, "<< Tick", func() -> void: step_tick(-1))
	_add_button(controls, "< Step", func() -> void: step_frame(-1))
	_play_button = _add_button(controls, "Play", func() -> void: set_playing(not playing))
	_add_button(controls, "Step >", func() -> void: step_frame(1))
	_add_button(controls, "Tick >>", func() -> void: step_tick(1))
	_speed_button = OptionButton.new()
	for speed in SPEEDS:
		_speed_button.add_item("%d ticks/s" % int(speed))
	_speed_button.select(1)
	_speed_button.item_selected.connect(func(i: int) -> void: ticks_per_second = SPEEDS[i])
	controls.add_child(_speed_button)
	_controls.append_array([_perspective_button, _speed_button, _timeline])

	_footer = Label.new()
	_footer.add_theme_font_size_override("font_size", 12)
	root.add_child(_footer)


func _add_button(parent: Control, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(callback)
	parent.add_child(button)
	_controls.append(button)
	return button
