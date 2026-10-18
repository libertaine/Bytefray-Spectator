extends SceneTree
## Standalone presentation handling: manifest versions, rejection, reloading
## and the ways a user opens a presentation (File menu, drop, launch option).
##
## Run: godot --headless --path . --script res://tests/presentation_check.gd [-- --fixture=<v2 presentation dir>]
## Exit code 0 = pass, 1 = failure (each failure is printed).
##
## The v2 presentation defaults to the bundled production sample; pass any
## presentation written by `bytefray spectator export` to check that instead.
## Tampered copies are written under user://presentation_check only.

const FixtureLoader := preload("res://scripts/fixture_loader.gd")
const MainScript := preload("res://scripts/main.gd")
const SHOWCASE := "res://fixtures/showcase/presentation"
const DEV := "res://fixtures/dev/presentation"
const SAMPLE := "res://fixtures/production_sample/presentation"
const WORK := "user://presentation_check"
const FILES := ["manifest.json", "broadcast.json", "agent_a.json"]

var failures: PackedStringArray = []
var checks := 0
var _main: Node
var _frame := 0
var _v2 := SAMPLE


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("FAIL: ", message)


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--fixture="):
			_v2 = arg.substr("--fixture=".length())
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 1:
		_run(_main)
	if _frame < 3:
		return false
	print("%d checks, %d failures" % [checks, failures.size()])
	print("PRESENTATION CHECK %s" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)
	return true


func _run(main: Node) -> void:
	_check_versions(main)
	_check_rejections(main)
	_check_reloading(main)
	_check_user_paths(main)
	_check_launch_options()


func _loaded(main: Node, label: String) -> bool:
	var ok: bool = main.load_error.is_empty() and main.broadcast != null and main.agent != null
	check(ok, "%s loads (%s)" % [label, main.load_error])
	return ok


func _check_versions(main: Node) -> void:
	# Default start: the bundled showcase, a version-1 (pinned prototype) presentation.
	check(_loaded(main, "default showcase"), "the viewer opens the showcase by default")
	check(FixtureLoader.manifest_version(main.manifest) == 1, "the showcase is manifest version 1")
	check(main._footer.text.begins_with("Verified fixture  |  Bytefray 9c81718  |"), "v1 footer wording is unchanged: %s" % main._footer.text)

	check(main.open_presentation(_v2) == "", "the v2 presentation opens: %s" % main.load_error)
	if not _loaded(main, "v2 presentation"):
		return
	var manifest: Dictionary = main.manifest
	check(FixtureLoader.manifest_version(manifest) == 2, "a production export is manifest version 2")
	check(manifest["verification"]["provenance"] == "bytefray_match", "v2 provenance is bytefray_match")
	var version := String(manifest["bytefray"]["version"])
	check(main._footer.text.begins_with("Verified Bytefray match  |  Bytefray %s  |" % version), "v2 footer names the exporting Bytefray: %s" % main._footer.text)
	check(main.get_window().title.begins_with("Bytefray Spectator - ") and main.get_window().title.contains(" vs "), "the window title names the match: %s" % main.get_window().title)
	check(main.perspective == "broadcast" and main.index == 0 and not main.playing, "a newly opened presentation starts paused at the beginning in Broadcast")
	main.set_perspective("agent_a")
	check(main.perspective == "agent_a" and main.agent.entrant_id == "A", "Agent A perspective of a v2 presentation")
	check(main._position_label.text.contains("(limit %d)" % int(manifest["match"]["tick_limit"])), "Agent A shows only the public tick limit")
	main.jump_to_end()
	check(main.current_tick() <= int(manifest["match"]["tick_limit"]), "Agent A seeks within its own record")
	main.set_perspective("broadcast")
	main.jump_to_end()
	check(main.current_tick() == int(manifest["match"]["ticks"]), "Broadcast reaches the recorded end of a v2 presentation")


func _copy(source: String, name: String) -> String:
	var target := WORK.path_join(name)
	DirAccess.make_dir_recursive_absolute(target)
	for file in FILES:
		var from := source.path_join(file)
		if FileAccess.file_exists(from):
			var bytes := FileAccess.get_file_as_bytes(from)
			var out := FileAccess.open(target.path_join(file), FileAccess.WRITE)
			out.store_buffer(bytes)
			out.close()
	return target


func _edit_manifest(dir: String, edit: Callable) -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("manifest.json")))
	edit.call(manifest)
	var out := FileAccess.open(dir.path_join("manifest.json"), FileAccess.WRITE)
	out.store_string(JSON.stringify(manifest))
	out.close()


func _write(dir: String, file: String, bytes: PackedByteArray) -> void:
	var out := FileAccess.open(dir.path_join(file), FileAccess.WRITE)
	out.store_buffer(bytes)
	out.close()


func _rejected(main: Node, dir: String, expected: String, label: String) -> void:
	var error: String = main.open_presentation(dir)
	check(error.contains(expected), "%s is rejected with '%s' (got '%s')" % [label, expected, error])
	check(main.broadcast == null and main.agent == null and main.manifest.is_empty(), "%s: nothing from it is kept" % label)
	check(main._title.text == "Fixture rejected" and main._ring.state.is_empty(), "%s: nothing from it is shown" % label)
	check(main._play_button.disabled and not main._jump.editable, "%s: playback controls are disabled" % label)
	check(main.get_window().title.ends_with("presentation rejected"), "%s: the window title says it was rejected" % label)


func _check_rejections(main: Node) -> void:
	var cases := {
		"manifest version 3": [func(m: Dictionary) -> void: m["schema_version"] = 3, "unsupported manifest schema"],
		"fractional manifest version": [func(m: Dictionary) -> void: m["schema_version"] = 2.5, "unsupported manifest schema"],
		"foreign manifest schema": [func(m: Dictionary) -> void: m["schema"] = "something.else", "unsupported manifest schema"],
		"v2 claiming a prototype provenance": [func(m: Dictionary) -> void: m["verification"]["provenance"] = "showcase_match", "unknown provenance"],
		"v1 claiming the production provenance": [func(m: Dictionary) -> void: m["schema_version"] = 1, "unknown provenance"],
		"unverified replay preflight": [func(m: Dictionary) -> void: m["verification"]["result_replay_preflight"] = false, "result_replay_preflight"],
		"sources changed during export": [func(m: Dictionary) -> void: m["verification"].erase("sources_unchanged"), "sources_unchanged"],
		"unverified outcome": [func(m: Dictionary) -> void: m["verification"]["outcome_verified"] = false, "outcome_verified"],
		"unchecked agent allowlist": [func(m: Dictionary) -> void: m["verification"].erase("agent_view_allowlist_checked"), "agent_view_allowlist_checked"],
		"unknown exporter": [func(m: Dictionary) -> void: m["exporter"]["name"] = "someone_else", "unknown exporter"],
		"no Bytefray version": [func(m: Dictionary) -> void: m["bytefray"].erase("version"), "no Bytefray version"],
		"no tick limit": [func(m: Dictionary) -> void: m["match"].erase("tick_limit"), "no tick limit"],
		"document version 2": [func(m: Dictionary) -> void: m["presentation"]["broadcast"]["schema_version"] = 2, "unexpected schema"],
		"path traversal": [func(m: Dictionary) -> void: m["presentation"]["agent_a"]["path"] = "../agent_a.json", "unsafe presentation path"],
		"wrong digest": [func(m: Dictionary) -> void: m["presentation"]["broadcast"]["sha256"] = "0".repeat(64), "SHA-256 does not match"],
	}
	for label in cases:
		var dir := _copy(_v2, "case_%d" % checks)
		_edit_manifest(dir, cases[label][0])
		_rejected(main, dir, cases[label][1], label)

	var changed := _copy(_v2, "changed_broadcast")
	var bytes := FileAccess.get_file_as_bytes(changed.path_join("broadcast.json"))
	bytes[bytes.size() / 2] = bytes[bytes.size() / 2] ^ 1
	_write(changed, "broadcast.json", bytes)
	_rejected(main, changed, "SHA-256 does not match", "a changed broadcast.json")

	var missing := _copy(_v2, "missing_agent")
	DirAccess.remove_absolute(missing.path_join("agent_a.json"))
	_rejected(main, missing, "agent_a.json is missing", "a missing agent_a.json")

	var empty := WORK.path_join("empty")
	DirAccess.make_dir_recursive_absolute(empty)
	_rejected(main, empty, "manifest.json not found", "a folder with no manifest")

	var garbage := _copy(_v2, "garbage_manifest")
	_write(garbage, "manifest.json", "not json".to_utf8_buffer())
	_rejected(main, garbage, "not a JSON object", "a malformed manifest")


func _check_reloading(main: Node) -> void:
	# From a rejected presentation, the next good one opens normally.
	check(main.open_presentation(_v2) == "", "a good presentation opens after a rejection")
	main.seek_tick(5)
	main.set_perspective("agent_a")
	main.set_playing(true)
	main._process(0.5)
	check(main.playing, "v2 playback runs")
	# Opening another presentation during playback stops it and starts fresh.
	check(main.open_presentation(SHOWCASE) == "", "the showcase reopens during playback")
	check(not main.playing and main._play_button.text == "Play", "opening a presentation stops playback")
	check(main.perspective == "broadcast" and main.index == 0 and main.current_tick() == 0, "the reopened presentation starts at the beginning")
	check(main.sound.active_voices() == 0 and main.intro_left() == 0.0, "no sound or opening sequence carries over")
	for dir in [DEV, _v2, SHOWCASE, _v2, DEV]:
		check(main.open_presentation(dir) == "" and main.frame_count() > 0, "repeated loading of %s" % dir)
	check(int(main.manifest["match"]["seed"]) == 0, "the last presentation loaded is the one shown")


func _check_user_paths(main: Node) -> void:
	# The File menu offers Open, the bundled showcase and Quit.
	var popup: PopupMenu = main._file_menu.get_popup()
	var items: PackedStringArray = []
	for i in popup.item_count:
		items.append(popup.get_item_text(i))
	check(items == PackedStringArray(["Open Presentation...", "Open Bundled Showcase", "", "Quit"]), "File menu items: %s" % [items])
	main._on_file_menu(MainScript.MENU_SHOWCASE)
	check(main.load_error.is_empty() and main.fixture_dir == SHOWCASE, "File > Open Bundled Showcase")
	main.show_open_dialog()
	var dialog: FileDialog = main._open_dialog
	check(dialog != null and dialog.file_mode == FileDialog.FILE_MODE_OPEN_DIR and dialog.access == FileDialog.ACCESS_FILESYSTEM, "File > Open Presentation chooses a folder anywhere on disk")
	dialog.hide()
	dialog.dir_selected.emit(ProjectSettings.globalize_path(_v2) if _v2.begins_with("res://") else _v2)
	check(main.load_error.is_empty() and FixtureLoader.manifest_version(main.manifest) == 2, "choosing a folder in the dialog opens it")
	# A dropped manifest.json opens its folder; a dropped folder opens itself.
	main.open_presentation(SHOWCASE)
	var on_disk := ProjectSettings.globalize_path(SAMPLE)
	main._on_files_dropped(PackedStringArray([on_disk.path_join("manifest.json")]))
	check(main.load_error.is_empty() and main.fixture_dir == on_disk, "dropping manifest.json opens its folder")
	main.open_presentation(SHOWCASE)
	main._on_files_dropped(PackedStringArray([on_disk.replace("/", "\\") if OS.get_name() == "Windows" else on_disk]))
	check(main.load_error.is_empty() and main.fixture_dir == on_disk, "dropping the folder opens it (native separators): %s" % main.fixture_dir)


func _check_launch_options() -> void:
	var options: Dictionary = MainScript.launch_options(PackedStringArray([
		"--fixture=C:/Matches/a=b/presentation", "--perspective=agent_a", "--tick=12", "--speed=20", "--rendering=classic", "--play",
	]))
	check(options["fixture"] == "C:/Matches/a=b/presentation", "a fixture path may contain '=': %s" % options["fixture"])
	check(options["perspective"] == "agent_a" and options["tick"] == 12 and options["play"] == true, "launch options parse")
	check(options["rendering"] == "classic" and MainScript.SPEEDS[options["speed"]] == 20.0, "rendering and speed parse")
	check(options["check"] == false and MainScript.launch_options(PackedStringArray(["--check"]))["check"] == true, "--check parses")
	check(MainScript.launch_options(PackedStringArray(["--fixture=sample"]))["fixture"] == SAMPLE, "--fixture=sample names the bundled production sample")
	check(MainScript.launch_options(PackedStringArray(["--fixture=D:\\Runs\\x"]))["fixture"] == "D:\\Runs\\x", "a Windows path is passed through unchanged")
