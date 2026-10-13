extends SceneTree
## Generic headless playback check for any verified presentation fixture.
##
## Run: godot --headless --path . --script res://tests/fixture_check.gd -- --fixture=<dir|showcase|dev> [--core-log=<file>]
## Exit code 0 = pass, 1 = failure (each failure is printed).
##
## Checks: the manifest and both files load and verify; every frame of both
## perspectives plays in tick order to the recorded end; the broadcast's final
## alive set, eliminations, core display and result text match the manifest's
## verified outcome; the Agent A perspective holds only agent state, never
## shows the result or the match length; perspective switches land on tick
## boundaries; playback runs at the chosen rate and stops at the end.
##
## P1 effects, on every frame, against references this script builds itself
## from the presentation files: the broadcast shows exactly the recorded
## actions of the last 3 ticks up to the current frame (never a later one),
## with their recorded fields and outcomes; every SENSE sample is pending until
## its recorded delivery and delivered from then on; tick-end disruptions are
## the recorded sets and agree with the WRITEs that hit an anchor; core gauges
## equal an independent count; no shown effect carries data from a later frame;
## the decisive capture is marked from the recorded elimination on.
## Agent A's own indicators equal a reference built from agent_a.json alone,
## and Agent A never holds broadcast effects. After random seeks, restarts,
## jumps, switches and playback, the drawn effects equal those of sequential
## stepping. Playback visits every frame of a tick in order.
## --core-log writes each tick end's gauge values for comparison with the replay.

const FixtureLoader := preload("res://scripts/fixture_loader.gd")
const LegendView := preload("res://scripts/legend_view.gd")
const AGENT_STATE_KEYS := [
	"mode", "tick", "callback", "phase", "core_base", "core_size", "processes",
	"contacts", "receipt", "latest_sample", "recent_events", "own_actions",
]
const WINDOW := 3  # effect ticks

var failures: PackedStringArray = []
var checks := 0
var _main: Node
var _frame := 0
var _fixture := ""
var _core_log := ""


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("FAIL: ", message)


## Records the first failure of a per-frame property; returns the new state.
func holds(ok: bool, condition: bool, first: Array, message: String) -> bool:
	if ok and not condition:
		first.append(message)
	return ok and condition


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--fixture="):
			_fixture = arg.trim_prefix("--fixture=")
		elif arg.begins_with("--core-log="):
			_core_log = arg.trim_prefix("--core-log=")
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	_fixture = _main.FIXTURES.get(_fixture, _fixture)  # same aliases as the viewer
	root.add_child(_main)  # main reads --fixture= itself in _ready


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 1:
		var started := Time.get_ticks_msec()
		_run(_main)
		print("fixture checks run in %d ms" % (Time.get_ticks_msec() - started))
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
	var reference := _broadcast_reference(main.broadcast)
	var broadcast_hashes: Dictionary = {}

	# Broadcast: every frame, in tick order, to the recorded end.
	main.restart()
	var last_tick := 0
	var monotonic := true
	var alive_counts: Dictionary = {}
	var banner_early := false
	var styles_ok := true
	var effects_first: Array = []
	var effects_ok := _check_broadcast_frame(main, reference, 0, effects_first)
	broadcast_hashes[0] = _effects_hash(ring)
	for i in range(1, main.frame_count()):
		main.step_frame(1)
		monotonic = monotonic and main.current_tick() >= last_tick
		last_tick = main.current_tick()
		alive_counts[(ring.state["alive"] as Array).size()] = true
		banner_early = banner_early or (ring.banner != "" and i < main.frame_count() - 1)
		for anchor in ring.state["anchors"]:
			var eliminated: bool = not (ring.state["alive"] as Array).has(anchor[0])
			styles_ok = styles_ok and (ring.marker_style(anchor) == "eliminated") == eliminated
		effects_ok = _check_broadcast_frame(main, reference, i, effects_first) and effects_ok
		broadcast_hashes[i] = _effects_hash(ring)
	check(monotonic, "broadcast ticks are monotonic")
	check(main.current_tick() == ticks, "broadcast ends at tick %d" % ticks)
	check(styles_ok, "process markers are styled eliminated exactly when their entrant is not alive")
	check(not banner_early and ring.banner != "", "the result banner appears only at the recorded end")
	check(effects_ok, "every broadcast frame shows exactly the recorded effects: %s" % [effects_first])
	_check_sense_pairing(main, reference)
	_check_disruption_hits(main, reference)
	_check_decisive(main, reference, match_info)
	if _core_log != "":
		_write_core_log(main, reference)
	var alive: Array = ring.state["alive"]
	if String(match_info["termination_reason"]) == "last_agent_standing":
		check(alive == [winner], "only the winner is alive at the end (%s)" % [alive])
		check(main._side.text.contains("eliminated"), "the loser is shown eliminated")
		var loser := 1 - int(main.broadcast.entrant_index[winner])
		var loser_id := String(main.broadcast.entrants[loser]["id"])
		check(main.broadcast.core_cells_owned(main.index, loser) == 0, "the loser's core shows 0/8 at the end")
		check(main._caption.text.contains("%s %s eliminated (core 0/8)" % [loser_id, main.broadcast.entrants[loser]["name"]]), "the final caption names the eliminated entrant: %s" % main._caption.text)
		var loser_markers: Array = (ring.state["anchors"] as Array).filter(func(a: Array) -> bool: return a[0] == loser_id)
		check(not loser_markers.is_empty() and loser_markers.all(func(a: Array) -> bool: return ring.marker_style(a) == "eliminated"), "the loser's process markers are drawn eliminated")
		var winner_name := String(main.broadcast.entrants[int(main.broadcast.entrant_index[winner])]["name"])
		check(ring.banner == ("%s %s wins" % [winner, winner_name]).to_upper(), "the banner names the winner: %s" % ring.banner)
		check(ring.cores[loser]["level"] == "eliminated" and ring.cores[loser]["held"] == 0, "the loser's core gauge shows 0/8 eliminated at the end")
	check(main._side.text.contains("Result: %s" % winner), "broadcast shows the verified result")
	check(int(main._timeline.max_value) == ticks, "broadcast timeline spans the recorded match")
	for i in range(main.frame_count() - 1):
		main.step_frame(-1)
	check(main.index == 0 and not main._side.text.contains("Result:"), "no result is shown before the end")

	# Agent A: every frame; only agent state; no result and no match length.
	main.set_perspective("agent_a")
	main.restart()
	var agent_reference := _agent_reference(main.agent)
	var agent_hashes: Dictionary = {}
	var keys_ok := true
	var label_ok := true
	var hidden_ok := true
	var own_first: Array = []
	var own_ok := true
	for i in range(main.frame_count()):
		if i:
			main.step_frame(1)
		keys_ok = keys_ok and ring.mode == "agent" and ring.entrants.is_empty() and ring.effects.is_empty() and ring.cores.is_empty()
		for key in ring.state:
			keys_ok = keys_ok and AGENT_STATE_KEYS.has(key)
		var label: String = main._position_label.text
		label_ok = label_ok and label.contains("(limit %d)" % main.tick_limit) and not label.contains("/")
		label_ok = label_ok and int(main._timeline.max_value) == main.tick_limit
		hidden_ok = hidden_ok and not main._side.text.contains("Result") and not main._side.text.contains("eliminated")
		hidden_ok = hidden_ok and ring.banner == "" and not main._caption.text.contains("eliminated")
		hidden_ok = hidden_ok and main._side.text.begins_with("[color=#8a8f98]%s" % main.AGENT_NOTE)
		hidden_ok = hidden_ok and main._legend.text() == _legend_text(LegendView.AGENT)
		own_ok = _check_agent_frame(main, agent_reference, i, own_first) and own_ok
		agent_hashes[i] = JSON.stringify(ring.state).md5_text()
	check(keys_ok, "agent perspective holds no broadcast state or effects")
	check(label_ok, "agent perspective shows only the public tick limit")
	check(hidden_ok, "agent perspective never shows the result or eliminations, and its legend is static")
	check(own_ok, "Agent A's own indicators equal its own record on every frame: %s" % [own_first])
	check(main.current_tick() == ticks, "agent perspective ends at the recorded end")

	# Switching lands on tick boundaries in both directions.
	var middle := ticks / 2
	main.seek_tick(middle)
	main.set_perspective("broadcast")
	check(main.current_tick() == middle and main.current_model().is_tick_end(main.index), "agent -> broadcast on a boundary")
	main.step_frame(3)
	main.set_perspective("agent_a")
	check(main.current_tick() == middle and main.current_model().is_tick_end(main.index), "mid-tick switch lands on the last boundary")

	_check_navigation(main, broadcast_hashes, agent_hashes)
	_check_switch_while_playing(main)
	_check_playback_order(main, mini(10, ticks - 1))

	# Playback at a fixed rate, stopping at the end, in both perspectives.
	for perspective in ["broadcast", "agent_a"]:
		main.set_perspective(perspective)
		main.seek_tick(0)
		main.ticks_per_second = 20.0
		main.set_playing(true)
		# Playing from tick 0 starts with the announcer, which holds the match clock.
		var held := true
		while main.intro_left() > 0.0:
			main._process(0.1)
			held = held and main.current_tick() == 0
		check(held, "%s: the opening sequence holds tick 0" % perspective)
		for i in 10:
			main._process(0.1)
		check(main.current_tick() == 20, "%s plays 20 ticks in 1 s at 20 ticks/s (got %d)" % [perspective, main.current_tick()])
		main.seek_tick(ticks - 1)
		for i in 10:
			main._process(0.1)
		check(not main.playing and main.current_tick() == ticks, "%s playback stops at the end" % perspective)


static func _legend_text(rows: Array) -> String:
	return "\n".join(rows.map(func(row: Array) -> String: return row[1]))


static func _key(frame: Dictionary) -> String:
	return "%s/%s" % [frame["actor"], frame["process"]]


static func _anchor_of(frame: Dictionary, entrant: Variant, process: Variant) -> int:
	for anchor in frame["anchors"]:
		if anchor[0] == entrant and anchor[1] == process:
			return int(anchor[2])
	return -1


## Independent reference from broadcast.json: tick ranges, previous owners of
## WRITE targets, SENSE deliveries and core counts at every frame.
func _broadcast_reference(model) -> Dictionary:
	var frames: Array = model.frames
	var arena: int = model.arena_size
	var owners: Array = []
	owners.resize(arena)
	var tick_start: Dictionary = {}
	var tick_end: Dictionary = {}
	var previous_owner: Dictionary = {}  # write frame -> owner of its target before it
	var deliveries: Dictionary = {}  # SENSE frame -> delivery frame
	var open: Dictionary = {}
	var unpaired: Array = []
	var held: Array = []  # per frame: Array of core cells held per entrant
	var core_of: Dictionary = {}
	for e in model.entrants.size():
		for cell in model.entrants[e]["core"]:
			core_of[int(cell)] = e
	for j in frames.size():
		var frame: Dictionary = frames[j]
		var t := int(frame["t"])
		if not tick_start.has(t):
			tick_start[t] = j
		if int(frame["p"]) == 1 and frame["kind"] == "write" and frame["address"] != null:
			previous_owner[j] = owners[int(frame["address"])]
		if j == 0:
			for cell in arena:
				owners[cell] = frame["owners"][cell]
		else:
			for change in frame["owner_changes"]:
				owners[int(change[0])] = change[1]
		var counts: Array = []
		for e in model.entrants.size():
			var count := 0
			for cell in model.entrants[e]["core"]:
				if owners[int(cell)] == model.entrants[e]["id"]:
					count += 1
			counts.append(count)
		held.append(counts)
		match int(frame["p"]):
			0:
				if frame["sensed"] != null:
					if open.has(_key(frame)) and frames[open[_key(frame)]]["sensed"] == frame["sensed"]:
						deliveries[open[_key(frame)]] = j
						open.erase(_key(frame))
					else:
						unpaired.append(j)
			1:
				if frame["kind"] == "sense" and frame["status"] == "APPLIED":
					open[_key(frame)] = j
			2:
				tick_end[t] = j
	var span := 0
	var eliminated_by := frames.size()
	for j in frames.size():
		if int(frames[j]["p"]) == 1 and frames[j]["kind"] == "sense" and frames[j]["status"] == "APPLIED":
			span = maxi(span, int(deliveries.get(j, frames.size())) - j)
		if j > 0 and (frames[j]["alive"] as Array).size() < (frames[j - 1]["alive"] as Array).size():
			eliminated_by = mini(eliminated_by, j)
	return {
		"frames": frames, "tick_start": tick_start, "tick_end": tick_end, "previous_owner": previous_owner,
		"deliveries": deliveries, "unpaired": unpaired, "held": held, "core_of": core_of, "span": span,
		"eliminated_by": eliminated_by,
	}


func _window_start(reference: Dictionary, tick: int) -> int:
	return int(reference["tick_start"][maxi(0, tick - WINDOW + 1)])


func _check_broadcast_frame(main: Node, reference: Dictionary, i: int, first: Array) -> bool:
	var ring: Control = main._ring
	var frames: Array = reference["frames"]
	var tick := int(frames[i]["t"])
	var ok := holds(true, ring.mode == "broadcast" and not ring.effects.is_empty(), first, "frame %d: broadcast effects present" % i)
	# Actions: every recorded action of the window up to i, and nothing else.
	var expected: Array = []
	for j in range(_window_start(reference, tick), i + 1):
		var f: Dictionary = frames[j]
		if int(f["p"]) == 1 and f["kind"] != null and not (f["kind"] == "sense" and f["status"] == "APPLIED"):
			expected.append(j)
	var shown: Array = (ring.effects["actions"] as Array).map(func(a: Dictionary) -> int: return int(a["i"]))
	ok = holds(ok, shown == expected, first, "frame %d: actions %s, expected %s" % [i, shown, expected])
	for action in ring.effects["actions"]:
		ok = holds(ok, int(action["age"]) == tick - int(frames[int(action["i"])]["t"]) and bool(action["current"]) == (int(action["i"]) == i), first, "frame %d: action age/current" % i)
	var current: Dictionary = main.effects.action_at(i)
	if int(frames[i]["p"]) == 1 and frames[i]["kind"] != null:
		ok = holds(ok, _action_matches(current, i, reference, main.broadcast), first, "frame %d: action fields differ from the record: %s" % [i, current])
		ok = holds(ok, main._caption.text.begins_with(main.broadcast.caption(i)), first, "frame %d: caption starts with the recorded fact" % i)
	else:
		ok = holds(ok, current.is_empty(), first, "frame %d: no action outside ACTION frames" % i)
	# SENSE samples: pending until the recorded delivery, then delivered for the window.
	# Any SENSE delivered in the window or still pending is at most `span` frames
	# before the window start; every 97th frame the whole record is scanned instead.
	var scan_from := 0 if i % 97 == 0 else maxi(0, _window_start(reference, tick) - int(reference["span"]))
	var expected_senses: Array = []
	for j in range(scan_from, i + 1):
		var f: Dictionary = frames[j]
		if int(f["p"]) != 1 or f["kind"] != "sense" or f["status"] != "APPLIED":
			continue
		var d := int(reference["deliveries"].get(j, -1))
		if d < 0 or d > i:
			expected_senses.append([j, "pending"])
		elif int(frames[d]["t"]) > tick - WINDOW:
			expected_senses.append([j, "delivered"])
	var senses: Array = (ring.effects["senses"] as Array).map(func(s: Dictionary) -> Array: return [int(s["i"]), s["state"]])
	ok = holds(ok, senses == expected_senses, first, "frame %d: senses %s, expected %s" % [i, senses, expected_senses])
	# Nothing shown carries a later frame: no delivery data while pending, no
	# decisive mark before the recorded elimination.
	for sense in ring.effects["senses"]:
		ok = holds(ok, sense["state"] == "delivered" or (int(sense["delivered"]) == -1 and int(sense["receiver"]) == -1), first, "frame %d: a pending sample carries its future delivery" % i)
	for action in ring.effects["actions"]:
		ok = holds(ok, not action.has("decisive_from") and (not action["decisive"] or int(reference["eliminated_by"]) <= i), first, "frame %d: decisive shown before the recorded elimination" % i)
	for sense in ring.effects["senses"]:
		var f: Dictionary = frames[int(sense["i"])]
		var good: bool = sense["actor"] == f["actor"] and sense["process"] == f["process"] and int(sense["address"]) == int(f["address"]) and sense["sensed"] == f["sensed"]
		good = good and int(sense["half_width"]) == main.effects.half_width
		if sense["state"] == "delivered":
			var d := int(reference["deliveries"][int(sense["i"])])
			good = good and int(sense["receiver"]) == _anchor_of(frames[d], f["actor"], f["process"])
		ok = holds(ok, good, first, "frame %d: sense fields differ from the record: %s" % [i, sense])
		for anchor in f["sensed"]:
			var distance := absi(int(anchor) - int(f["address"]))
			distance = mini(distance, main.broadcast.arena_size - distance)
			ok = holds(ok, main.effects.half_width < 0 or distance <= main.effects.half_width, first, "frame %d: sensed anchor %d outside the drawn window" % [i, int(anchor)])
	# Tick-end disruptions: the recorded sets of the window, up to i.
	var expected_hits: Array = []
	for t in range(maxi(0, tick - WINDOW + 1), tick + 1):
		var k := int(reference["tick_end"].get(t, -1))
		if k >= 0 and k <= i:
			for pair in frames[k]["disrupted"]:
				expected_hits.append([pair[0], pair[1], _anchor_of(frames[k], pair[0], pair[1]), tick - t])
	var hits: Array = (ring.effects["disruptions"] as Array).map(func(h: Dictionary) -> Array: return [h["actor"], h["process"], int(h["anchor"]), int(h["age"])])
	ok = holds(ok, hits == expected_hits, first, "frame %d: disruptions %s, expected %s" % [i, hits, expected_hits])
	# Core gauges: an independent count, the change since the last tick end, the level.
	var held: Array = reference["held"][i]
	var base: Array = reference["held"][int(reference["tick_end"][tick - 1])] if tick > 0 else held
	var alive: Array = frames[i]["alive"]
	for e in ring.cores.size():
		var status: Dictionary = ring.cores[e]
		var id: String = main.broadcast.entrants[e]["id"]
		var level := "eliminated" if not alive.has(id) else ("critical" if held[e] <= 2 else ("low" if held[e] <= 4 else "ok"))
		ok = holds(ok, int(status["held"]) == held[e] and int(status["delta"]) == held[e] - base[e] and status["level"] == level, first, "frame %d: core gauge %s %s, expected held %d delta %d %s" % [i, id, status, held[e], held[e] - base[e], level])
	return ok


func _action_matches(action: Dictionary, i: int, reference: Dictionary, model) -> bool:
	var frames: Array = reference["frames"]
	var f: Dictionary = frames[i]
	if action.is_empty() or int(action["i"]) != i:
		return false
	var ok: bool = action["kind"] == f["kind"] and action["actor"] == f["actor"] and action["process"] == f["process"] and action["status"] == f["status"]
	ok = ok and int(action["address"]) == (-1 if f["address"] == null else int(f["address"]))
	var applied: bool = f["status"] == "APPLIED"
	ok = ok and (action["outcome"] == "refused") == (not applied)
	match String(f["kind"]):
		"move":
			if applied:
				var from := _anchor_of(frames[i - 1], f["actor"], f["process"])
				var to := _anchor_of(f, f["actor"], f["process"])
				ok = ok and int(action["from"]) == from and posmod(from + int(action["delta"]), model.arena_size) == to
				ok = ok and (int(action["delta"]) == 0 or signi(int(action["delta"])) == signi(int(f["operand"])))
		"write":
			if applied:
				var address := int(f["address"])
				var before: Variant = reference["previous_owner"][i]
				var changed: bool = (f["owner_changes"] as Array).any(func(c: Array) -> bool: return int(c[0]) == address)
				ok = ok and action["outcome"] == ("took" if changed else "kept")
				var core := int(reference["core_of"].get(address, -1))
				var core_id: Variant = null if core < 0 else model.entrants[core]["id"]
				var change := ""
				if core >= 0 and before == core_id and f["actor"] != core_id:
					change = "damage"
				elif core >= 0 and f["actor"] == core_id and before != core_id:
					change = "recovery"
				ok = ok and action["core_change"] == change
				var hits: Array = []
				for anchor in f["anchors"]:
					if anchor[0] != f["actor"] and int(anchor[2]) == address and (f["alive"] as Array).has(anchor[0]):
						hits.append([anchor[0], anchor[1]])
				ok = ok and action["hits"] == hits
		"sense":
			if applied:
				ok = ok and action["sensed"] == f["sensed"]
	return ok


func _check_sense_pairing(main: Node, reference: Dictionary) -> void:
	check((reference["unpaired"] as Array).is_empty(), "every recorded delivery follows a recorded SENSE with the same sample: unpaired %s" % [reference["unpaired"]])
	var paired := true
	for j in reference["deliveries"]:
		var d := int(reference["deliveries"][j])
		paired = paired and main.effects.delivery_at(d).get("i", -1) == j and d > j
	check(paired, "the viewer pairs each delivery with its recorded SENSE, always after it (%d deliveries)" % reference["deliveries"].size())


## The WRITEs the viewer marks as hitting an anchor are exactly the recorded
## tick-end disruption set of each tick.
func _check_disruption_hits(main: Node, reference: Dictionary) -> void:
	var by_tick: Dictionary = {}
	for action in main.effects.actions:
		for hit in action["hits"]:
			var hits: Dictionary = by_tick.get(int(action["t"]), {})
			hits["%s/%s" % [hit[0], hit[1]]] = true
			by_tick[int(action["t"])] = hits
	var ok := true
	for t in reference["tick_end"]:
		var recorded: Array = (reference["frames"][int(reference["tick_end"][t])]["disrupted"] as Array).map(func(p: Array) -> String: return "%s/%s" % [p[0], p[1]])
		recorded.sort()
		var marked: Array = by_tick.get(t, {}).keys()
		marked.sort()
		ok = ok and recorded == marked
	check(ok, "WRITE hits on anchors equal the recorded tick-end disruption sets")


func _check_decisive(main: Node, reference: Dictionary, match_info: Dictionary) -> void:
	var decisive: Array = main.effects.actions.filter(func(a: Dictionary) -> bool: return int(a["decisive_from"]) >= 0)
	if String(match_info["termination_reason"]) != "last_agent_standing":
		check(decisive.is_empty(), "no decisive capture without an elimination")
		return
	check(decisive.size() == 1, "exactly one decisive capture (%d)" % decisive.size())
	if decisive.size() != 1:
		return
	var action: Dictionary = decisive[0]
	var winner := String(match_info["winner"])
	var loser := 1 - int(main.broadcast.entrant_index[winner])
	var last: int = main.broadcast.frame_count() - 1
	var i := int(action["i"])
	check(action["actor"] == winner and int(action["core_owner"]) == loser and action["core_change"] == "damage", "the decisive capture is the winner's WRITE on the loser's core")
	check(int(reference["held"][i][loser]) == 0 and i < last, "the loser's core is 0/8 after the decisive WRITE, before the final frame")
	check(int(action["decisive_from"]) == int(reference["eliminated_by"]) and int(reference["eliminated_by"]) == last, "it is marked decisive from the recorded elimination frame")
	main.seek_tick(int(match_info["ticks"]))
	main.step_frame(-(last - i))
	var at_write: Array = (main._ring.effects["actions"] as Array).filter(func(a: Dictionary) -> bool: return int(a["i"]) == i)
	check(main.index == i and main._ring.banner == "" and main._caption.text.contains("core cell lost") and not main._caption.text.contains("DECISIVE"), "at the WRITE, before the elimination is recorded, it is shown as a core cell lost, not yet decisive: %s" % main._caption.text)
	check(at_write.size() == 1 and not at_write[0]["decisive"] and int(main._ring.cores[loser]["held"]) == 0, "at the WRITE the loser's gauge already reads 0/8")
	main.seek_tick(int(match_info["ticks"]))
	var shown: Array = (main._ring.effects["actions"] as Array).filter(func(a: Dictionary) -> bool: return a["decisive"])
	check(main._ring.banner != "" and shown.size() == 1 and int(shown[0]["i"]) == i, "the decisive capture is drawn alongside the result banner")
	check(main._caption.text.contains("decisive capture: %s/%s WRITE %d" % [action["actor"], action["process"], int(action["address"])]), "the elimination caption names the decisive capture: %s" % main._caption.text)


func _write_core_log(main: Node, reference: Dictionary) -> void:
	var lines := PackedStringArray()
	for t in range(0, main.broadcast.max_tick + 1):
		main.seek_tick(t)
		var parts := PackedStringArray([str(t)])
		for status in main._ring.cores:
			parts.append("%s:%d:%s" % [status["id"], int(status["held"]), status["level"]])
		lines.append(",".join(parts))
	var file := FileAccess.open(_core_log, FileAccess.WRITE)
	file.store_string("\n".join(lines) + "\n")
	file.close()


## Independent reference from agent_a.json alone: own MOVE/WRITE/SENSE events
## and the frame that delivers each SENSE's sample.
func _agent_reference(model) -> Dictionary:
	var frames: Array = model.frames
	var tick_start: Dictionary = {}
	var events: Array = []
	var event_frames := PackedInt32Array()
	var delivered_at: Dictionary = {}
	for j in frames.size():
		var t := int(frames[j]["t"])
		if not tick_start.has(t):
			tick_start[t] = j
		for sample in frames[j]["samples"]:
			delivered_at["%d/%d/%s" % [int(sample["sampled"][0]), int(sample["sampled"][1]), sample["sampled"][2]]] = j
		for event in frames[j]["events"]:
			if ["move", "write", "sense"].has(event["kind"]):
				events.append([j, event])
				event_frames.append(j)
	var span := 0
	for entry in events:
		var frame: Dictionary = frames[int(entry[0])]
		if entry[1]["kind"] == "sense":
			var d := int(delivered_at.get("%d/%d/%s" % [int(frame["t"]), int(frame["cb"]), entry[1]["process"]], frames.size()))
			span = maxi(span, d - int(entry[0]))
	return {"frames": frames, "tick_start": tick_start, "events": events, "event_frames": event_frames, "delivered_at": delivered_at, "span": span}


func _check_agent_frame(main: Node, reference: Dictionary, i: int, first: Array) -> bool:
	var frames: Array = reference["frames"]
	var tick := int(frames[i]["t"])
	var since := int(reference["tick_start"][maxi(0, tick - WINDOW + 1)])
	var writes: Array = []
	var moves: Array = []
	var pending: Array = []
	var events: Array = reference["events"]
	for k in range((reference["event_frames"] as PackedInt32Array).bsearch(mini(since, i - int(reference["span"]))), events.size()):
		var entry: Array = events[k]
		var j := int(entry[0])
		if j > i:
			break
		var event: Dictionary = entry[1]
		var frame: Dictionary = frames[j]
		if event["kind"] == "sense":
			var d := int(reference["delivered_at"].get("%d/%d/%s" % [int(frame["t"]), int(frame["cb"]), event["process"]], -1))
			if event["status"] == "APPLIED" and (d < 0 or d > i):
				pending.append([event["process"], int(event["address"])])
		elif j >= since and event["kind"] == "write":
			writes.append([event["process"], int(event["address"]), event["status"], tick - int(frame["t"])])
		elif j >= since and event["kind"] == "move" and event["status"] == "APPLIED":
			var from := -1
			var to := -1
			for p in frames[j - 1]["processes"]:
				from = int(p[1]) if p[0] == event["process"] else from
			for p in frame["processes"]:
				to = int(p[1]) if p[0] == event["process"] else to
			moves.append([event["process"], from, to, tick - int(frame["t"])])
	var own: Dictionary = main._ring.state["own_actions"]
	var arena: int = main.agent.arena_size
	var shown_writes: Array = (own["writes"] as Array).map(func(w: Array) -> Array: return [w[0], int(w[2]), w[3], int(w[4])])
	var shown_moves: Array = (own["moves"] as Array).map(func(m: Array) -> Array: return [m[0], int(m[1]), posmod(int(m[1]) + int(m[2]), arena), int(m[3])])
	var shown_pending: Array = (own["pending_senses"] as Array).map(func(p: Array) -> Array: return [p[0], int(p[1])])
	var ok := holds(true, shown_writes == writes, first, "agent frame %d: writes %s, expected %s" % [i, shown_writes, writes])
	ok = holds(ok, shown_moves == moves, first, "agent frame %d: moves %s, expected %s" % [i, shown_moves, moves])
	return holds(ok, shown_pending == pending, first, "agent frame %d: pending %s, expected %s" % [i, shown_pending, pending])


static func _effects_hash(ring: Control) -> String:
	return JSON.stringify([ring.effects, ring.cores, ring.banner]).md5_text()


## Random seeks, restarts, jumps, steps, switches and playback: whatever is
## drawn afterwards must equal what sequential stepping drew at that index.
func _check_navigation(main: Node, broadcast_hashes: Dictionary, agent_hashes: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261012
	var ok := true
	var first: Array = []
	for n in 400:
		var op := rng.randi_range(0, 9)
		match op:
			0:
				main.seek_tick(rng.randi_range(0, main.tick_limit + 5))
			1:
				main.restart()
			2:
				main.step_frame(rng.randi_range(-60, 60))
			3:
				main.step_tick(1 if rng.randf() < 0.5 else -1)
			4:
				main.jump_to_end()
			5:
				main.jump_to_tick(str(rng.randi_range(0, main.tick_limit)))
			6:
				main.set_perspective("agent_a" if main.perspective == "broadcast" else "broadcast")
			7:
				main.ticks_per_second = main.SPEEDS[rng.randi_range(0, main.SPEEDS.size() - 1)]
				main.set_playing(true)
				for k in rng.randi_range(1, 12):
					main._process(1.0 / 30.0)
				main.set_playing(false)
			8:
				main._timeline.value = rng.randi_range(0, int(main._timeline.max_value))
			9:
				main.ticks_per_second = main.SPEEDS[rng.randi_range(0, 3)]
				main.set_playing(true)
				for k in rng.randi_range(1, 8):
					main._process(1.0 / 60.0)
				main.set_perspective("agent_a" if main.perspective == "broadcast" else "broadcast")
				for k in rng.randi_range(0, 8):
					main._process(1.0 / 60.0)
				main.set_playing(false)
		var ring: Control = main._ring
		if main.perspective == "broadcast":
			ok = holds(ok, _effects_hash(ring) == broadcast_hashes[main.index], first, "op %d (%d): broadcast effects at %d differ from sequential stepping" % [n, op, main.index])
		else:
			ok = holds(ok, ring.effects.is_empty() and ring.cores.is_empty() and JSON.stringify(ring.state).md5_text() == agent_hashes[main.index], first, "op %d (%d): agent view at %d differs from sequential stepping" % [n, op, main.index])
	check(ok, "after 400 random navigation operations nothing stale is drawn: %s" % [first])


## Switching perspective during playback resumes from the new perspective's
## boundary with no progress carried over from the other perspective's frames,
## from every mid-tick frame of the first ticks (where indexes of the two
## perspectives can coincide).
func _check_switch_while_playing(main: Node) -> void:
	for source in ["agent_a", "broadcast"]:
		var target: String = "broadcast" if source == "agent_a" else "agent_a"
		var ok := true
		var first: Array = []
		main.set_perspective(source)
		var model = main.current_model()
		for a in range(1, mini(400, model.frame_count())):
			if model.is_tick_end(a):
				continue
			main.set_playing(false)
			main.set_perspective(source)
			main.index = a
			main._refresh()
			main.ticks_per_second = 1.0
			main.set_playing(true)
			main._process(0.0)
			main.set_perspective(target)
			var boundary: int = main.index
			main._process(0.0001)
			ok = holds(ok, main.index == boundary, first, "%s index %d -> %s: resumed at %d, not the boundary %d" % [source, a, target, main.index, boundary])
		# At tick 0 the progress can be carried without moving the index, so check it directly.
		main.set_playing(false)
		main.set_perspective(source)
		main.restart()
		main.set_playing(true)
		main._process(0.02)
		main.set_perspective(target)
		main._process(0.0001)
		ok = holds(ok, main.index == 0 and absf(main._play_progress - 0.0001) < 1e-9, first, "%s tick 0 -> %s: progress %f carried over" % [source, target, main._play_progress])
		main.set_playing(false)
		check(ok, "switching %s -> %s during playback resumes at the boundary: %s" % [source, target, first])


## At a slow rate, playback visits every frame of a tick, in order, in both perspectives.
func _check_playback_order(main: Node, tick: int) -> void:
	for perspective in ["broadcast", "agent_a"]:
		main.set_perspective(perspective)
		main.seek_tick(tick)
		var model = main.current_model()
		var start: int = model.index_for_tick_end(tick)
		var end: int = model.index_for_tick_end(tick + 2)
		main.ticks_per_second = 1.0
		main.set_playing(true)
		var visited: Array = [main.index]
		var guard := 0
		while main.index < end and guard < 2 * 240 * 4:
			main._process(1.0 / 240.0)
			guard += 1
			if main.index != visited.back():
				visited.append(main.index)
		main.set_playing(false)
		check(visited == range(start, end + 1), "%s playback at 1 tick/s visits every frame of ticks %d-%d in order" % [perspective, tick + 1, tick + 2])
