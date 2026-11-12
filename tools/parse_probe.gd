extends SceneTree

## The driver for tools/parse_probe.py: load each script named after `--` WITH the project's autoloads present.
## The autoload names (JobSystem, GameState, ...) exist only once the tree has started, so this waits two frames before
## it compiles anything; a bare `--check-only` has none of them and fails a healthy BattleScene.gd.


func _init() -> void:
	await process_frame
	await process_frame
	for path in OS.get_cmdline_user_args():
		var res: String = path if path.begins_with("res://") else "res://" + path
		var script = load(res)
		var ok: bool = script is GDScript and (script as GDScript).can_instantiate()
		print("[PARSE] %s %s" % [res, "OK" if ok else "FAILED"])
	print("[PARSE] done")
	quit(0)
