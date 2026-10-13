extends Control
## Draws the circular arena: one ring segment per cell, cores, process markers,
## transient effects and (agent mode) delivered sensing knowledge.
##
## The view keeps broadcast data only while in broadcast mode. show_agent()
## drops it, so an agent perspective can only ever draw agent-visible state.
## In broadcast mode an eliminated entrant's process markers are drawn dimmed
## and crossed out, core gauges show each entrant's core integrity, and a
## banner (the verified result) can be shown at the end.
##
## Effects are drawn from what the models hand over for the current frame and
## nothing else: the view keeps no history, so a seek can never leave one behind.

const ENTRANT_COLORS: Array[Color] = [
	Color("#3fb6ff"), Color("#ff9f43"), Color("#c18bff"), Color("#5be37d"),
]
const UNOWNED := Color(0.20, 0.21, 0.25)
const FILLED_UNOWNED := Color("#191a1f")
const MEMORY_DEPTH := 40.0
const RENDER_MODES := ["classic", "filled_arcs"]
const BACKGROUND := Color(0.07, 0.07, 0.09)
const UNKNOWN := Color(0.14, 0.14, 0.17)
const SAMPLE_COLORS := {
	"POSITIVE": Color("#ffd166"),
	"EMPTY": Color("#7c8db5"),
	"REFUSED": Color("#ef476f"),
}
const DAMAGE := Color("#ff4040")
const RECOVERY := Color("#f2f2f2")
const CRITICAL := Color("#ff4040")
## Opacity of an effect by its age in ticks (0 = the current tick).
const AGE_ALPHA: Array[float] = [1.0, 0.5, 0.25]

var rendering_mode := "filled_arcs"
# Geometry only: never cache ownership, colours or broadcast effects here.
var _wedge_geometry: Array[PackedVector2Array] = []
var _geometry_key: Array = []

var mode := ""
var arena_size := 512
var state: Dictionary = {}
var entrants: Array = []  # broadcast mode only
var banner := ""  # broadcast mode only
var effects: Dictionary = {}  # broadcast mode only
var cores: Array = []  # broadcast mode only
var agent_color := ENTRANT_COLORS[0]
var sense_half_width := -1  # public ruleset constant


func show_broadcast(new_state: Dictionary, broadcast_entrants: Array, cells: int, result_banner: String = "", new_effects: Dictionary = {}, core_status: Array = []) -> void:
	mode = "broadcast"
	arena_size = cells
	entrants = broadcast_entrants
	banner = result_banner
	effects = new_effects
	cores = core_status
	state = new_state
	queue_redraw()


func show_agent(new_state: Dictionary, cells: int, half_width: int = -1) -> void:
	mode = "agent"
	arena_size = cells
	entrants = []
	banner = ""
	effects = {}
	cores = []
	sense_half_width = half_width
	state = new_state
	queue_redraw()


func clear() -> void:
	mode = ""
	entrants = []
	banner = ""
	effects = {}
	cores = []
	state = {}
	queue_redraw()


func set_rendering_mode(value: String) -> void:
	if RENDER_MODES.has(value):
		rendering_mode = value
		queue_redraw()


## Same outer edge as Classic's stroke; depth extends inward only. All existing
## core, process, sensing and action coordinates still use radius and width.
func memory_outer_radius(radius: float, width: float) -> float:
	return radius + width * 0.5


func memory_inner_radius(radius: float, width: float) -> float:
	return maxf(0.0, memory_outer_radius(radius, width) - MEMORY_DEPTH)


## Full address interval [cell, cell + 1], with shared edges and no gap.
## Subdivide for small arenas too, keeping each curve step at most one degree.
func cell_polygon(center: Vector2, radius: float, width: float, cell: int) -> PackedVector2Array:
	var outer := memory_outer_radius(radius, width)
	var inner := memory_inner_radius(radius, width)
	var steps := maxi(1, int(ceil(360.0 / arena_size)))
	var points := PackedVector2Array()
	for k in range(steps + 1):
		points.append(_at(center, outer, cell + float(k) / steps))
	for k in range(steps, -1, -1):
		points.append(_at(center, inner, cell + float(k) / steps))
	return points


func _prepare_geometry(center: Vector2, radius: float, width: float) -> void:
	var key := [center, radius, width, arena_size]
	if key == _geometry_key:
		return
	_geometry_key = key
	_wedge_geometry.clear()
	for cell in arena_size:
		_wedge_geometry.append(cell_polygon(center, radius, width, cell))


## Broadcast-only flashes; newest recorded take wins at an address. A flash
## brightens the CURRENT owner, never carries a prior owner's colour forward.
## The three tick ages match existing effects and reconstruct on every seek.
func ownership_flashes() -> Dictionary:
	var flashes := {}
	if mode != "broadcast":
		return flashes
	var owners: PackedInt32Array = state["owners"]
	for action in effects.get("actions", []):
		if action["kind"] != "write" or action["outcome"] != "took":
			continue
		var cell := int(action["address"])
		var age := int(action["age"])
		if cell >= 0 and cell < arena_size and age >= 0 and age < AGE_ALPHA.size() and owners[cell] == int(action["entrant"]):
			flashes[cell] = _alpha(age)
	return flashes


func memory_color(cell: int, flashes: Dictionary) -> Color:
	if mode != "broadcast":
		return UNKNOWN
	var code: int = state["owners"][cell]
	if code < 0:
		return FILLED_UNOWNED if rendering_mode == "filled_arcs" else UNOWNED
	var color := ENTRANT_COLORS[code % ENTRANT_COLORS.size()].darkened(0.35)
	return color.lightened(0.55 * float(flashes.get(cell, 0.0))) if rendering_mode == "filled_arcs" else color


func _draw_memory(center: Vector2, radius: float, width: float) -> void:
	var flashes := ownership_flashes() if rendering_mode == "filled_arcs" else {}
	if rendering_mode == "classic":
		for cell in arena_size:
			_cell_arc(center, radius, cell, memory_color(cell, flashes), width)
		return
	_prepare_geometry(center, radius, width)
	for cell in arena_size:
		draw_colored_polygon(_wedge_geometry[cell], memory_color(cell, flashes))
	var outer := memory_outer_radius(radius, width)
	var inner := memory_inner_radius(radius, width)
	# Fine notches at the outer edge suggest individual addresses without
	# cutting coloured ownership runs into 512 noisy radial stripes.
	var ticks := PackedVector2Array()
	for cell in arena_size:
		ticks.append(_at(center, outer - 3.0, cell))
		ticks.append(_at(center, outer, cell))
	draw_multiline(ticks, Color(0, 0, 0, 0.22), -1.0)
	draw_arc(center, outer, 0.0, TAU, maxi(128, arena_size), Color("#646873"), 1.0, true)
	draw_arc(center, inner, 0.0, TAU, maxi(128, arena_size), Color("#30333c"), 1.0, true)


## Contrasting backing only in Filled Arcs; never move an existing lane.
func _lane_backing(center: Vector2, lane: float, from_cell: float, to_cell: float, line_width: float) -> void:
	if rendering_mode == "filled_arcs":
		_span_arc(center, lane, from_cell, to_cell, Color(BACKGROUND, 0.9), line_width + 3.0)


func _write_line(center: Vector2, inner: float, source: float, target: float, color: Color, line_width: float) -> void:
	var start := _at(center, inner, source)
	var end := _at(center, inner, target)
	if rendering_mode == "filled_arcs":
		draw_line(start, end, Color(BACKGROUND, 0.8), line_width + 2.0)
	draw_line(start, end, color, line_width)


func _angle(cell: float) -> float:
	return -PI / 2.0 + TAU * cell / float(arena_size)


func _at(center: Vector2, radius: float, cell: float) -> Vector2:
	return center + Vector2.from_angle(_angle(cell)) * radius


func _cell_arc(center: Vector2, radius: float, cell: int, color: Color, width: float) -> void:
	draw_arc(center, radius, _angle(cell), _angle(cell + 0.92), 3, color, width)


func _span_arc(center: Vector2, radius: float, from_cell: float, to_cell: float, color: Color, width: float) -> void:
	var points := maxi(4, int(abs(to_cell - from_cell) / 2.0))
	draw_arc(center, radius, _angle(from_cell), _angle(to_cell), points, color, width)


func _dashed_arc(center: Vector2, radius: float, from_cell: float, to_cell: float, color: Color, width: float) -> void:
	var cell := from_cell
	while cell < to_cell:
		_span_arc(center, radius, cell, minf(cell + 3.0, to_cell), color, width)
		cell += 5.0


func _marker(center: Vector2, radius: float, cell: float, color: Color, filled: bool) -> void:
	var tip := _at(center, radius, cell + 0.5)
	var outward := Vector2.from_angle(_angle(cell + 0.5))
	var side := outward.orthogonal() * 7.0
	var base := tip + outward * 14.0
	var points := PackedVector2Array([tip, base + side, base - side])
	if filled:
		draw_colored_polygon(points, color)
	else:
		points.append(tip)
		draw_polyline(points, color, 2.0)


func _alpha(age: int) -> float:
	return AGE_ALPHA[clampi(age, 0, AGE_ALPHA.size() - 1)]


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BACKGROUND)
	if state.is_empty():
		return
	var center := size / 2.0
	var radius := minf(size.x, size.y) * 0.34
	var width := maxf(radius * 0.10, 6.0)
	if mode == "broadcast":
		_draw_broadcast(center, radius, width)
	elif mode == "agent":
		_draw_agent(center, radius, width)


func _draw_broadcast(center: Vector2, radius: float, width: float) -> void:
	var owners: PackedInt32Array = state["owners"]
	_draw_memory(center, radius, width)
	var alive: Array = state["alive"]
	for i in entrants.size():
		var color := ENTRANT_COLORS[i % ENTRANT_COLORS.size()]
		if not alive.has(entrants[i]["id"]):
			color = color.darkened(0.7)
		for cell in entrants[i]["core"]:
			var held: bool = owners[int(cell)] == i
			_cell_arc(center, radius + width * 0.95, int(cell), color if held else color.darkened(0.6), width * 0.45)
			if rendering_mode == "filled_arcs":
				_cell_arc(center, memory_inner_radius(radius, width) + 2.5, int(cell), color if held else color.darkened(0.6), 3.0)
	if not effects.is_empty():
		_draw_senses(center, radius, width)
		_draw_actions(center, radius, width)
	for anchor in state["anchors"]:
		var index := int(_entrant_index(String(anchor[0])))
		var color := ENTRANT_COLORS[index % ENTRANT_COLORS.size()]
		var style := marker_style(anchor)
		if style == "eliminated":
			color = color.darkened(0.7)
		_marker(center, radius + width * 1.6, float(anchor[2]), color, style == "active")
		if style == "eliminated":
			_cross(_at(center, radius + width * 1.6 + 7.0, float(anchor[2]) + 0.5), 8.0, Color(0.85, 0.85, 0.85))
	if not effects.is_empty():
		for hit in effects["disruptions"]:
			_burst(_at(center, radius + width * 1.6 + 7.0, float(hit["anchor"]) + 0.5), 15.0, Color(1, 1, 1, _alpha(int(hit["age"])) * 0.9))
	_draw_core_gauges()
	if not banner.is_empty():
		var font := ThemeDB.fallback_font
		var font_size := int(clampf(radius * 0.11, 14.0, 30.0))
		var text_size := font.get_string_size(banner, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
		var origin := center + Vector2(-text_size.x / 2.0, font_size * 0.35)
		draw_string(font, origin, banner, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)


## Inner lane radius for an entrant's SENSE samples (one lane per entrant, so
## simultaneous or overlapping samples of both sides stay visible).
func sense_lane(radius: float, width: float, entrant: int) -> float:
	return radius - width * (1.35 + 0.7 * entrant)


func _draw_senses(center: Vector2, radius: float, width: float) -> void:
	for sense in effects["senses"]:
		var e := int(sense["entrant"])
		var lane := sense_lane(radius, width, e)
		var color := ENTRANT_COLORS[e % ENTRANT_COLORS.size()]
		var c := float(sense["address"])
		var h := float(sense["half_width"]) if int(sense["half_width"]) >= 0 else 0.5
		var delivered: bool = sense["state"] == "delivered"
		var alpha := _alpha(int(sense["age"]))
		_lane_backing(center, lane, c - h, c + h + 1.0, width * 0.4)
		if delivered:
			_span_arc(center, lane, c - h, c + h + 1.0, Color(color, 0.55 * alpha), width * 0.4)
		else:
			_dashed_arc(center, lane, c - h, c + h + 1.0, Color(color, 0.9), width * 0.4)
		for anchor in sense["sensed"]:
			var at := _at(center, lane, float(anchor) + 0.5)
			if delivered:
				draw_circle(at, 4.0, Color(Color.WHITE, alpha))
			else:
				draw_arc(at, 4.0, 0.0, TAU, 12, Color.WHITE, 1.5)
		if bool(sense["current"]) or (delivered and int(sense["age"]) == 0):
			var start := _at(center, lane, c + 0.5)
			if delivered:
				# The recorded delivery: the sample reaches the process that took it.
				draw_line(start, _at(center, radius + width * 1.6, float(sense["receiver"]) + 0.5), Color(color, 0.8 * alpha), 1.5)
			else:
				draw_line(_at(center, radius - width * 0.55, float(sense["source"]) + 0.5), start, Color(color, 0.6), 1.0)


func _draw_actions(center: Vector2, radius: float, width: float) -> void:
	var decisive: Dictionary = {}
	for action in effects["actions"]:
		var e := int(action["entrant"])
		if e < 0:
			continue
		var color := ENTRANT_COLORS[e % ENTRANT_COLORS.size()]
		var alpha := _alpha(int(action["age"]))
		var current: bool = action["current"]
		var kind := String(action["kind"])
		if action["outcome"] == "refused":
			var cell := float(action["address"]) if int(action["address"]) >= 0 else float(action["source"])
			_cross(_at(center, radius, cell + 0.5), 5.0, Color(color, alpha))
			continue
		if kind == "write":
			var target := float(action["address"]) + 0.5
			if int(action["age"]) == 0:
				var inner := radius - width * 0.55
				_write_line(center, inner, float(action["source"]) + 0.5, target, Color(color, 0.9 if current else 0.22), 2.0 if current else 1.0)
			var at := _at(center, radius, target)
			if action["outcome"] == "took":
				draw_circle(at, width * 0.24, Color(color.lightened(0.35), alpha))
			else:
				draw_arc(at, width * 0.24, 0.0, TAU, 12, Color(color.lightened(0.35), alpha), 1.5)
			if action["core_change"] != "":
				var ring := _at(center, radius + width * 0.95, target)
				var mark := DAMAGE if action["core_change"] == "damage" else RECOVERY
				draw_arc(ring, width * 0.5, 0.0, TAU, 16, Color(mark, alpha), 2.5)
			if action["decisive"]:
				decisive = action
		elif kind == "move":
			_move_arc(center, radius + width * 2.45, float(action["from"]), float(action["delta"]), Color(color, alpha), 3.0 if current else 2.0)
	if not decisive.is_empty():
		var cell := float(decisive["address"]) + 0.5
		draw_arc(_at(center, radius + width * 0.95, cell), width * 1.1, 0.0, TAU, 24, DAMAGE, 3.0)
		var font := ThemeDB.fallback_font
		var at := _at(center, radius + width * 3.4, cell)
		var text := "CORE CAPTURED"
		var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
		draw_string(font, at - Vector2(text_size.x / 2.0, -6.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, DAMAGE)


func _move_arc(center: Vector2, radius: float, from: float, delta: float, color: Color, line_width: float) -> void:
	if delta == 0.0:
		return
	var start := from + 0.5
	var end := from + delta + 0.5
	_span_arc(center, radius, minf(start, end), maxf(start, end), color, line_width)
	var tip := _at(center, radius, end)
	var tangent := Vector2.from_angle(_angle(end) + (PI / 2.0 if delta > 0.0 else -PI / 2.0))
	var side := tangent.orthogonal() * 5.0
	draw_colored_polygon(PackedVector2Array([tip + tangent * 6.0, tip - tangent * 4.0 + side, tip - tangent * 4.0 - side]), color)


func _burst(at: Vector2, reach: float, color: Color) -> void:
	for k in 8:
		var direction := Vector2.from_angle(TAU * k / 8.0)
		draw_line(at + direction * reach * 0.55, at + direction * reach, color, 2.0)


## Broadcast only: a card per entrant with its core cells (held or lost, in core
## order), the count, the change since the last tick boundary and its level.
func _draw_core_gauges() -> void:
	var font := ThemeDB.fallback_font
	var card := Vector2(236.0, 66.0)
	for e in cores.size():
		var status: Dictionary = cores[e]
		var color := ENTRANT_COLORS[e % ENTRANT_COLORS.size()]
		var origin := Vector2(8.0 if e % 2 == 0 else size.x - card.x - 8.0, 8.0 + (e / 2) * (card.y + 8.0))
		var level := String(status["level"])
		var border := CRITICAL if level == "critical" else (color.darkened(0.6) if level == "eliminated" else color)
		draw_rect(Rect2(origin, card), Color(0.35, 0.05, 0.05, 0.85) if level == "critical" else Color(0.1, 0.1, 0.13, 0.9))
		draw_rect(Rect2(origin, card), border, false, 3.0 if level == "critical" else 1.5)
		var entrant: Dictionary = entrants[e]
		draw_string(font, origin + Vector2(8, 18), "%s %s" % [entrant["id"], entrant["name"]], HORIZONTAL_ALIGNMENT_LEFT, card.x - 16, 14, color)
		var owners: PackedInt32Array = state["owners"]
		var core: Array = entrant["core"]
		for k in core.size():
			var held: bool = owners[int(core[k])] == e
			var pip := Rect2(origin + Vector2(8 + k * 15, 26), Vector2(12, 12))
			if held:
				draw_rect(pip, color)
			else:
				draw_rect(pip, Color(0.3, 0.3, 0.33), false, 1.0)
		draw_string(font, origin + Vector2(134, 37), "core %d/%d" % [int(status["held"]), int(status["size"])], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
		draw_string(font, origin + Vector2(8, 58), core_note(status), HORIZONTAL_ALIGNMENT_LEFT, card.x - 16, 13, Color("#ff8080") if level == "critical" else Color(0.75, 0.75, 0.78))


## The status line of a core gauge: its level and the change this tick.
static func core_note(status: Dictionary) -> String:
	var parts: PackedStringArray = []
	match String(status["level"]):
		"eliminated":
			return "ELIMINATED"
		"critical":
			parts.append("CRITICAL")
	var delta := int(status["delta"])
	if delta < 0:
		parts.append("lost %d this tick" % -delta)
	elif delta > 0:
		parts.append("regained %d this tick" % delta)
	return "  ".join(parts)


## Broadcast only: "eliminated", "disrupted" or "active" for a process anchor.
func marker_style(anchor: Array) -> String:
	if not (state["alive"] as Array).has(anchor[0]):
		return "eliminated"
	var disrupted: Array = state["disrupted"]
	if disrupted.any(func(d: Array) -> bool: return d[0] == anchor[0] and d[1] == anchor[1]):
		return "disrupted"
	return "active"


func _cross(at: Vector2, half: float, color: Color) -> void:
	draw_line(at + Vector2(-half, -half), at + Vector2(half, half), color, 2.0)
	draw_line(at + Vector2(-half, half), at + Vector2(half, -half), color, 2.0)


func _entrant_index(entrant_id: String) -> int:
	for i in entrants.size():
		if entrants[i]["id"] == entrant_id:
			return i
	return 0


func _draw_agent(center: Vector2, radius: float, width: float) -> void:
	_draw_memory(center, radius, width)
	# Own core as an outline: its location is known, its ownership is not
	# delivered, so it must not look like the broadcast's solid "held" band.
	var core_base := int(state["core_base"])
	var core_radius := radius + width * 0.95
	for offset in int(state["core_size"]):
		var cell := (core_base + offset) % arena_size
		for edge in [-1.0, 1.0]:
			_cell_arc(center, core_radius + edge * width * 0.225, cell, agent_color, 2.0)
	var sample: Variant = state["latest_sample"]
	if sample != null:
		var color: Color = SAMPLE_COLORS.get(String(sample["status"]), Color.WHITE)
		var c := float(sample["center"])
		var h := float(sample["half_width"])
		_lane_backing(center, radius - width * 1.1, c - h, c + h + 1.0, width * 0.5)
		_span_arc(center, radius - width * 1.1, c - h, c + h + 1.0, Color(color, 0.55), width * 0.5)
	var own: Dictionary = state["own_actions"]
	for pending in own["pending_senses"]:
		var c := float(pending[1])
		var h := float(sense_half_width) if sense_half_width >= 0 else 0.5
		_lane_backing(center, radius - width * 1.1, c - h, c + h + 1.0, width * 0.4)
		_dashed_arc(center, radius - width * 1.1, c - h, c + h + 1.0, Color(agent_color, 0.9), width * 0.4)
	for process in state["processes"]:
		var anchor := float(process[1])
		var reach := float(process[2])
		_span_arc(center, radius - width * 1.9, anchor - reach, anchor + reach + 1.0, Color(agent_color, 0.18), width * 0.25)
		_marker(center, radius + width * 1.6, anchor, agent_color, true)
	for write in own["writes"]:
		var age := int(write[4])
		var target := float(write[2]) + 0.5
		if write[3] != "APPLIED":
			_cross(_at(center, radius, target), 5.0, Color(agent_color, _alpha(age)))
			continue
		if age == 0:
			var inner := radius - width * 0.55
			_write_line(center, inner, float(write[1]) + 0.5, target, Color(agent_color, 0.22), 1.0)
		# Outline only: whether the write changed ownership is not delivered.
		draw_arc(_at(center, radius, target), width * 0.24, 0.0, TAU, 12, Color(agent_color.lightened(0.35), _alpha(age)), 1.5)
	for move in own["moves"]:
		_move_arc(center, radius + width * 2.45, float(move[1]), float(move[2]), Color(agent_color, _alpha(int(move[3]))), 2.0)
	for contact in state["contacts"]:
		var age := float(contact["age_ticks"])
		var alpha := clampf(1.0 - age / 400.0, 0.3, 1.0)
		var stale: bool = contact["stale_since"] != null
		var color := Color(0.6, 0.6, 0.6, 0.5) if stale else Color(SAMPLE_COLORS["POSITIVE"], alpha)
		_marker(center, radius + width * 1.6, float(contact["address"]), color, false)
