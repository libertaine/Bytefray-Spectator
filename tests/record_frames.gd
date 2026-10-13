extends SceneTree
## Records viewer playback as numbered PNG frames at a fixed frame rate.
##
## Needs a real renderer (not --headless):
##   godot --path . --script res://tests/record_frames.gd -- --fixture=showcase \
##       --perspective=broadcast --tick=440 --speed=5 --fps=30 --frames=256 --out=<dir>
## then, for example:
##   ffmpeg -framerate 30 -i <dir>/frame-%05d.png -c:v libx264 -preset slow -crf 28 -pix_fmt yuv420p <file.mp4>
##
## Playback starts paused at --tick and is advanced by exactly 1/fps seconds
## per recorded frame through the viewer's own _process, as Godot's fixed-fps
## movie mode would, but into a fixed 1280x800 SubViewport, so the recording
## does not depend on the display. The same options give the same frames.

const SIZE := Vector2i(1280, 800)

var _main: Node
var _viewport: SubViewport
var _out := ""
var _fps := 30
var _frames := 256
var _frame := 0
var _saved := 0


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg.begins_with("--fps="):
			_fps = int(arg.trim_prefix("--fps="))
		elif arg.begins_with("--frames="):
			_frames = int(arg.trim_prefix("--frames="))
	DirAccess.make_dir_recursive_absolute(_out)
	_viewport = SubViewport.new()
	_viewport.size = SIZE
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	_viewport.add_child(_main)  # main reads --fixture=, --perspective=, --tick=, --speed= in _ready


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 2:
		if _main.load_error != "":
			printerr("fixture rejected: ", _main.load_error)
			quit(1)
			return true
		_main.set_process(false)  # advanced only by the fixed step below
		_main.set_playing(true)
	if _frame < 3:
		return false
	# Odd steps save what the previous engine frame drew, then advance one step.
	if (_frame - 3) % 2 == 0:
		_viewport.get_texture().get_image().save_png(_out.path_join("frame-%05d.png" % _saved))
		_saved += 1
		if _saved >= _frames:
			print("recorded %d frames at %d fps" % [_saved, _fps])
			quit(0)
			return true
		_main._process(1.0 / float(_fps))
	return false
