extends SceneTree

const ShotGuard = preload("res://tools/shot_guard.gd")
## Where does a roaming monster's CONTACT sit relative to where it is DRAWN on the Mode 7 overworld? (struktured:
## "the monster object detection in the Mode 7 overworld is still embarrassing"). A real roamer is frozen at offsets
## around the frozen player; its contact circle, the player's true point and the measured visual ground point
## (InteractGeometry.MODE7_GROUND_DISPLACEMENT_PX north) are drawn INTO the world, so the shader projects them exactly
## as it projects the monster. Needs a real renderer (xvfb-run). Writes tmp/screens/m7contact_<dir>_<dist>.png.


class Marks extends Node2D:
	var monster: Node2D
	var player: Node2D
	var touch_r: float = 48.0
	func _process(_d: float) -> void:
		queue_redraw()
	func _draw() -> void:
		if monster == null or player == null:
			return
		draw_arc(to_local(monster.global_position), touch_r, 0.0, TAU, 48, Color(1, 0.2, 0.2), 3.0)
		draw_circle(to_local(player.global_position), 6.0, Color(0.2, 1, 0.2))
		var g: Vector2 = player.global_position + Vector2(0, -InteractGeometry.MODE7_GROUND_DISPLACEMENT_PX)
		draw_circle(to_local(g), 6.0, Color(0.3, 0.6, 1))


func _init() -> void:
	var at := Vector2(2880, 1280)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--at="):
			var p := a.get_slice("=", 1).split(",")
			at = Vector2(float(p[0]), float(p[1]))
	await process_frame
	await process_frame
	var scene: Node = load("res://src/exploration/OverworldScene.tscn").instantiate() if ResourceLoader.exists("res://src/exploration/OverworldScene.tscn") else load("res://src/exploration/OverworldScene.gd").new()
	root.add_child(scene)
	for i in range(8):
		await process_frame
	var p: Node2D = scene.get("player")
	var spawner: Node = scene.get("monster_spawner")
	var roamer: Node2D = null
	if spawner:
		for c in spawner.get_children():
			if c.has_signal("touched"):
				roamer = c
				break
	if p == null or roamer == null:
		push_error("no player (%s) or no roamer (%s)" % [str(p), str(roamer)])
		quit(3)
		return
	p.global_position = at
	p.set_physics_process(false)
	p.set_process_input(false)
	roamer.process_mode = Node.PROCESS_MODE_DISABLED
	roamer.set_deferred("monitoring", false)
	roamer.visible = true
	var spr = roamer.get_node_or_null("Sprite")
	if spr:
		spr.visible = true
	var marks := Marks.new()
	marks.monster = roamer
	marks.player = p
	marks.touch_r = float(roamer.get("TOUCH_RADIUS_PX")) if roamer.get("TOUCH_RADIUS_PX") != null else 48.0
	marks.z_index = 50
	scene.add_child(marks)
	var contact_at: float = marks.touch_r + 4.0
	print("[M7C] player at %s, contact fires at world distance < %.1f, visual ground %.1f px north" % [str(at), contact_at, InteractGeometry.MODE7_GROUND_DISPLACEMENT_PX])
	DirAccess.make_dir_recursive_absolute("res://tmp/screens")
	var dirs := {"N": Vector2(0, -1), "S": Vector2(0, 1), "E": Vector2(1, 0), "W": Vector2(-1, 0)}
	for d in ["N", "S", "E", "W"]:
		for dist in [240, 180, 140, 100, 60, 40]:
			roamer.global_position = at + dirs[d] * float(dist)
			for i in range(4):
				await process_frame
			var img := root.get_texture().get_image()
			var out := "res://tmp/screens/m7contact_%s_%03d.png" % [d, dist]
			ShotGuard.save_or_refuse(img, out)
			print("[M7C] %s %3d  world_contact=%s  wrote %s" % [d, dist, str(float(dist) < contact_at), out])
	quit(3 if ShotGuard.refused > 0 else 0)
