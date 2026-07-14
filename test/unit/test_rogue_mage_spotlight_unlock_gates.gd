extends GutTest

## tick 98 regression: rogue + mage spotlight cutscenes must trigger
## via _get_pending_story_cutscene so the corresponding PCs unlock
## manual control. Pre-fix, both cutscenes existed in data/cutscenes/
## and were referenced by _CUTSCENE_COMPLETION_FLAGS, but no code
## path actually played them — so Rogue and Mage stayed permanently
## autobattle-locked. Mirror of tick 97's cleric fix.

const GAME_LOOP := "res://src/GameLoop.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func _pending_cutscene_body() -> String:
	var src := _read(GAME_LOOP)
	var idx: int = src.find("func _get_pending_story_cutscene")
	assert_gt(idx, -1, "_get_pending_story_cutscene must exist")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	return src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)


func test_rogue_spotlight_returnable() -> void:
	var body := _pending_cutscene_body()
	assert_true(body.contains("return \"world1_spotlight_rogue_ch3\""),
		"_get_pending_story_cutscene must return world1_spotlight_rogue_ch3 — otherwise rogue stays autobattle-locked")


func test_mage_spotlight_returnable() -> void:
	var body := _pending_cutscene_body()
	assert_true(body.contains("return \"world1_spotlight_mage_ch3\""),
		"_get_pending_story_cutscene must return world1_spotlight_mage_ch3 — otherwise mage stays autobattle-locked")


func test_rogue_gate_uses_chapter3_complete_predicate() -> void:
	var body := _pending_cutscene_body()
	assert_true(body.contains("flags.get(\"cutscene_flag_chapter3_complete\", false) and not flags.get(\"cutscene_flag_spotlight_unlocked_rogue\", false)"),
		"rogue spotlight gate must check chapter3_complete + not unlocked_rogue — fires after the cave intro cutscene plays")


func test_mage_gate_chains_on_rogue_unlock() -> void:
	# Pin the chaining: mage gate predicate is rogue UNLOCKED. This
	# prevents both spotlights from stacking on a single cave entry
	# — mage waits for next visit after rogue plays.
	var body := _pending_cutscene_body()
	assert_true(body.contains("flags.get(\"cutscene_flag_spotlight_unlocked_rogue\", false) and not flags.get(\"cutscene_flag_spotlight_unlocked_mage\", false)"),
		"mage spotlight gate must chain on rogue UNLOCKED (not chapter flag) — sequences cleanly across map re-entries")


func test_both_gates_scoped_to_whispering_cave() -> void:
	var body := _pending_cutscene_body()
	for cutscene_id in ["world1_spotlight_rogue_ch3", "world1_spotlight_mage_ch3"]:
		var idx: int = body.find("return \"" + cutscene_id + "\"")
		assert_gt(idx, -1, "%s return must exist" % cutscene_id)
		# Look back ~150 chars for the map gate.
		var window_start: int = max(0, idx - 150)
		var window: String = body.substr(window_start, idx - window_start)
		assert_true(window.contains("_current_map_id == \"whispering_cave\""),
			"%s must be gated on whispering_cave — story comment says both PCs unlock in the cave" % cutscene_id)


func test_rogue_gate_precedes_mage_gate_in_source() -> void:
	# Ordering: rogue check must come BEFORE mage check so the rogue
	# unlock can predicate the mage gate. If they swap, mage never
	# fires (rogue-unlocked is false at the time of mage check).
	var body := _pending_cutscene_body()
	var rogue_idx: int = body.find("return \"world1_spotlight_rogue_ch3\"")
	var mage_idx: int = body.find("return \"world1_spotlight_mage_ch3\"")
	assert_gt(rogue_idx, -1, "rogue spotlight return must exist")
	assert_gt(mage_idx, -1, "mage spotlight return must exist")
	assert_lt(rogue_idx, mage_idx,
		"rogue gate must precede mage gate in source — otherwise the mage chain on rogue unlock never resolves correctly")


func test_both_cutscene_files_exist_and_embed_battles() -> void:
	# Tick 471 architecture: unlock flag now written by
	# GameLoop._on_battle_ended on battle_won, not by a set_flag
	# cutscene step. Both cutscenes must embed a "battle" step
	# targeting their PC so the engine has something to fight.
	for entry in [
		["res://data/cutscenes/world1_spotlight_rogue_ch3.json", "rogue"],
		["res://data/cutscenes/world1_spotlight_mage_ch3.json",  "mage"],
	]:
		var path: String = entry[0]
		var pc: String = entry[1]
		assert_true(FileAccess.file_exists(path), "%s must exist" % path)
		var raw: String = FileAccess.get_file_as_string(path)
		var parsed: Variant = JSON.parse_string(raw)
		assert_true(parsed is Dictionary)
		var steps: Variant = (parsed as Dictionary).get("steps", [])
		assert_true(steps is Array)
		var found_battle: bool = false
		for step in steps:
			if step is Dictionary and str((step as Dictionary).get("type", "")) == "battle":
				var combatants: Variant = (step as Dictionary).get("combatants", [])
				if combatants is Array and pc in (combatants as Array):
					found_battle = true
					break
		assert_true(found_battle,
			"%s must embed a `type:battle` step with combatants:[\"%s\"] — engine writes unlock flag on battle_won" % [path, pc])


func test_cleric_gate_still_present() -> void:
	# Don't regress tick 97's cleric gate while adding rogue + mage.
	var body := _pending_cutscene_body()
	assert_true(body.contains("return \"world1_spotlight_cleric_ch1\""),
		"cleric spotlight gate from tick 97 must still be present")
