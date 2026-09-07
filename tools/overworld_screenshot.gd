extends SceneTree
## Renders the W1 overworld to tmp/screens/. Proves the composed map actually reaches a
## renderer -- a census and a component count say nothing about whether it DRAWS.
## Needs a real GL driver (xvfb-run). ALWAYS invoke under `timeout`: an abort in _init()
## eats the quit() below and the process hangs forever.

func _init() -> void:
	var zoom := 1.0
	var tag := "spawn"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--zoom="):
			zoom = float(a.get_slice("=", 1))
		elif a.begins_with("--tag="):
			tag = a.get_slice("=", 1)
	# Autoloads are added AFTER a -s script's _init runs; instantiating earlier fails on GameState
	await process_frame
	await process_frame
	var packed: PackedScene = load("res://src/exploration/OverworldScene.tscn")
	if packed == null:
		push_error("no OverworldScene.tscn")
		quit(2)
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	for i in range(12):
		await process_frame
	var cam: Camera2D = scene.get_node_or_null("OverworldPlayer/Camera")
	if cam == null and "camera" in scene:
		cam = scene.camera
	if cam != null and zoom != 1.0:
		cam.zoom = Vector2(zoom, zoom)
		cam.limit_left = -100000
		cam.limit_right = 100000
		cam.limit_top = -100000
		cam.limit_bottom = 100000
		for i in range(8):
			await process_frame
	var img := root.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute("res://tmp/screens")
	var out := "res://tmp/screens/overworld_%s.png" % tag
	img.save_png(out)
	print("[SCREEN] wrote %s (%dx%d) zoom=%s camera=%s" % [out, img.get_width(), img.get_height(), zoom, cam != null])
	quit(0)
