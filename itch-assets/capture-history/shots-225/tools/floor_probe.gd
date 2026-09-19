extends SceneTree
## Probe: does ContrarianDepths render real geometry when bare-instantiated,
## and at which floor? Size is the tell — its base class DragonCave produced a
## 7.7 KB empty grey void where populated scenes are 50-180 KB.
func _init() -> void:
	await process_frame
	await process_frame
	DirAccess.make_dir_recursive_absolute("res://tmp/marketing")
	var src := load("res://src/maps/dungeons/ContrarianDepths.gd")
	if src == null:
		print("[PROBE] FAIL: ContrarianDepths.gd did not load"); quit(1); return
	for f in [1, 2, 3, 4]:
		var s = src.new()
		if not ("current_floor" in s):
			print("[PROBE] FAIL: no current_floor property on the instance"); quit(1); return
		s.current_floor = f
		root.add_child(s)
		for i in range(14):
			await process_frame
		var img := root.get_texture().get_image()
		var p := "res://tmp/marketing/probe_warren_f%d.png" % f
		img.save_png(p)
		var fa := FileAccess.open(p, FileAccess.READ)
		var sz := fa.get_length() if fa else 0
		if fa: fa.close()
		print("[PROBE] floor %d -> %d bytes (%dx%d)" % [f, sz, img.get_width(), img.get_height()])
		s.queue_free()
		await process_frame
	quit(0)
