extends Control
## Draws the circular arena: one ring segment per cell, cores, process markers
## and (agent mode) delivered sensing knowledge.
##
## The view keeps broadcast data only while in broadcast mode. show_agent()
## drops it, so an agent perspective can only ever draw agent-visible state.
## In broadcast mode an eliminated entrant's process markers are drawn dimmed
## and crossed out, and a banner (the verified result) can be shown at the end.

const ENTRANT_COLORS: Array[Color] = [
	Color("#3fb6ff"), Color("#ff9f43"), Color("#c18bff"), Color("#5be37d"),
]
const UNOWNED := Color(0.20, 0.21, 0.25)
const UNKNOWN := Color(0.14, 0.14, 0.17)
const SAMPLE_COLORS := {
	"POSITIVE": Color("#ffd166"),
	"EMPTY": Color("#7c8db5"),
	"REFUSED": Color("#ef476f"),
}

var mode := ""
var arena_size := 512
var state: Dictionary = {}
var entrants: Array = []  # broadcast mode only
var banner := ""  # broadcast mode only
var agent_color := ENTRANT_COLORS[0]


func show_broadcast(new_state: Dictionary, broadcast_entrants: Array, cells: int, result_banner: String = "") -> void:
	mode = "broadcast"
	arena_size = cells
	entrants = broadcast_entrants
	banner = result_banner
	state = new_state
	queue_redraw()


func show_agent(new_state: Dictionary, cells: int) -> void:
	mode = "agent"
	arena_size = cells
	entrants = []
	banner = ""
	state = new_state
	queue_redraw()


func clear() -> void:
	mode = ""
	entrants = []
	banner = ""
	state = {}
	queue_redraw()


func _angle(cell: float) -> float:
	return -PI / 2.0 + TAU * cell / float(arena_size)


func _at(center: Vector2, radius: float, cell: float) -> Vector2:
	return center + Vector2.from_angle(_angle(cell)) * radius


func _cell_arc(center: Vector2, radius: float, cell: int, color: Color, width: float) -> void:
	draw_arc(center, radius, _angle(cell), _angle(cell + 0.92), 3, color, width)


func _span_arc(center: Vector2, radius: float, from_cell: float, to_cell: float, color: Color, width: float) -> void:
	var points := maxi(4, int(abs(to_cell - from_cell) / 2.0))
	draw_arc(center, radius, _angle(from_cell), _angle(to_cell), points, color, width)


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


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.07, 0.07, 0.09))
	if state.is_empty():
		return
	var center := size / 2.0
	var radius := minf(size.x, size.y) * 0.36
	var width := maxf(radius * 0.10, 6.0)
	if mode == "broadcast":
		_draw_broadcast(center, radius, width)
	elif mode == "agent":
		_draw_agent(center, radius, width)


func _draw_broadcast(center: Vector2, radius: float, width: float) -> void:
	var owners: PackedInt32Array = state["owners"]
	for cell in arena_size:
		var code := owners[cell]
		var color := UNOWNED if code < 0 else ENTRANT_COLORS[code % ENTRANT_COLORS.size()].darkened(0.35)
		_cell_arc(center, radius, cell, color, width)
	var alive: Array = state["alive"]
	for i in entrants.size():
		var color := ENTRANT_COLORS[i % ENTRANT_COLORS.size()]
		if not alive.has(entrants[i]["id"]):
			color = color.darkened(0.7)
		for cell in entrants[i]["core"]:
			var held: bool = owners[int(cell)] == i
			_cell_arc(center, radius + width * 0.95, int(cell), color if held else color.darkened(0.6), width * 0.45)
	for anchor in state["anchors"]:
		var index := int(_entrant_index(String(anchor[0])))
		var color := ENTRANT_COLORS[index % ENTRANT_COLORS.size()]
		var style := marker_style(anchor)
		if style == "eliminated":
			color = color.darkened(0.7)
		_marker(center, radius + width * 1.6, float(anchor[2]), color, style == "active")
		if style == "eliminated":
			_cross(_at(center, radius + width * 1.6 + 7.0, float(anchor[2]) + 0.5), 8.0, Color(0.85, 0.85, 0.85))
	if not banner.is_empty():
		var font := ThemeDB.fallback_font
		var font_size := int(clampf(radius * 0.11, 14.0, 30.0))
		var text_size := font.get_string_size(banner, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
		var origin := center + Vector2(-text_size.x / 2.0, font_size * 0.35)
		draw_string(font, origin, banner, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)


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
	for cell in arena_size:
		_cell_arc(center, radius, cell, UNKNOWN, width)
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
		_span_arc(center, radius - width * 1.1, c - h, c + h + 1.0, Color(color, 0.55), width * 0.5)
	for process in state["processes"]:
		var anchor := float(process[1])
		var reach := float(process[2])
		_span_arc(center, radius - width * 1.9, anchor - reach, anchor + reach + 1.0, Color(agent_color, 0.18), width * 0.25)
		_marker(center, radius + width * 1.6, anchor, agent_color, true)
	for contact in state["contacts"]:
		var age := float(contact["age_ticks"])
		var alpha := clampf(1.0 - age / 400.0, 0.3, 1.0)
		var stale: bool = contact["stale_since"] != null
		var color := Color(0.6, 0.6, 0.6, 0.5) if stale else Color(SAMPLE_COLORS["POSITIVE"], alpha)
		_marker(center, radius + width * 1.6, float(contact["address"]), color, false)
