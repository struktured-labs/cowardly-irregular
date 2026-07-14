extends GutTest

## Copy audit 2026-07-03: every battle end told gamepad players to
## "Press ENTER" — keyboard-only copy in a controller-first game
## (CLAUDE.md: designed for SNES-style gamepad, no mouse required).
## The established convention is the dialogue-box style
## "Z / A / Click to continue...". This bans the keyboard-only form
## from shipping strings.


func _scan(dir_path: String, hits: Array) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		var full := dir_path + "/" + f
		if dir.current_is_dir() and not f.begins_with("."):
			_scan(full, hits)
		elif f.ends_with(".gd"):
			var src := FileAccess.get_file_as_string(full)
			# string literals only — comments may reference the old copy
			if src.contains("\"Press ENTER") or src.contains("Press ENTER to"):
				for line in src.split("\n"):
					if line.contains("Press ENTER") and not line.strip_edges().begins_with("#") \
							and not line.strip_edges().begins_with("##"):
						hits.append("%s: %s" % [full, line.strip_edges().left(80)])
		f = dir.get_next()


func test_no_keyboard_only_advance_prompts() -> void:
	var hits: Array = []
	_scan("res://src", hits)
	assert_eq(hits.size(), 0,
		"keyboard-only 'Press ENTER' copy in a controller-first game: %s" % str(hits))
