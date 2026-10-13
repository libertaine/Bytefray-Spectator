extends SceneTree
## Native-renderer check of the actual filled pixels, with overlays suppressed
## only in this test. No fixture is altered and no match is run.

const Ring := preload("res://scripts/ring_view.gd")
const Loader := preload("res://scripts/fixture_loader.gd")
const Broadcast := preload("res://scripts/broadcast_model.gd")
const Effects := preload("res://scripts/broadcast_effects.gd")
const Agent := preload("res://scripts/agent_model.gd")
const FIXTURE := "res://fixtures/showcase/presentation"
const TICKS := [12, 320, 461, 476, 477]
const SIZE := Vector2i(1024, 1024)

class MemoryOnly:
	extends "res://scripts/ring_view.gd"
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), BACKGROUND)
		_draw_memory(size / 2.0, minf(size.x, size.y) * 0.34, maxf(minf(size.x, size.y) * 0.034, 6.0))

var viewport: SubViewport
var ring: MemoryOnly
var broadcast: Broadcast
var effects: Effects
var agent: Agent
var jobs: Array = []
var frame := 0
var checks := 0
var failures := 0


func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("memory_ring_pixels.gd requires a native renderer")
		quit(1)
		return
	var loaded := Loader.load_manifest(FIXTURE)
	if loaded.has("error"):
		printerr(loaded["error"])
		quit(1)
		return
	var b := Loader.load_presentation(FIXTURE, loaded["manifest"], "broadcast")
	var a := Loader.load_presentation(FIXTURE, loaded["manifest"], "agent_a")
	if b.has("error") or a.has("error"):
		printerr("presentation did not verify")
		quit(1)
		return
	broadcast = Broadcast.new(b["document"])
	effects = Effects.new(broadcast)
	agent = Agent.new(a["document"])
	viewport = SubViewport.new()
	viewport.size = SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	ring = MemoryOnly.new()
	ring.size = SIZE
	viewport.add_child(ring)
	# Deliberately includes a same-owner run crossing 511 -> 0.
	jobs.append(["wrap", 0])
	for perspective in ["broadcast", "agent"]:
		for tick in TICKS:
			jobs.append([perspective, tick])


func _process(_delta: float) -> bool:
	if ring == null:
		return false
	frame += 1
	if frame < 3:
		return false
	var step := frame - 3
	var index := step / 2
	if index >= jobs.size():
		print("%d pixel checks, %d failures" % [checks, failures])
		print("MEMORY PIXELS %s" % ("PASS" if failures == 0 else "FAIL"))
		quit(0 if failures == 0 else 1)
		return true
	var job: Array = jobs[index]
	if step % 2 == 0:
		if job[0] == "wrap":
			var owners := PackedInt32Array()
			owners.resize(512)
			owners.fill(-1)
			for cell in 512:
				if cell < 64 or cell >= 448:
					owners[cell] = 0
				elif cell >= 160 and cell < 320:
					owners[cell] = 1
			ring.show_broadcast({"owners": owners}, [], 512)
		elif job[0] == "broadcast":
			var at := broadcast.index_for_tick_end(job[1])
			ring.show_broadcast(broadcast.state(at), broadcast.entrants, 512, "", effects.at(at))
		else:
			ring.show_agent(agent.state(agent.index_for_tick_end(job[1])), 512)
	else:
		_check_pixels(job)
	return false


func _check_pixels(job: Array) -> void:
	var image := viewport.get_texture().get_image()
	var center := Vector2(SIZE) / 2.0
	var radius := SIZE.x * 0.34
	var width := radius * 0.1
	var outer := ring.memory_outer_radius(radius, width)
	var flashes := ring.ownership_flashes()
	for cell in 512:
		var expected := ring.memory_color(cell, flashes)
		for depth in [6.0, 20.0, 34.0]:
			_check_at(image, ring._at(center, outer - depth, cell + 0.5), expected, "%s tick %d cell %d depth %d" % [job[0], job[1], cell, depth])
		# Away from antialiased borders, the annulus cannot fill the interior
		# or grow outside Classic's original circumference.
		for offset in [-3.0, 43.0]:
			_check_at(image, ring._at(center, outer - offset, cell + 0.5), Ring.BACKGROUND, "outside band cell %d offset %d" % [cell, offset])
		if job[0] == "wrap" and ring.state["owners"][cell] == ring.state["owners"][(cell + 1) % 512]:
			_check_at(image, ring._at(center, outer - 20.0, cell + 1.0), expected, "continuous shared edge %d -> %d" % [cell, (cell + 1) % 512])


func _check_at(image: Image, at: Vector2, expected: Color, message: String) -> void:
	checks += 1
	var actual := image.get_pixel(int(round(at.x)), int(round(at.y)))
	if absf(actual.r - expected.r) > 1.1 / 255 or absf(actual.g - expected.g) > 1.1 / 255 or absf(actual.b - expected.b) > 1.1 / 255:
		failures += 1
		if failures < 12:
			printerr("FAIL: ", message, " expected ", expected, " actual ", actual)
