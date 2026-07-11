extends GutTest

## Audit ratchet (deploy-smoke find 2026-07-10): QuestLog queried the
## never-defined action "ui_back" — Godot errors on EVERY keypress while
## the log is open and the branch is silently dead input. Any literal
## action name referenced anywhere in src/ must exist in the InputMap
## (project actions + ui_* builtins are all registered at runtime).

const ACTION_CALL := "(?:is_action_(?:just_)?(?:pressed|released)|action_press|action_release|get_action_strength|is_action)\\s*\\(\\s*\"([^\"]+)\""


func test_every_literal_action_reference_resolves() -> void:
	var rx := RegEx.create_from_string(ACTION_CALL)
	var offenders: Dictionary = {}
	for path in _gd_files("res://src"):
		var src := FileAccess.get_file_as_string(path)
		for m in rx.search_all(src):
			var action := m.get_string(1)
			if InputMap.has_action(action):
				continue
			# Guarded-optional pattern is legal: InputMap.has_action("x") and is_action_pressed("x") w/ fallback (RebalanceReviewPanel).
			if src.contains("has_action(\"%s\")" % action):
				continue
			offenders[action] = path
	assert_eq(offenders.size(), 0,
		"undefined InputMap actions referenced (action → first file): %s" % str(offenders))


func _gd_files(root: String) -> Array:
	var out: Array = []
	var dirs: Array = [root]
	while dirs.size() > 0:
		var d: String = dirs.pop_back()
		var dir := DirAccess.open(d)
		if dir == null:
			continue
		dir.list_dir_begin()
		var f := dir.get_next()
		while f != "":
			var p := d + "/" + f
			if dir.current_is_dir():
				dirs.append(p)
			elif f.ends_with(".gd"):
				out.append(p)
			f = dir.get_next()
	return out
