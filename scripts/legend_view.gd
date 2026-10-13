extends Control
## A concise legend for the ring encodings of the active perspective.
##
## The legend is static per perspective: it is the same at every position of
## every match, so it reveals nothing. The Agent A legend describes only what
## the Agent A view draws.

const RingView := preload("res://scripts/ring_view.gd")

const BROADCAST := [
	["owned", "Cells owned by A / B"],
	["core", "Core cells: bright = held, dark = lost"],
	["markers", "Process; hollow = hit by an opponent WRITE last tick"],
	["pending", "SENSE sample taken, not yet delivered"],
	["delivered", "Sample delivered to its process"],
	["writes", "WRITE: filled = took the cell, ring = owner unchanged"],
	["move", "MOVE"],
	["core_marks", "Core cell lost (red) / regained (white)"],
	["burst", "Hit at tick end; effects fade over 3 ticks"],
]
const AGENT := [
	["own_core", "Own core location (ownership not delivered)"],
	["markers_agent", "Own process and its reach"],
	["pending_agent", "Own SENSE requested, result pending"],
	["sample", "Latest delivered sample (gold = positive)"],
	["contacts", "Remembered contact; grey = absent in a newer sample"],
	["write_agent", "Own WRITE target (outcome not delivered)"],
	["move_agent", "Own MOVE"],
]
const ROW := 19.0

var perspective := "broadcast"


func set_perspective(value: String) -> void:
	perspective = value
	custom_minimum_size = Vector2(0, rows().size() * ROW + 8.0)
	queue_redraw()


func rows() -> Array:
	return BROADCAST if perspective == "broadcast" else AGENT


## The legend text, for tests and traces.
func text() -> String:
	return "\n".join(rows().map(func(row: Array) -> String: return row[1]))


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.1, 0.1, 0.13))
	var font := ThemeDB.fallback_font
	var y := 4.0
	for row in rows():
		_glyph(String(row[0]), Vector2(8, y + ROW / 2.0))
		draw_string(font, Vector2(64, y + 14), String(row[1]), HORIZONTAL_ALIGNMENT_LEFT, size.x - 70, 13, Color(0.85, 0.85, 0.88))
		y += ROW


func _glyph(kind: String, at: Vector2) -> void:
	var a: Color = RingView.ENTRANT_COLORS[0]
	var b: Color = RingView.ENTRANT_COLORS[1]
	var gold: Color = RingView.SAMPLE_COLORS["POSITIVE"]
	match kind:
		"owned":
			draw_rect(Rect2(at + Vector2(0, -5), Vector2(20, 10)), a.darkened(0.35))
			draw_rect(Rect2(at + Vector2(24, -5), Vector2(20, 10)), b.darkened(0.35))
		"core":
			draw_rect(Rect2(at + Vector2(0, -3), Vector2(20, 6)), a)
			draw_rect(Rect2(at + Vector2(24, -3), Vector2(20, 6)), a.darkened(0.6))
		"markers", "markers_agent":
			_triangle(at + Vector2(6, 0), a, true)
			if kind == "markers":
				_triangle(at + Vector2(30, 0), a, false)
			else:
				draw_line(at + Vector2(18, 0), at + Vector2(46, 0), Color(a, 0.4), 3.0)
		"pending", "pending_agent":
			for k in 4:
				draw_line(at + Vector2(k * 12, 0), at + Vector2(k * 12 + 7, 0), a, 4.0)
			if kind == "pending":
				draw_arc(at + Vector2(22, 0), 4.0, 0.0, TAU, 12, Color.WHITE, 1.5)
		"delivered":
			draw_line(at, at + Vector2(44, 0), Color(a, 0.55), 4.0)
			draw_circle(at + Vector2(22, 0), 4.0, Color.WHITE)
		"writes":
			draw_circle(at + Vector2(10, 0), 5.0, a.lightened(0.35))
			draw_arc(at + Vector2(32, 0), 5.0, 0.0, TAU, 12, b.lightened(0.35), 1.5)
		"write_agent":
			draw_arc(at + Vector2(10, 0), 5.0, 0.0, TAU, 12, a.lightened(0.35), 1.5)
		"move", "move_agent":
			draw_line(at, at + Vector2(38, 0), a, 2.0)
			draw_colored_polygon(PackedVector2Array([at + Vector2(46, 0), at + Vector2(38, -5), at + Vector2(38, 5)]), a)
		"core_marks":
			draw_arc(at + Vector2(10, 0), 7.0, 0.0, TAU, 16, RingView.DAMAGE, 2.5)
			draw_arc(at + Vector2(32, 0), 7.0, 0.0, TAU, 16, RingView.RECOVERY, 2.5)
		"burst":
			for k in 8:
				var direction := Vector2.from_angle(TAU * k / 8.0)
				draw_line(at + Vector2(10, 0) + direction * 4.0, at + Vector2(10, 0) + direction * 8.0, Color.WHITE, 2.0)
		"own_core":
			draw_rect(Rect2(at + Vector2(0, -4), Vector2(44, 8)), a, false, 2.0)
		"sample":
			draw_line(at, at + Vector2(44, 0), Color(gold, 0.55), 5.0)
		"contacts":
			_triangle(at + Vector2(6, 0), gold, false)
			_triangle(at + Vector2(30, 0), Color(0.6, 0.6, 0.6), false)


func _triangle(at: Vector2, color: Color, filled: bool) -> void:
	var points := PackedVector2Array([at + Vector2(0, -7), at + Vector2(12, -7), at + Vector2(6, 6)])
	if filled:
		draw_colored_polygon(points, color)
	else:
		points.append(points[0])
		draw_polyline(points, color, 2.0)
