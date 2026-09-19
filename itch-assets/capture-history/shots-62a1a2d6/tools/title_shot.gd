extends SceneTree
## Capture the title screen for provisional itch cover art.
func _init() -> void:
	await process_frame
	await process_frame
	var gs = root.get_node_or_null("GameState")
	if gs and "debug_log_enabled" in gs:
		gs.debug_log_enabled = false
	var dbg = root.get_node_or_null("DebugLogOverlay")
	if dbg and dbg.has_method("set_enabled"):
		dbg.set_enabled(false)

	var gl: Node = load("res://src/GameLoop.tscn").instantiate()
	root.add_child(gl)
	# The title screen is what _show_title_screen() puts up at boot; do NOT close it.
	# Give it time to animate in — a shot taken too early catches a fading logo.
	for i in range(6):
		await process_frame
	await create_timer(3.0).timeout

	DirAccess.make_dir_recursive_absolute("res://tmp/marketing")
	var img := root.get_texture().get_image()
	img.save_png("res://tmp/marketing/title_screen.png")
	print("[SHOT] title_screen (%dx%d)" % [img.get_width(), img.get_height()])
	quit(0)
