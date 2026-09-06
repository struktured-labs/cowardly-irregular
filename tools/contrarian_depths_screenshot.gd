extends SceneTree
## Loads The Backwards Warren, jumps to a floor, renders and writes tmp/screens/backwards_warren_f<N>.png. Needs xvfb-run. Modeled on village_screenshot.gd.

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var target_floor := 1
	for a in args:
		if a.begins_with("--floor="):
			target_floor = int(a.get_slice("=", 1))
	# Autoloads are added AFTER the -s script's _init runs.
	await process_frame
	await process_frame
	var scene = load("res://src/maps/dungeons/ContrarianDepths.gd").new()
	root.add_child(scene)
	for i in range(4):
		await process_frame
	# Vantage per floor, chosen to keep the puzzle geometry on-screen at zoom 2.0.
	var vantage := {1: Vector2(13, 3), 2: Vector2(10, 7), 3: Vector2(15, 6), 4: Vector2(9, 8)}
	if target_floor != scene.current_floor:
		scene.current_floor = target_floor
		scene.tile_map.clear()
		scene._generate_map_for_floor(target_floor)
		scene._update_floor_encounters(target_floor)
	var v: Vector2 = vantage.get(target_floor, Vector2(10, 7))
	scene.player.teleport(v * 32 + Vector2(16, 16))
	for i in range(10):
		await process_frame
	var img := root.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute("res://tmp/screens")
	var out := "res://tmp/screens/backwards_warren_f%d.png" % target_floor
	img.save_png(out)
	print("[SCREEN] wrote %s (%dx%d)" % [out, img.get_width(), img.get_height()])
	quit(0)
