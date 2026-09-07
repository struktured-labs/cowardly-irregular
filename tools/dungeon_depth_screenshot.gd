extends SceneTree
## Loads a W1 depth-pass dungeon and renders every requested floor to tmp/screens/<id>_f<N>.png.
## Usage: --dungeon=res://src/maps/dungeons/FireDragonCave.gd --floors=1,2,3,4,5 [--vantage=10,7;10,12;...]. Needs xvfb-run.

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var dungeon_path := "res://src/maps/dungeons/FireDragonCave.gd"
	var floors: Array = [1]
	var vantages: Array = []
	for a in args:
		if a.begins_with("--dungeon="):
			dungeon_path = a.get_slice("=", 1)
		elif a.begins_with("--floors="):
			floors.clear()
			for f in a.get_slice("=", 1).split(","):
				floors.append(int(f))
		elif a.begins_with("--vantage="):
			for v in a.get_slice("=", 1).split("|"):
				var parts := v.split(",")
				vantages.append(Vector2(float(parts[0]), float(parts[1])))
	# Autoloads are added AFTER the -s script's _init runs.
	await process_frame
	await process_frame
	var scene = load(dungeon_path).new()
	root.add_child(scene)
	for i in range(4):
		await process_frame
	DirAccess.make_dir_recursive_absolute("res://tmp/screens")
	for idx in range(floors.size()):
		var target_floor: int = floors[idx]
		var vantage: Vector2 = vantages[idx] if idx < vantages.size() else Vector2(10, 7)
		if target_floor != scene.current_floor:
			scene.current_floor = target_floor
			scene.tile_map.clear()
			scene._generate_map_for_floor(target_floor)
			scene._update_floor_encounters(target_floor)
		scene.player.teleport(vantage * 32 + Vector2(16, 16))
		for i in range(10):
			await process_frame
		var img := root.get_texture().get_image()
		var out := "res://tmp/screens/%s_f%d.png" % [scene.cave_id, target_floor]
		img.save_png(out)
		print("[SCREEN] wrote %s (%dx%d)" % [out, img.get_width(), img.get_height()])
	quit(0)
