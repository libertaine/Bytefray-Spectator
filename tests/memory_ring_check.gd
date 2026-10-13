extends SceneTree
## Rendering regression over recorded showcase frames, without executing agents.

const Ring := preload("res://scripts/ring_view.gd")
const TICKS := [12, 320, 461, 476, 477]
var main: Node
var checks := 0
var failures := PackedStringArray()
var started := false


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("FAIL: ", message)


func _initialize() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)


func _process(_delta: float) -> bool:
	if started:
		return false
	started = true
	check(main.load_error == "", "showcase verifies")
	if main.load_error == "":
		_geometry()
		_recorded_ownership()
		_seeks_and_isolation()
		_playback_and_sound()
	print("%d checks, %d failures" % [checks, failures.size()])
	print("MEMORY RING CHECK %s" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)
	return true


func _geometry() -> void:
	var ring := Ring.new()
	var center := Vector2(420, 300)
	var radius := 204.0
	var width := 20.4
	check(is_equal_approx(ring.memory_outer_radius(radius, width), radius + width / 2), "Classic and Filled Arcs share the outer circumference")
	check(is_equal_approx(ring.memory_outer_radius(radius, width) - ring.memory_inner_radius(radius, width), 40.0), "memory depth is 40 pixels inward")
	for cells in [8, 512, 1024]:
		ring.arena_size = cells
		var polygons: Array[PackedVector2Array] = []
		for cell in cells:
			polygons.append(ring.cell_polygon(center, radius, width, cell))
		for cell in cells:
			var polygon := polygons[cell]
			var mid: Vector2 = ring._at(center, ring.memory_outer_radius(radius, width) - 12.0, cell + 0.5)
			check(Geometry2D.is_point_in_polygon(mid, polygon), "%d: address %d belongs to its wedge" % [cells, cell])
			var neighbour: int = (cell + 1) % cells
			check(not Geometry2D.is_point_in_polygon(mid, polygons[neighbour]), "%d: address %d does not belong to neighbour %d" % [cells, cell, neighbour])
			var end := polygon.size() / 2 - 1
			check(polygon[end].is_equal_approx(polygons[neighbour][0]) and polygon[end + 1].is_equal_approx(polygons[neighbour][-1]), "%d: shared inner and outer edge %d -> %d" % [cells, cell, neighbour])
		check(polygons[0][0].is_equal_approx(center + Vector2(0, -ring.memory_outer_radius(radius, width))), "%d: address 0 starts at twelve o'clock" % cells)
	# Cache invalidation cannot retain geometry from another arena or resize.
	ring._prepare_geometry(center, radius, width)
	ring.arena_size = 512
	ring._prepare_geometry(center, radius, width)
	check(ring._wedge_geometry.size() == 512, "arena change rebuilds geometry")
	ring._prepare_geometry(center, radius + 10, width)
	check(is_equal_approx(ring._wedge_geometry[0][0].distance_to(center), ring.memory_outer_radius(radius + 10, width)), "resize rebuilds geometry")
	ring.free()


## Independent reference: fold raw owner_changes, and mark only actual WRITE
## changes. Compare every frame and every address, including tick 0 and wrap.
func _recorded_ownership() -> void:
	var model = main.broadcast
	var ring := Ring.new()
	var owners := PackedInt32Array()
	owners.resize(model.arena_size)
	var last_take := {}
	var took := 0
	var kept := 0
	var colors_ok := true
	var owners_ok := true
	var flashes_ok := true
	var before_write_ok := true
	for i in model.frame_count():
		var frame: Dictionary = model.frames[i]
		if i == 0:
			for cell in owners.size():
				owners[cell] = model.owner_code(frame["owners"][cell])
		else:
			for change in frame.get("owner_changes", []):
				var cell := int(change[0])
				var after: int = model.owner_code(change[1])
				if int(frame["p"]) == 1 and frame["kind"] == "write" and frame["status"] == "APPLIED" and owners[cell] != after:
					last_take[cell] = [int(frame["t"]), after]
					took += 1
				owners[cell] = after
		var reference := {}
		for cell in last_take:
			var take: Array = last_take[cell]
			var age := int(frame["t"]) - int(take[0])
			if age < 3 and owners[cell] == int(take[1]):
				reference[cell] = [1.0, 0.5, 0.25][age]
		var state: Dictionary = model.state(i)
		owners_ok = owners_ok and owners == state["owners"]
		ring.show_broadcast(state, model.entrants, model.arena_size, "", main.effects.at(i), main.effects.cores(i))
		flashes_ok = flashes_ok and ring.ownership_flashes() == reference
		var action: Dictionary = main.effects.action_at(i)
		if not action.is_empty() and action["kind"] == "write":
			if action["outcome"] == "kept":
				kept += 1
			if action["outcome"] == "took":
				# The new owner's flash must not appear before the recorded action.
				var previous: Dictionary = model.state(i - 1)
				before_write_ok = before_write_ok and previous["owners"][int(action["address"])] != owners[int(action["address"])]
		if int(frame["p"]) == 2 and TICKS.has(int(frame["t"])):
			for cell in owners.size():
				var code := owners[cell]
				var expected := Ring.FILLED_UNOWNED if code < 0 else Ring.ENTRANT_COLORS[code % Ring.ENTRANT_COLORS.size()].darkened(0.35).lightened(0.55 * float(reference.get(cell, 0.0)))
				colors_ok = colors_ok and ring.memory_color(cell, reference).is_equal_approx(expected)
	check(owners_ok, "raw ownership fold matches reconstructed owners at every showcase frame")
	check(flashes_ok and took > 0 and kept > 0, "flashes match only raw WRITE ownership changes, every frame (%d takes, %d kept)" % [took, kept])
	check(before_write_ok, "new ownership is absent before its recorded WRITE")
	check(colors_ok, "all 512 address colours match recorded state at all five requested ticks")
	ring.free()


func _seeks_and_isolation() -> void:
	var snapshots := {}
	for mode in Ring.RENDER_MODES:
		main.set_rendering_mode(mode)
		main.set_perspective("broadcast")
		for tick in TICKS:
			main.seek_tick(tick)
			var ring: Control = main._ring
			var record := [ring.state.duplicate(true), ring.ownership_flashes(), ring.cores.duplicate(true)]
			if mode == "classic":
				snapshots[tick] = record
			else:
				check(record == snapshots[tick], "both modes use identical recorded state at tick %d" % tick)
			for e in main.broadcast.entrants.size():
				var core: Array = main.broadcast.entrants[e]["core"]
				var held := 0
				for cell in core:
					held += 1 if ring.state["owners"][int(cell)] == e else 0
				check(held == int(ring.cores[e]["held"]), "%s tick %d: recorded core addresses and gauge agree" % [mode, tick])
		for tick in [477, 12, 476, 320, 461, 0, 461]:
			main.seek_tick(tick)
			if tick != 0:
				check([main._ring.state, main._ring.ownership_flashes(), main._ring.cores] == snapshots[tick], "%s: arbitrary seek reconstructs tick %d" % [mode, tick])
		main.set_perspective("agent_a")
		for tick in TICKS:
			main.seek_tick(tick)
			var ring: Control = main._ring
			check(not ring.state.has("owners") and ring.effects.is_empty() and ring.cores.is_empty() and ring.entrants.is_empty() and ring.banner.is_empty() and ring.ownership_flashes().is_empty(), "%s tick %d: switching to Agent A drops all broadcast ownership and effects" % [mode, tick])
			var unknown := true
			for cell in ring.arena_size:
				unknown = unknown and ring.memory_color(cell, {cell: 1.0}) == Ring.UNKNOWN
			check(unknown, "%s tick %d: every Agent A cell remains unknown, even with hostile flash input" % [mode, tick])
		# A replay history ending in Broadcast cannot affect Agent A rendering.
		var own: Dictionary = main._ring.state.duplicate(true)
		main.set_perspective("broadcast")
		main.seek_tick(12)
		main.set_perspective("agent_a")
		main.seek_tick(477)
		check(main._ring.state == own and main._ring.ownership_flashes().is_empty(), "%s: Agent A rendering is independent of broadcast navigation history" % mode)
	check(main.launch_options(PackedStringArray(["--rendering=classic"]))["rendering"] == "classic", "Classic launch option")
	check(main.launch_options(PackedStringArray(["--rendering=filled_arcs"]))["rendering"] == "filled_arcs", "Filled Arcs launch option")


func _playback_and_sound() -> void:
	for perspective in ["broadcast", "agent_a"]:
		var reference: Array = []
		for mode in Ring.RENDER_MODES:
			main.set_playing(false)
			main.set_perspective(perspective)
			main.seek_tick(458)
			main.set_rendering_mode(mode)
			main.set_sound_enabled(true)
			main.ticks_per_second = 5.0
			main.set_playing(true)
			var frames: Array = []
			var heard := false
			for k in 90:
				main._process(1.0 / 60)
				var cues: Array = main.sound.take_played()
				heard = heard or not cues.is_empty()
				frames.append([main.index, main._caption.text, cues])
				if k == 30:
					var index: int = main.index
					var progress: float = main._play_progress
					var voices: int = main.sound.active_voices()
					main.set_rendering_mode("filled_arcs" if mode == "classic" else "classic")
					check(main.index == index and main.playing and main._play_progress == progress and main.sound.active_voices() == voices, "%s: changing rendering during playback preserves clock and audio" % perspective)
			if mode == "classic":
				reference = frames
			else:
				check(frames == reference and heard, "%s: deterministic playback, captions and started sounds agree across rendering modes" % perspective)
		main.set_playing(false)
