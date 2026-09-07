extends SceneTree
## Loads a W2-W6 dungeon, jumps to a floor, renders and writes tmp/screens/<cave_id>_f<N>.png. Needs xvfb-run. Modeled on contrarian_depths_screenshot.gd.

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var script_path := "res://src/maps/dungeons/SuburbanUnderground.gd"
	var target_floor := 1
	var vantage := Vector2(10, 12)
	for a in args:
		if a.begins_with("--script="):
			script_path = a.get_slice("=", 1)
		elif a.begins_with("--floor="):
			target_floor = int(a.get_slice("=", 1))
		elif a.begins_with("--x="):
			vantage.x = float(a.get_slice("=", 1))
		elif a.begins_with("--y="):
			vantage.y = float(a.get_slice("=", 1))
	# Autoloads are added AFTER the -s script's _init runs.
	await process_frame
	await process_frame
	var scene = load(script_path).new()
	root.add_child(scene)
	for i in range(4):
		await process_frame
	if target_floor != scene.current_floor:
		# Route through the real _transition_to_floor -- a raw _generate_map_for_floor override fires a stale sensor and over-advances a floor.
		await scene._transition_to_floor(target_floor, "")
	scene.player.teleport(vantage * 32 + Vector2(16, 16))
	for i in range(10):
		await process_frame
	var img := root.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute("res://tmp/screens")
	var out := "res://tmp/screens/%s_f%d.png" % [str(scene.cave_id), target_floor]
	img.save_png(out)
	print("[SCREEN] wrote %s (%dx%d) at floor %d" % [out, img.get_width(), img.get_height(), scene.current_floor])
	quit(0)
