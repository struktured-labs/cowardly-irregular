extends SceneTree
## Loads a village scene, pins a day phase, renders a few frames and writes tmp/screens/<village>_<phase>.png. Needs a real renderer (xvfb-run).

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var village := "harmonia"
	var phase := 0.3
	for a in args:
		if a.begins_with("--village="):
			village = a.get_slice("=", 1)
		elif a.begins_with("--phase="):
			phase = float(a.get_slice("=", 1))
	# Autoloads are added AFTER the -s script's _init runs; compiling the village before then fails on SoundManager/GameState
	await process_frame
	await process_frame
	var path := "res://src/maps/villages/%sVillage.tscn" % village.capitalize()
	var packed: PackedScene = load(path)
	if packed == null:
		push_error("no scene at %s" % path)
		quit(2)
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	if "lighting" in scene and scene.lighting != null:
		scene.lighting.phase_override = phase
	for i in range(8):
		await process_frame
	var img := root.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute("res://tmp/screens")
	var out := "res://tmp/screens/%s_%.2f.png" % [village, phase]
	img.save_png(out)
	print("[SCREEN] wrote %s (%dx%d)" % [out, img.get_width(), img.get_height()])
	quit(0)
