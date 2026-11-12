extends SceneTree

## Stills of the FIELD menu (the overworld menu) at Text Size 1.0 / 1.5 / 2.0, cursor on the first row and on the last
## (Teleport), so the rows can be seen against the panel's border. xvfb + opengl3, not --headless: run through
## tools/field_menu_shots.sh (sandboxed). Optional arg --out=res://tmp/<dir>. Writes field_menu_<scale>_<top|last>.png.

func _init() -> void:
	var out_dir := "res://tmp/field_menu_shots"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.get_slice("=", 1)
	DirAccess.make_dir_recursive_absolute(out_dir)
	await process_frame
	await process_frame
	var gs = root.get_node_or_null("GameState")
	var pc = load("res://src/battle/Combatant.gd").new()
	pc.combatant_name = "Bram"
	root.add_child(pc)
	var js = root.get_node_or_null("JobSystem")
	if js != null and js.has_method("assign_job"):
		js.call("assign_job", pc, "fighter")
	await process_frame
	for s in [1.0, 1.5, 2.0]:
		if gs != null:
			gs.text_size_scale = s
		var m = load("res://src/ui/OverworldMenu.gd").new()
		m.set_anchors_preset(Control.PRESET_FULL_RECT)
		root.add_child(m)
		m.setup([pc])
		for i in 3:
			await process_frame
		for where in ["top", "last"]:
			m.selected_index = 0 if where == "top" else m._menu_options.size() - 1
			m._update_selection()
			await process_frame
			await process_frame
			var img := root.get_viewport().get_texture().get_image()
			var path := "%s/field_menu_%s_%s.png" % [out_dir, str(s).replace(".", "_"), where]
			print("SCREEN saved %s err=%d windowed=%s per_col=%d" % [path, img.save_png(path), str(m.get("_menu_windowed")), int(m.get("_menu_per_col") if m.get("_menu_per_col") != null else -1)])
		m.queue_free()
		await process_frame
	if gs != null:
		gs.text_size_scale = 1.0
	quit(0)
