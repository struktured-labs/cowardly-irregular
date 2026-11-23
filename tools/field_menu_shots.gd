extends SceneTree

## Stills of the FIELD menu (the overworld menu) at Text Size 1.0 / 1.5 / 2.0, cursor on the first row and on the last
## (Teleport), so the rows can be seen against the panel's border. xvfb + opengl3, not --headless: run through
## tools/field_menu_shots.sh (sandboxed). Optional args --out=res://tmp/<dir>, --members=N, --names=A,B (descenders show a name against its job line). Writes field_menu_<scale>_<top|last>.png.

func _init() -> void:
	var out_dir := "res://tmp/field_menu_shots"
	var members := 1
	var names: PackedStringArray = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.get_slice("=", 1)
		elif a.begins_with("--names="):
			names = a.get_slice("=", 1).split(",")
		elif a.begins_with("--members="):
			members = clampi(int(a.get_slice("=", 1)), 1, 5)
	DirAccess.make_dir_recursive_absolute(out_dir)
	await process_frame
	await process_frame
	var gs = root.get_node_or_null("GameState")
	var js = root.get_node_or_null("JobSystem")
	var party: Array = []
	var cast := [["Bram", "fighter"], ["Sister Ilse", "cleric"], ["Quill", "mage"], ["Nettle", "rogue"], ["Fen", "bard"]]
	for i in members:
		var pc = load("res://src/battle/Combatant.gd").new()
		pc.combatant_name = names[i] if i < names.size() else cast[i][0]
		root.add_child(pc)
		if js != null and js.has_method("assign_job"):
			js.call("assign_job", pc, cast[i][1])
		party.append(pc)
	await process_frame
	for s in [1.0, 1.5, 2.0]:
		if gs != null:
			gs.text_size_scale = s
		var m = load("res://src/ui/OverworldMenu.gd").new()
		m.set_anchors_preset(Control.PRESET_FULL_RECT)
		root.add_child(m)
		m.setup(party)
		for i in 3:
			await process_frame
		for where in ["top", "last"]:
			m.selected_index = 0 if where == "top" else m._menu_options.size() - 1
			m._update_selection()
			await process_frame
			await process_frame
			var img := root.get_viewport().get_texture().get_image()
			var path := "%s/field_menu_x%d_%s_%s.png" % [out_dir, members, str(s).replace(".", "_"), where]
			print("SCREEN saved %s err=%d windowed=%s per_col=%d" % [path, img.save_png(path), str(m.get("_menu_windowed")), int(m.get("_menu_per_col") if m.get("_menu_per_col") != null else -1)])
		m.queue_free()
		await process_frame
	if gs != null:
		gs.text_size_scale = 1.0
	quit(0)
