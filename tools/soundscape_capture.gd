extends SceneTree

## Loads a village, plays it by day then by night under --write-movie, so the music and the living soundscape are captured together.

func _init() -> void:
	var village := "harmonia"
	var day_s := 40.0
	var night_s := 25.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--village="):
			village = a.get_slice("=", 1)
		elif a.begins_with("--day="):
			day_s = float(a.get_slice("=", 1))
		elif a.begins_with("--night="):
			night_s = float(a.get_slice("=", 1))
	# Autoloads arrive after a -s script's _init, so wait before compiling the village.
	await process_frame
	await process_frame
	var gs = root.get_node_or_null("GameState")
	var sm = root.get_node_or_null("SoundManager")
	if gs == null or sm == null:
		push_error("[SCAPECAP] autoloads missing (GameState=%s SoundManager=%s)" % [gs, sm])
		quit(2)
		return
	gs.day_phase = 0.30
	var stem := ""
	for part in village.split("_"):
		stem += part.capitalize()
	var scene: Node = null
	for path in ["res://src/maps/villages/%sVillage.tscn" % stem, "res://src/maps/villages/%sVillage.gd" % stem]:
		if not ResourceLoader.exists(path):
			continue
		var res = load(path)
		scene = res.instantiate() if res is PackedScene else res.new()
		if scene != null:
			print("[SCAPECAP] source ", path)
			break
	if scene == null:
		push_error("[SCAPECAP] no village named %s" % village)
		quit(2)
		return
	root.add_child(scene)
	await process_frame
	var place: String = sm.soundscape_place()
	print("[SCAPECAP] soundscape_place=%s bed=%s band=%s" % [place, sm._current_ambient_key, gs.get_time_of_day_name()])
	if place == "":
		push_error("[SCAPECAP] %s started no soundscape, so this capture would be music alone" % village)
		quit(3)
		return
	await create_timer(day_s).timeout
	var day_fired: int = sm._soundscape.fired.size()
	gs.day_phase = 0.70
	gs.time_of_day_changed.emit(gs.get_time_of_day_name())
	print("[SCAPECAP] nightfall at %.0fs: day events fired=%d bed=%s band=%s" % [day_s, day_fired, sm._current_ambient_key, gs.get_time_of_day_name()])
	await create_timer(night_s).timeout
	print("[SCAPECAP] done: night events fired=%d total=%d" % [sm._soundscape.fired.size() - day_fired, sm._soundscape.fired.size()])
	for s in sm._soundscape.fired:
		print("[SCAPECAP] event %s %.1fdB pan=%.2f pitch=%.2f" % [s["key"], s["volume_db"], s["pan"], s["pitch"]])
	quit(0)
