extends SceneTree
## Render an overworld at a chosen world position, and report where the player actually stops when
## he walks north. Built to settle the Mode 7 "water/mountain edge is a bit off" question with a
## FRAME rather than with shader arithmetic. Needs a real renderer (xvfb-run).

func _init() -> void:
	var world := "medieval"
	var at := Vector2(2880, 1280)
	var move := false
	var walk := true
	var tag := "edge"
	var zoom := 0.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--world="):
			world = a.get_slice("=", 1)
		elif a.begins_with("--at="):
			var p := a.get_slice("=", 1).split(",")
			if p.size() == 2:
				at = Vector2(float(p[0]), float(p[1]))
				move = true
		elif a.begins_with("--tag="):
			tag = a.get_slice("=", 1)
		elif a.begins_with("--zoom="):
			zoom = float(a.get_slice("=", 1))
		elif a == "--no-walk":
			walk = false
	# Autoloads land after _init, same as the village harness.
	await process_frame
	await process_frame

	var paths := {
		"medieval": "res://src/exploration/OverworldScene.gd",
		"suburban": "res://src/exploration/SuburbanOverworld.gd",
		"steampunk": "res://src/exploration/SteampunkOverworld.gd",
		"industrial": "res://src/exploration/IndustrialOverworld.gd",
		"futuristic": "res://src/exploration/FuturisticOverworld.gd",
		"abstract": "res://src/exploration/AbstractOverworld.gd",
	}
	if not paths.has(world):
		push_error("unknown world %s" % world)
		quit(2)
		return
	# Prefer a .tscn when the world has one; the 2026-08-22 renderer used it and only W1 has one.
	var scene: Node = null
	var packed_path: String = paths[world].replace(".gd", ".tscn")
	if ResourceLoader.exists(packed_path):
		var packed = load(packed_path)
		if packed is PackedScene:
			scene = packed.instantiate()
	if scene == null:
		scene = load(paths[world]).new()
	root.add_child(scene)
	for i in range(6):
		await process_frame

	if zoom > 0.0:
		var cam: Camera2D = scene.get_node_or_null("OverworldPlayer/Camera")
		if cam == null and "camera" in scene:
			cam = scene.camera
		if cam != null:
			cam.zoom = Vector2(zoom, zoom)
	var p = scene.get("player")
	if p == null:
		push_error("scene exposes no player")
		quit(3)
		return
	# Omit --at to survey a world where its own spawn put the player.
	if move:
		p.global_position = at
	else:
		at = p.global_position
	for i in range(4):
		await process_frame

	var stopped: Vector2 = at
	if walk:
		# Drive the real body north until it stops moving. No grid model, no shader math.
		var last: Vector2 = p.global_position
		var still := 0
		for step in range(600):
			if p.has_method("move_and_slide"):
				p.velocity = Vector2(0, -90)
				p.move_and_slide()
			await physics_frame
			if p.global_position.distance_to(last) < 0.05:
				still += 1
				if still >= 4:
					break
			else:
				still = 0
			last = p.global_position
		stopped = p.global_position
	for i in range(6):
		await process_frame

	var img := root.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute("res://tmp/screens")
	var out := "res://tmp/screens/overworld_%s_%s.png" % [world, tag]
	img.save_png(out)
	print("[SHOT] world=%s start=%s stopped=%s  cell=%s  wrote %s (%dx%d)" % [
		world, str(at), str(stopped),
		str(Vector2i(int(stopped.x) / 32, int(stopped.y) / 32)),
		out, img.get_width(), img.get_height()])
	quit(0)
