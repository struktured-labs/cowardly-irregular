extends SceneTree

## A clip of a story cutscene played by the REAL game (GameLoop's gate and _play_story_cutscene), for --write-movie capture.
## Run through tools/scene_clip.sh. Args: --flags=<a,b: game_constants set true first> --map=<map id, default harmonia_village>
## --expect=<the id the story gate must return> --seconds=<cap> --press_every=<seconds between confirm presses, default 2.2>

func _init() -> void:
	var flags := PackedStringArray()
	var map := "harmonia_village"
	var expect := ""
	var seconds := 60.0
	var press_every := 2.2
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--flags="):
			flags = a.get_slice("=", 1).split(",", false)
		elif a.begins_with("--map="):
			map = a.get_slice("=", 1)
		elif a.begins_with("--expect="):
			expect = a.get_slice("=", 1)
		elif a.begins_with("--seconds="):
			seconds = float(a.get_slice("=", 1))
		elif a.begins_with("--press_every="):
			press_every = float(a.get_slice("=", 1))
	await process_frame
	await process_frame
	var gs = root.get_node_or_null("GameState")
	if gs and "debug_log_enabled" in gs:
		gs.debug_log_enabled = false
	var hints = load("res://src/ui/TutorialHints.gd")
	if gs and hints and ("HINTS" in hints):
		for id in hints.HINTS.keys():
			gs.game_constants["tutorial_" + str(id)] = true
	var gl: Node = (load("res://src/GameLoop.tscn") as PackedScene).instantiate()
	root.add_child(gl)
	for i in 4:
		await process_frame
	if gl.has_method("_close_title_screen"):
		gl._close_title_screen()
	await process_frame
	gl._create_party()
	gs.game_constants["cutscene_flag_prologue_complete"] = true
	for f in flags:
		gs.game_constants[f] = true
	gl._current_map_id = map
	gl._start_exploration()
	for i in 45:
		await process_frame
	var dbg = root.get_node_or_null("DebugLogOverlay")
	if dbg and dbg.has_method("set_enabled"):
		dbg.set_enabled(false)
	var pending: String = gl._get_pending_story_cutscene()
	print("[SCLIP] map=%s gate=%s" % [map, pending])
	if pending == "" or (expect != "" and pending != expect):
		print("[SCLIP] FAIL: the story gate returned '%s', expected '%s'" % [pending, expect])
		quit(1)
		return
	var director = gl.get_cutscene_director()
	var state := {"done": false}
	director.cutscene_finished.connect(func(id: String) -> void:
		state["done"] = true
		print("[SCLIP] finished=%s frame=%d" % [id, Engine.get_process_frames()]))
	print("[SCLIP] built frame=%d" % Engine.get_process_frames())
	gl._play_story_cutscene(pending)
	## Frames, not a timer: under --fixed-fps 30 a frame is 1/30 s of VIDEO. A confirm press every `press_every` seconds.
	var every := maxi(2, int(round(press_every * 30.0)))
	var tail := 0
	for i in int(round(seconds * 30.0)):
		await process_frame
		if i % every == every - 1:
			_press(true)
		elif i % every == 1:
			_press(false)
		if state["done"]:
			tail += 1
			if tail > 45:
				break
	print("[SCLIP] done finished=%s complete_flag=%s" % [state["done"], gs.game_constants.get("cutscene_flag_%s_complete" % pending, false)])
	quit(0 if state["done"] else 1)


func _press(down: bool) -> void:
	var ev := InputEventAction.new()
	ev.action = "ui_accept"
	ev.pressed = down
	Input.parse_input_event(ev)
