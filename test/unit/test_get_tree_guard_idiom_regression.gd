extends GutTest

## Log-mining find 2026-07-03: `x if get_tree() else null` evaluates
## get_tree() as the CONDITION, and on a detached node that call itself
## prints "ERROR: Parameter data.tree is null" — the guard emits the
## noise it exists to suppress. Scenes configure controllers/players
## before add_child, so every village/cave/overworld load dumped engine
## errors that buried real ones. is_inside_tree() is the errorless
## equivalent. This ratchet bans the idiom from ever returning.

const BANNED := ["if get_tree() else", "if not get_tree():", "if get_tree():"]


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
			for pattern in BANNED:
				if src.contains(pattern):
					hits.append("%s: %s" % [full, pattern])
		f = dir.get_next()


func test_no_get_tree_truthiness_guards_in_src() -> void:
	var hits: Array = []
	_scan("res://src", hits)
	assert_eq(hits.size(), 0,
		"get_tree() used as a truthiness guard — it error-prints on detached nodes; use is_inside_tree(): %s" % str(hits))
