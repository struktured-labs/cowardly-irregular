extends GutTest

## Regression: every hint defined in TutorialHints.HINTS must have at least
## one trigger site somewhere in the codebase. Hints with no trigger are
## dead documentation — they exist in the catalog but a player will never
## see them. This test sweeps src/ for `TutorialHints.show(..., "<id>")`
## call sites and fails for any orphan id.
##
## Audit history when this lands (2026-05-25):
##   - movement, save_crystal previously had no trigger; wired into
##     OverworldScene._build_world() and SavePoint._on_body_entered().
##   - autobattle_intro remains untriggered intentionally (overlaps with
##     autobattle_toggle which already fires in BattleScene). If a future
##     trigger point exists, this test will pass without code change.
## NOTE: This test calls out autobattle_intro as the known exception so
## a future maintainer who wants to wire it doesn't get confused.

const HINTS_PATH := "res://src/ui/TutorialHints.gd"
const KNOWN_UNFIRED_EXCEPTIONS := {
	# autobattle_intro overlaps with autobattle_toggle which IS fired in
	# BattleScene. Either wire it from AutobattleGridEditor.setup() or
	# remove from the catalog. Tracked here so this test doesn't fail
	# loud-by-default while the decision is pending.
	"autobattle_intro": true,
}


func _read(path: String) -> String:
	var file = FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "file should exist: %s" % path)
	var text = file.get_as_text()
	file.close()
	return text


func _list_hint_ids() -> Array:
	# Pull all keys from the const HINTS dict by parsing the source. Going
	# through the live const would require instantiating TutorialHints
	# which is a class_name Node — overkill for a static catalog read.
	var text = _read(HINTS_PATH)
	var ids: Array = []
	var lines = text.split("\n")
	for line in lines:
		var stripped = line.strip_edges()
		# Hint entries are `"hint_id": {` on their own line inside HINTS.
		if stripped.ends_with(": {") and stripped.begins_with("\""):
			var end_quote = stripped.find("\"", 1)
			if end_quote > 1:
				ids.append(stripped.substr(1, end_quote - 1))
	return ids


func _grep_src_for_hint_trigger(hint_id: String) -> bool:
	# Recursively scan src/**/*.gd looking for a call of the form
	# TutorialHints.show(<anything>, "<hint_id>") — accepts any parent
	# expression (self, scene, get_tree().current_scene, etc.). Excludes
	# TutorialHints.gd itself so the catalog definition doesn't get
	# mistaken for a trigger site.
	return _scan_dir("res://src", hint_id)


func _scan_dir(dir_path: String, hint_id: String) -> bool:
	var dir = DirAccess.open(dir_path)
	if dir == null:
		return false
	dir.list_dir_begin()
	var name = dir.get_next()
	while name != "":
		if name.begins_with("."):
			name = dir.get_next()
			continue
		var full = dir_path + "/" + name
		if dir.current_is_dir():
			if _scan_dir(full, hint_id):
				return true
		elif name.ends_with(".gd") and name != "TutorialHints.gd":
			var f = FileAccess.open(full, FileAccess.READ)
			if f:
				var txt = f.get_as_text()
				f.close()
				# Walk every occurrence of the quoted hint id and check
				# whether it's an argument to a TutorialHints.show( call
				# (i.e. preceded by `TutorialHints.show(` within ~120 chars).
				var quoted = "\"" + hint_id + "\""
				var idx = txt.find(quoted)
				while idx > -1:
					var window_start = maxi(0, idx - 120)
					var window = txt.substr(window_start, idx - window_start)
					if window.find("TutorialHints.show(") > -1:
						return true
					idx = txt.find(quoted, idx + 1)
		name = dir.get_next()
	return false


func test_movement_hint_fires_from_overworld_scene() -> void:
	var overworld = _read("res://src/exploration/OverworldScene.gd")
	assert_true(overworld.find("TutorialHints.show(self, \"movement\")") > -1,
		"OverworldScene must fire the movement hint on first overworld entry")


func test_save_crystal_hint_fires_from_save_point() -> void:
	var save_point = _read("res://src/exploration/SavePoint.gd")
	assert_true(save_point.find("TutorialHints.show(self, \"save_crystal\")") > -1,
		"SavePoint must fire the save_crystal hint when player first enters the zone")


func test_no_orphan_tutorial_hints_outside_known_exceptions() -> void:
	# Catalog sweep: every defined hint id must have a trigger somewhere
	# in src/, unless explicitly exempted in KNOWN_UNFIRED_EXCEPTIONS.
	# This catches future drift — if someone adds a hint to the catalog
	# but forgets the trigger, this test screams.
	var ids = _list_hint_ids()
	assert_true(ids.size() >= 10, "Expected at least ~10 hints in catalog, got: %d" % ids.size())
	for id in ids:
		if KNOWN_UNFIRED_EXCEPTIONS.has(id):
			continue
		# Trigger sites pass a parent Node followed by the hint id. The parent
		# might be `self`, a captured `scene` var, or `get_tree().current_scene`
		# depending on where the call lives, so we just look for the id literal
		# bound to a TutorialHints.show( call. Two-line scan accepts both
		# single-line and split-line forms.
		var needle = "\"" + id + "\")"
		assert_true(_grep_src_for_hint_trigger(id),
			"Hint '%s' has no TutorialHints.show(...) trigger in src/. Either wire it OR add to KNOWN_UNFIRED_EXCEPTIONS." % id)
