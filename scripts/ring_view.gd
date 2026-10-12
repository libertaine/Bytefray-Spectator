extends Control
## Draws the circular arena: one ring segment per cell, cores, process markers
## and (agent mode) delivered sensing knowledge.
##
## The view keeps broadcast data only while in broadcast mode. show_agent()
## drops it, so an agent perspective can only ever draw agent-visible state.

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
var agent_color := ENTRANT_COLORS[0]


func show_broadcast(new_state: Dictionary, broadcast_entrants: Array, cells: int) -> void:
	mode = "broadcast"
	arena_size = cells
	entrants = broadcast_entrants
	state = new_state
	queue_redraw()


func show_agent(new_state: Dictionary, cells: int) -> void:
	mode = "agent"
	arena_size = cells
	entrants = []
	state = new_state
	queue_redraw()


func clear() -> void:
	mode = ""
	entrants = []
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
	var disrupted: Array = state["disrupted"]
	for anchor in state["anchors"]:
		var index := int(_entrant_index(String(anchor[0])))
		var color := ENTRANT_COLORS[index % ENTRANT_COLORS.size()]
		var is_disrupted := disrupted.any(func(d: Array) -> bool: return d[0] == anchor[0] and d[1] == anchor[1])
		_marker(center, radius + width * 1.6, float(anchor[2]), color, not is_disrupted)


func _entrant_index(entrant_id: String) -> int:
	for i in entrants.size():
		if entrants[i]["id"] == entrant_id:
			return i
	return 0


func _draw_agent(center: Vector2, radius: float, width: float) -> void:
	for cell in arena_size:
		_cell_arc(center, radius, cell, UNKNOWN, width)
	var core_base := int(state["core_base"])
	for offset in int(state["core_size"]):
		_cell_arc(center, radius + width * 0.95, (core_base + offset) % arena_size, agent_color, width * 0.45)
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
