extends SceneTree

## A clip of a night at the inn (InnRestSequence) in the REAL inn room, for --write-movie capture at a fixed fps.
## Run through tools/inn_clip.sh (it owns the sandbox, xvfb, the pad jail and the encode).
## Args: --seconds=<length from the rest's start> --skip_at=<seconds into the night to press skip; 0 = never>

func _init() -> void:
	var seconds := 9.5
	var skip_at := 0.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seconds="):
			seconds = float(a.get_slice("=", 1))
		elif a.begins_with("--skip_at="):
			skip_at = float(a.get_slice("=", 1))
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
	## A fresh game opens Harmonia on the prologue; the clip is of the inn, so the opening is marked seen.
	for flag in ["prologue_complete", "chapter1_complete"]:
		gs.game_constants["cutscene_flag_" + flag] = true
	gl._current_map_id = "harmonia_village"
	gl._start_exploration()
	for i in 20:
		await process_frame
	gl._on_area_transition("inn_interior", "")
	var inn: Node = null
	for i in 240:
		await process_frame
		var scene = gl.get("_exploration_scene")
		if scene != null and is_instance_valid(scene) and scene.has_method("_do_rest") and not gl.get("_transition_in_progress"):
			inn = scene
			break
	if inn == null:
		print("[ICLIP] FAIL: no inn room (map=%s)" % str(gl.get("_current_map_id")))
		quit(1)
		return
	for i in 30:
		await process_frame
	var dbg = root.get_node_or_null("DebugLogOverlay")
	if dbg and dbg.has_method("set_enabled"):
		dbg.set_enabled(false)
	for m in gl.party:
		m.current_hp = maxi(1, int(m.max_hp / 3))
	if gs:
		gs.party_gold = 500
	var sm = root.get_node_or_null("SoundManager")
	var under := ""
	if sm and sm._music_player and sm._music_player.stream:
		under = str(sm._music_player.stream.resource_path).get_file().get_basename()
	var director = gl.get_cutscene_director() if gl.has_method("get_cutscene_director") else null
	print("[ICLIP] room=%s under=%s cutscene_playing=%s" % [str(gl.get("_current_map_id")), under, str(director.is_playing()) if director and director.has_method("is_playing") else "?"])
	inn._do_rest()
	var seq: Node = null
	for n in root.get_children():
		if n.has_signal("beat") and n.has_method("request_skip"):  # by shape: a -s script compiles before the autoloads a class_name leans on
			seq = n
	if seq == null:
		print("[ICLIP] FAIL: the rest started no night")
		quit(1)
		return
	seq.beat.connect(func(b: String) -> void: print("[ICLIP] beat=%s frame=%d time_scale=%.3f" % [b, Engine.get_process_frames(), Engine.time_scale]))
	print("[ICLIP] built frame=%d" % Engine.get_process_frames())
	## Frames, not a timer: under --fixed-fps 30 a frame is 1/30 s of VIDEO.
	var skip_frame := int(round(skip_at * 30.0))
	var night_from := -1
	for i in int(round(seconds * 30.0)):
		await process_frame
		if is_instance_valid(seq) and night_from < 0 and seq._skippable:
			night_from = i
			print("[ICLIP] night_sec=%.2f" % seq.night_sec)
		if skip_frame > 0 and night_from >= 0 and i - night_from == skip_frame and is_instance_valid(seq):
			seq.request_skip()
	print("[ICLIP] done")
	quit(0)
