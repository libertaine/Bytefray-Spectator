extends Control
## Bytefray Spectator main screen: loads a verified fixture and plays it back
## in the broadcast or Agent A perspective.
##
## Perspectives are separate models built from separate files. Switching maps
## the position on tick boundaries only (never a global decision index), so the
## agent perspective cannot be positioned by hidden opponent activity. The agent
## perspective shows only the public tick limit, never when the match ends.
##
## Playback gives every recorded frame of a tick an equal, in-order share of
## that tick's time, so at slow speeds each action of a tick appears in turn.
## (At faster speeds a display frame can span several recorded frames; the
## effects persist for 3 ticks, so the ring still shows them.) Each
## perspective is paced by its own frames only.
##
## Launch options (after `--`): --fixture=showcase|dev|<dir> (default
## showcase), --perspective=broadcast|agent_a, --tick=<n>, --speed=<ticks/s>
## (one of SPEEDS), --rendering=classic|filled_arcs and --play.
##
## Sound effects play only while playing, for the recorded frames playback has
## just passed, from the current perspective's own model (Agent A's from
## agent_a.json alone). Every seek, step, restart, perspective switch or
## fixture load cuts them, so a jump never replays the past. Pausing holds
## them; resuming at the same position continues them.
##
## The announcer's opening sequence (rumble, then FIGHT) plays when playback
## starts at tick 0 with sound on; playing from any later tick skips it. It
## holds the match clock: the match starts only once it has finished. Pausing
## holds it, and a seek, a switch or turning sound off ends it. The victory call
## is a broadcast sound cue at the recorded end (see sound_cues.gd).

const FixtureLoader := preload("res://scripts/fixture_loader.gd")
const BroadcastModel := preload("res://scripts/broadcast_model.gd")
const BroadcastEffects := preload("res://scripts/broadcast_effects.gd")
const AgentModel := preload("res://scripts/agent_model.gd")
const RingView := preload("res://scripts/ring_view.gd")
const LegendView := preload("res://scripts/legend_view.gd")
const SoundCues := preload("res://scripts/sound_cues.gd")
const SoundEffects := preload("res://scripts/sound_effects.gd")

const FIXTURES := {
	"showcase": "res://fixtures/showcase/presentation",
	"dev": "res://fixtures/dev/presentation",
}
const DEFAULT_FIXTURE := "res://fixtures/showcase/presentation"
const SPEEDS := [1.0, 2.0, 5.0, 10.0, 20.0, 60.0, 200.0]  # ticks per second
const DEFAULT_SPEED := 2  # index of 5 ticks/s
const PHASE_NAMES := ["OBSERVATION", "ACTION", "TICK_END"]
const PERSPECTIVES := ["broadcast", "agent_a"]
const REASONS := {
	"last_agent_standing": "last agent standing",
	"all_agents_dead": "all agents eliminated",
	"tick_limit": "tick limit reached",
}
const RECENT_ACTIONS := 6
# Options read by the test and capture scripts, not by the viewer.
const TEST_OPTIONS := ["--out=", "--ticks=", "--core-log=", "--fps=", "--frames="]
const NO_COUNTS := {"writes": 0, "took": 0, "core_hits": 0, "recovered": 0, "hits": 0, "moves": 0, "senses": 0, "reads": 0, "refused": 0}
# Static text: the same at every position, so it reveals nothing about the match.
const INTRO_CAPTION := "Get ready...  (the match starts after the opening cue; seek to skip)"
const AGENT_NOTE := "Agent A is never told the outcome. Switch to Broadcast (Tab) to see it."
const KEY_HINT := "Space play  |  Left/Right step  |  Shift+Left/Right tick  |  Home/End  |  G jump to tick  |  Tab perspective  |  -/+ speed  |  L legend  |  M sound  |  H help"
const HELP := """Keyboard
  Space                  Play / pause
  Right / Left           Step one recorded frame
  Shift+Right / Left     Step one tick
  Home / End             Restart / jump to the last tick
  G                      Jump to a tick (type it, then Enter)
  Tab                    Switch Broadcast / Agent A
  - / +                  Slower / faster playback
  L                      Show or hide the legend
  M                      Sound effects and arcade cues on / off (volume beside it)
  H or F1                Show or hide this help

Playback gives every recorded action of a tick an equal, in-order share
of its time: at 1 tick/s each one appears in turn. Effects fade over
3 ticks; any seek redraws them from the record. Sounds play only
while playing; a seek never replays them. Playing from tick 0
starts with the opening cue; from a later tick it is skipped."""

var manifest: Dictionary = {}
var tick_limit := 0
var sense_half_width := -1  # public ruleset constant (manifest ruleset)
var broadcast: BroadcastModel
var effects: BroadcastEffects
var sound: SoundEffects
var agent: AgentModel
var perspective := "broadcast"
var index := 0
var playing := false
var ticks_per_second: float = SPEEDS[DEFAULT_SPEED]
var load_error := ""

var _play_base := 0  # last completed tick boundary of the playback interval
var _play_progress := 0.0  # ticks elapsed since that boundary, in [0, 1)
var _play_index := -1  # index playback last set (anything else means a seek)
var _syncing_slider := false
var _sound_paused_at: Array = []  # [perspective, index] where playback paused the sound
var _intro_left := 0.0  # seconds of the opening sequence still to play (0 = none)

var _ring: RingView
var _legend: LegendView
var _title: Label
var _position_label: Label
var _caption: Label
var _side: RichTextLabel
var _hint: Label
var _footer: Label
var _help: PanelContainer
var _play_button: Button
var _perspective_button: OptionButton
var _rendering_button: OptionButton
var _speed_button: OptionButton
var _timeline: HSlider
var _jump: LineEdit
var _sound_toggle: CheckButton
var _volume: HSlider
var _controls: Array[Control] = []


func _ready() -> void:
	_build_ui()
	var options := launch_options(OS.get_cmdline_user_args())
	if load_fixture(options["fixture"]).is_empty():
		apply_launch_options(options)


## Parses launch options; an unrecognised value is reported and ignored.
static func launch_options(args: PackedStringArray) -> Dictionary:
	var options := {"fixture": DEFAULT_FIXTURE, "perspective": "broadcast", "tick": -1, "speed": -1, "play": false, "rendering": "filled_arcs"}
	for arg in args:
		var value := arg.get_slice("=", 1)
		if arg.begins_with("--fixture="):
			options["fixture"] = FIXTURES.get(value, value)
		elif arg.begins_with("--perspective=") and PERSPECTIVES.has(value):
			options["perspective"] = value
		elif arg.begins_with("--tick=") and value.is_valid_int() and int(value) >= 0:
			options["tick"] = int(value)
		elif arg.begins_with("--speed=") and value.is_valid_float() and SPEEDS.has(float(value)):
			options["speed"] = SPEEDS.find(float(value))
		elif arg.begins_with("--rendering=") and RingView.RENDER_MODES.has(value):
			options["rendering"] = value
		elif arg == "--play":
			options["play"] = true
		elif not TEST_OPTIONS.any(func(prefix: String) -> bool: return arg.begins_with(prefix)):
			printerr("Ignoring unrecognised launch option: ", arg)
	return options


func apply_launch_options(options: Dictionary) -> void:
	set_rendering_mode(options.get("rendering", "filled_arcs"))
	set_perspective(options["perspective"])
	if int(options["tick"]) >= 0:
		seek_tick(int(options["tick"]))
	if int(options["speed"]) >= 0:
		set_speed_index(int(options["speed"]))
	set_playing(options["play"])


## A presentation setting only: changing it never jumps, pauses or cuts sound.
func set_rendering_mode(value: String) -> void:
	if RingView.RENDER_MODES.has(value):
		_ring.set_rendering_mode(value)
		_rendering_button.select(RingView.RENDER_MODES.find(value))


func set_speed_index(i: int) -> void:
	i = clampi(i, 0, SPEEDS.size() - 1)
	ticks_per_second = SPEEDS[i]
	_speed_button.select(i)


func load_fixture(dir: String) -> String:
	playing = false
	broadcast = null
	effects = null
	agent = null
	manifest = {}
	_jumped()
	load_error = _load(dir)
	for control in _controls:
		control.set("disabled", not load_error.is_empty())
	_jump.editable = load_error.is_empty()
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
	sense_half_width = int(BroadcastEffects.SENSE_HALF_WIDTH.get(String(candidate["match"]["ruleset_id"]), -1))
	broadcast = BroadcastModel.new(b["document"])
	effects = BroadcastEffects.new(broadcast)
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
	_jumped()  # resume playback from this boundary, paced by this perspective
	_refresh()


func restart() -> void:
	index = 0
	_jumped()
	_refresh()


func step_frame(delta: int) -> void:
	index = clampi(index + delta, 0, frame_count() - 1)
	_jumped()
	_refresh()


func step_tick(delta: int) -> void:
	var model = current_model()
	seek_tick(model.tick_of(index) + delta if model.is_tick_end(index) or delta < 0 else model.tick_of(index))


func seek_tick(tick: int) -> void:
	index = current_model().index_for_tick_end(tick)
	_jumped()
	_refresh()


## The last tick of the timeline. In Agent A this is the public tick limit,
## which the model clamps to the end of Agent A's own record, like any seek.
func jump_to_end() -> void:
	seek_tick(int(_timeline.max_value))


## Seeks to a typed tick number; anything else is ignored.
func jump_to_tick(text: String) -> bool:
	var value := text.strip_edges()
	if load_error.is_empty() and value.is_valid_int() and int(value) >= 0:
		seek_tick(int(value))
		return true
	return false


## Plays or pauses. Pausing holds the sound; playing again at the same
## position continues it, anywhere else starts from silence. At the recorded
## end (`ring_out`) the last sounds are left to finish.
func set_playing(value: bool, ring_out: bool = false) -> void:
	var was_playing := playing
	playing = value and load_error.is_empty()
	_play_index = -1
	if _play_button:
		_play_button.text = "Pause" if playing else "Play"
	if playing and not was_playing:
		if _sound_paused_at == [perspective, index]:
			sound.resume()  # an opening sequence in progress continues too
		else:
			sound.stop_all()
			_intro_left = 0.0
			if load_error.is_empty() and current_tick() == 0:
				_intro_left = sound.play_intro(index)
		_sound_paused_at = []
	elif was_playing and not playing and not ring_out:
		sound.pause()
		_sound_paused_at = [perspective, index]
	if not load_error.is_empty():
		return
	if playing:
		_sync_play_position()
	_refresh()  # the broadcast caption differs between playing and paused


## Any change of position other than playback: nothing heard before it continues.
func _jumped() -> void:
	_play_index = -1
	_sound_paused_at = []
	_intro_left = 0.0
	if sound:
		sound.stop_all()


func set_sound_enabled(value: bool) -> void:
	sound.set_enabled(value)
	_sound_toggle.set_pressed_no_signal(value)
	_sound_settings_changed()


## Seconds of the opening sequence still to play (0 when none is playing).
func intro_left() -> float:
	return _intro_left


## Turning sound off or the volume to zero ends the opening sequence: the match starts.
func _sound_settings_changed() -> void:
	if _intro_left > 0.0 and not sound.is_audible():
		sound.stop_all()
		_intro_left = 0.0
		if playing:
			_sync_play_position()
		_refresh()


## Playback position from the current index: the last completed tick boundary
## and how far through the next tick's frames the index is.
func _sync_play_position() -> void:
	var model = current_model()
	if model.is_tick_end(index):
		_play_base = model.tick_of(index)
		_play_progress = 0.0
	else:
		_play_base = model.tick_of(index) - 1
		var start: int = model.index_for_tick_end(_play_base)
		var count: int = model.index_for_tick_end(_play_base + 1) - start
		_play_progress = float(index - start) / float(count)
	_play_index = index


func _process(delta: float) -> void:
	if not playing:
		return
	var model = current_model()
	if index != _play_index:
		_jumped()  # moved by something other than playback
		_sync_play_position()
	if _intro_left > 0.0:
		# The opening sequence holds the match clock; its time is not match time.
		_intro_left -= delta
		sound.play_cues([], delta)
		if _intro_left <= 0.0:
			_intro_left = 0.0
			_sync_play_position()
		_refresh()
		return
	var from := index
	_play_progress += delta * ticks_per_second
	var whole := int(floor(_play_progress))
	_play_base += whole
	_play_progress -= whole
	if _play_base >= model.max_tick:
		index = model.index_for_tick_end(model.max_tick)
		_play_sounds(from, delta)
		set_playing(false, true)
		return
	# Each frame of the next tick, its TICK_END included, gets an equal share.
	var start: int = model.index_for_tick_end(_play_base)
	var count: int = model.index_for_tick_end(_play_base + 1) - start
	index = start + int(floor(_play_progress * count))
	_play_index = index
	_play_sounds(from, delta)
	_refresh()


## Sounds of the recorded frames playback just passed, (from, index], from the
## current perspective's own model.
func _play_sounds(from: int, elapsed: float) -> void:
	var cues: Array
	if perspective == "broadcast":
		cues = SoundCues.broadcast_cues(broadcast, effects, from, index)
	else:
		cues = SoundCues.agent_cues(agent, from, index)
	sound.play_cues(cues, elapsed)


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
		KEY_END:
			jump_to_end()
		KEY_TAB:
			set_perspective("agent_a" if perspective == "broadcast" else "broadcast")
		KEY_G:
			_jump.grab_focus()
			_jump.select_all()
		KEY_MINUS, KEY_KP_SUBTRACT:
			set_speed_index(SPEEDS.find(ticks_per_second) - 1)
		KEY_EQUAL, KEY_PLUS, KEY_KP_ADD:
			set_speed_index(SPEEDS.find(ticks_per_second) + 1)
		KEY_L:
			_legend.visible = not _legend.visible
		KEY_M:
			set_sound_enabled(not sound.is_enabled())
		KEY_H, KEY_F1, KEY_SLASH:
			_help.visible = not _help.visible
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
	_legend.set_perspective(perspective)
	if perspective == "broadcast":
		var shown := effects.at(index)
		var cores := effects.cores(index)
		_ring.show_broadcast(state, broadcast.entrants, broadcast.arena_size, _result_banner(tick), shown, cores)
		_title.text = "Broadcast - full world state"
		_caption.text = _broadcast_caption()
		_side.text = _broadcast_panel(state, shown, cores)
	else:
		_ring.show_agent(state, agent.arena_size, sense_half_width)
		_title.text = "Agent %s (%s) - delivered information only" % [agent.entrant_id, agent.entrant_name]
		_caption.text = "Receipt: %s   Opponent activity: %s" % [state["receipt"], agent.opponent_activity]
		_side.text = _agent_panel(state)
	if _intro_left > 0.0:
		_caption.text = INTRO_CAPTION
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


## While playing, mid-tick frames go by too fast to read, so the caption holds
## the summary of the last completed tick. Paused, it describes this frame.
func _broadcast_caption() -> String:
	if playing and not broadcast.is_tick_end(index):
		var last: int = broadcast.tick_of(index) - 1
		return frame_caption(broadcast.index_for_tick_end(last)) if last >= 0 else ""
	return frame_caption(index)


## The broadcast caption of frame `at`: the recorded fact and its recorded
## outcome; at a tick end, the summary of that tick.
func frame_caption(at: int) -> String:
	var text := broadcast.caption(at)
	if broadcast.is_tick_end(at):
		for action in effects.decisive_at(at):
			text += "  -  decisive capture: %s/%s WRITE %d" % [action["actor"], action["process"], int(action["address"])]
		var summary := summary_text(effects.tick_summary(at))
		return text + ("  -  " + summary if summary != "" else "")
	var action := effects.action_at(at)
	if not action.is_empty():
		return text + _outcome_text(action)
	var sense := effects.delivery_at(at)
	if not sense.is_empty():
		text += "  -  SENSE sample from tick %d delivered (%s)" % [int(sense["t"]), _anchors_text(sense["sensed"])]
	return text


func _outcome_text(action: Dictionary) -> String:
	var parts: PackedStringArray = []
	match String(action["kind"]):
		"write":
			if action["outcome"] == "took":
				parts.append("took the cell")
			elif action["outcome"] == "kept":
				parts.append("owner unchanged")
			var owner := int(action["core_owner"])
			if action["core_change"] == "damage":
				parts.append("%s core cell lost" % broadcast.entrants[owner]["id"])
			elif action["core_change"] == "recovery":
				parts.append("%s core cell regained" % broadcast.entrants[owner]["id"])
			for hit in action["hits"]:
				parts.append("hits %s/%s" % [hit[0], hit[1]])
			if action["decisive"]:
				parts.append("DECISIVE CAPTURE")
		"move":
			if action["outcome"] != "refused":
				parts.append("%d -> %d" % [int(action["from"]), posmod(int(action["from"]) + int(action["delta"]), broadcast.arena_size)])
		"sense":
			if action["outcome"] != "refused":
				parts.append("sampled %s" % _anchors_text(action["sensed"]))
	return "" if parts.is_empty() else "  -  " + ", ".join(parts)


static func _anchors_text(anchors: Array) -> String:
	if anchors.is_empty():
		return "nothing"
	var cells: PackedStringArray = []
	for anchor in anchors:
		cells.append(str(int(anchor)))
	return "%s at %s" % ["1 anchor" if anchors.size() == 1 else "%d anchors" % anchors.size(), ", ".join(cells)]


## One line per entrant with actions: "A: 7 writes (took 3, 2 core), 1 sense".
func summary_text(summary: Array) -> String:
	var entrant_parts: PackedStringArray = []
	for e in summary.size():
		var counts: Dictionary = summary[e]
		var parts: PackedStringArray = []
		if counts["writes"] > 0:
			var detail: PackedStringArray = []
			if counts["took"] > 0:
				detail.append("took %d" % counts["took"])
			if counts["core_hits"] > 0:
				detail.append("%d core" % counts["core_hits"])
			if counts["recovered"] > 0:
				detail.append("%d own core back" % counts["recovered"])
			if counts["hits"] > 0:
				detail.append("%d hit%s" % [counts["hits"], "" if counts["hits"] == 1 else "s"])
			parts.append("%d write%s%s" % [counts["writes"], "" if counts["writes"] == 1 else "s", " (%s)" % ", ".join(detail) if not detail.is_empty() else ""])
		for key in ["senses", "moves", "reads", "refused"]:
			if counts[key] > 0:
				parts.append("%d %s" % [counts[key], key.trim_suffix("s") if counts[key] == 1 else key])
		if not parts.is_empty():
			entrant_parts.append("%s: %s" % [broadcast.entrants[e]["id"], ", ".join(parts)])
	return "   ".join(entrant_parts)


func _broadcast_panel(state: Dictionary, shown: Dictionary, cores: Array) -> String:
	var lines: PackedStringArray = []
	var tick := int(state["tick"])
	var alive: Array = state["alive"]
	for i in broadcast.entrants.size():
		var entrant: Dictionary = broadcast.entrants[i]
		var color := RingView.ENTRANT_COLORS[i % RingView.ENTRANT_COLORS.size()].to_html(false)
		var note := RingView.core_note(cores[i])
		lines.append("[color=#%s]%s[/color] %s  %s  core %d/%d%s" % [
			color, entrant["id"], entrant["name"],
			"alive" if alive.has(entrant["id"]) else "eliminated",
			int(cores[i]["held"]), int(cores[i]["size"]),
			"" if note == "" or note == "ELIMINATED" else "  (%s)" % note,
		])
	lines.append("")
	lines.append("Tick %d so far:" % tick)
	var summary: Array = effects.tick_summary(index)
	for i in summary.size():
		var only: Array = []
		for e in summary.size():
			only.append(summary[e] if e == i else NO_COUNTS)
		var text := summary_text(only)
		lines.append("  %s" % (text if text != "" else "%s: no actions" % broadcast.entrants[i]["id"]))
	lines.append("")
	lines.append("Recent actions:")
	for action in _recent_actions(shown):
		var color := RingView.ENTRANT_COLORS[int(action["entrant"]) % RingView.ENTRANT_COLORS.size()].to_html(false)
		lines.append("  t%d [color=#%s]%s/%s[/color] %s%s%s" % [
			int(action["t"]), color, action["actor"], action["process"], String(action["kind"]).to_upper(),
			" %d" % int(action["address"]) if int(action["address"]) >= 0 else "", _outcome_text(action),
		])
	if _at_recorded_end(tick):
		lines.append("")
		var reason := String(broadcast.result["termination_reason"])
		lines.append("Result: %s (%s, tick %d)" % [_winner_text(), REASONS.get(reason, reason), int(broadcast.result["ticks"])])
	return "\n".join(lines)


## The latest recorded actions at or before this frame, newest first.
func _recent_actions(shown: Dictionary) -> Array:
	var recent: Array = shown["actions"] + shown["senses"]
	recent.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["i"]) > int(b["i"]))
	return recent.slice(0, RECENT_ACTIONS)


func _at_recorded_end(tick: int) -> bool:
	return tick >= broadcast.max_tick and broadcast.is_tick_end(index)


func _winner_text() -> String:
	var winner := String(broadcast.result["winner"])
	if not broadcast.entrant_index.has(winner):
		return winner
	return "%s %s wins" % [winner, broadcast.entrants[int(broadcast.entrant_index[winner])]["name"]]


func _result_banner(tick: int) -> String:
	if not _at_recorded_end(tick):
		return ""
	var winner := String(broadcast.result["winner"])
	return _winner_text().to_upper() if broadcast.entrant_index.has(winner) else "RESULT: " + winner.to_upper()


func _agent_panel(state: Dictionary) -> String:
	var lines: PackedStringArray = ["[color=#8a8f98]%s[/color]" % AGENT_NOTE, "", "Own core location: cells %d-%d (ownership not shown)" % [
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
		var action: bool = event["status"] != null
		var text := "t%d %s %s" % [int(event["t"]), event["process"], String(event["kind"]).to_upper() if action else String(event["kind"])]
		if event["address"] != null:
			text += " %d" % int(event["address"])
		if action:
			text += " -> %s" % event["status"]
		if event["detail"] != "":
			text += (" (%s)" if action else ": %s") % event["detail"]
		lines.append("  " + text)
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
	_rendering_button = OptionButton.new()
	_rendering_button.add_item("Classic")
	_rendering_button.add_item("Filled Arcs")
	_rendering_button.select(1)
	_rendering_button.tooltip_text = "Memory rendering (same arena coordinates)"
	_rendering_button.item_selected.connect(func(i: int) -> void: set_rendering_mode(RingView.RENDER_MODES[i]))
	header.add_child(_rendering_button)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)
	_ring = RingView.new()
	_ring.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ring.size_flags_stretch_ratio = 2.0
	body.add_child(_ring)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(column)
	_side = RichTextLabel.new()
	_side.bbcode_enabled = true
	_side.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_side.add_theme_font_size_override("normal_font_size", 14)
	column.add_child(_side)
	_legend = LegendView.new()
	_legend.set_perspective("broadcast")
	column.add_child(_legend)

	_caption = Label.new()
	_caption.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_caption.clip_text = true
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
	_add_button(controls, "End", jump_to_end)
	_speed_button = OptionButton.new()
	for speed in SPEEDS:
		_speed_button.add_item("%d ticks/s" % int(speed))
	_speed_button.select(DEFAULT_SPEED)
	_speed_button.item_selected.connect(set_speed_index)
	controls.add_child(_speed_button)
	var jump_label := Label.new()
	jump_label.text = "  Tick"
	controls.add_child(jump_label)
	_jump = LineEdit.new()
	_jump.custom_minimum_size = Vector2(64, 0)
	_jump.placeholder_text = "G"
	_jump.text_submitted.connect(
		func(text: String) -> void:
			jump_to_tick(text)
			_jump.release_focus()
	)
	controls.add_child(_jump)
	_add_button(controls, "Go", func() -> void: jump_to_tick(_jump.text))
	_add_button(controls, "Help", func() -> void: _help.visible = not _help.visible)
	_controls.append_array([_perspective_button, _speed_button, _timeline])
	# Sound settings belong to the session, not the fixture, so they stay enabled.
	sound = SoundEffects.new()
	add_child(sound)
	_sound_toggle = CheckButton.new()
	_sound_toggle.text = "Sound"
	_sound_toggle.focus_mode = Control.FOCUS_NONE
	_sound_toggle.button_pressed = sound.is_enabled()
	_sound_toggle.toggled.connect(set_sound_enabled)
	controls.add_child(_sound_toggle)
	_volume = HSlider.new()
	_volume.min_value = 0
	_volume.max_value = 100
	_volume.step = 5
	_volume.value = round(sound.volume() * 100.0)
	_volume.custom_minimum_size = Vector2(90, 0)
	_volume.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_volume.focus_mode = Control.FOCUS_NONE  # Left/Right stay playback keys
	_volume.tooltip_text = "Sound effects volume"
	_volume.value_changed.connect(
		func(value: float) -> void:
			sound.set_volume(value / 100.0)
			_sound_settings_changed()
	)
	controls.add_child(_volume)

	_hint = Label.new()
	_hint.text = KEY_HINT
	_hint.add_theme_font_size_override("font_size", 12)
	_hint.add_theme_color_override("font_color", Color(0.7, 0.7, 0.74))
	root.add_child(_hint)
	_footer = Label.new()
	_footer.add_theme_font_size_override("font_size", 12)
	root.add_child(_footer)

	_help = PanelContainer.new()
	_help.visible = false
	var help_text := Label.new()
	help_text.text = HELP
	help_text.add_theme_font_size_override("font_size", 15)
	_help.add_child(help_text)
	add_child(_help)
	_help.resized.connect(func() -> void: _help.position = ((size - _help.size) / 2.0).floor())


func _add_button(parent: Control, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(callback)
	parent.add_child(button)
	_controls.append(button)
	return button
