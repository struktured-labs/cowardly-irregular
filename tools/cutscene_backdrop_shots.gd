extends SceneTree

## One frame per cutscene backdrop, shown the way the game shows it: CutsceneDirector's own loader with a dialogue line up.
## xvfb + opengl3, not --headless. Run through tools/cutscene_backdrop_shots.sh, which sandboxes user://.
## Keys default to the Harmonia set plus a few redrawn stills; pass --keys=a,b,c to choose.

const DEFAULT_KEYS := ["harmonia_square", "harmonia_square_portal", "harmonia_inn", "harmonia_shop",
	"prologue_village", "community_center", "node_prime"]


func _init() -> void:
	var out_dir := "res://tmp/cutscene_backdrop_shots"
	var keys: Array = DEFAULT_KEYS.duplicate()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.get_slice("=", 1)
		elif a.begins_with("--keys="):
			keys = Array(a.get_slice("=", 1).split(",", false))
	out_dir = ProjectSettings.globalize_path(out_dir)
	DirAccess.make_dir_recursive_absolute(out_dir)
	await process_frame
	await process_frame

	var failed := 0
	for key in keys:
		var director = load("res://src/cutscene/CutsceneDirector.gd").new()
		root.add_child(director)
		await process_frame
		var data := {"background": str(key), "keep_music": true, "steps": [{"type": "dialogue", "lines": [
			{"speaker": "Elder Theron", "text": "Backdrop: %s" % key, "portrait": "theron", "theme": "elder"}]}]}
		director.play_cutscene_from_data("shot_%s" % key, data)
		for _i in 30:
			await process_frame
		var shown: bool = director._background_texture.visible and director._background_texture.texture != null
		if not shown:
			print("[shot] REFUSED %s: the director showed no backdrop texture" % key)
			failed += 1
		else:
			await _save("%s/%s.png" % [out_dir, key])
		director.queue_free()
		await process_frame
	print("[shot] done: %d keys, %d without a backdrop" % [keys.size(), failed])
	quit(1 if failed > 0 else 0)


func _save(path: String) -> void:
	await process_frame
	var img := root.get_viewport().get_texture().get_image()
	if img == null:
		push_error("no viewport image for %s" % path)
		return
	var err := img.save_png(path)
	print("[shot] SCREEN saved %s (%dx%d) err=%d" % [path, img.get_width(), img.get_height(), err])
