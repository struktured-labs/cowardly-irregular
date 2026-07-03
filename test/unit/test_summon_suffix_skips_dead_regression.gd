extends GutTest

## Mid-battle summoned monsters used to count DEAD same-type enemies toward
## the suffix slot ("Slime A, Slime B (dead), Slime C → next summon = D").
## Result: live roster reads as A, C, D after a kill — confusing for the
## player and for any UI keyed on the name. Fix: only alive same-type enemies
## consume a suffix slot. 2026-07-03: superseded by first-free-letter naming
## (pick_summon_name — see test_summon_name_collision_regression) which keeps
## the alive-only property; these pins now anchor on the collector loop.

const BATTLE_SCENE_PATH := "res://src/battle/BattleScene.gd"

const ANCHOR := "letter must be unique among LIVING same-types"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func test_summon_suffix_counter_filters_on_is_alive() -> void:
	var text := _read(BATTLE_SCENE_PATH)
	var idx := text.find(ANCHOR)
	assert_gt(idx, -1, "the living-names collector comment must anchor the fix")
	var window := text.substr(idx, 320)
	assert_true(window.contains("e.is_alive"),
		"summon naming loop must filter on e.is_alive — dead enemies must not consume a suffix letter")
	assert_true(window.contains("is_instance_valid(e)"),
		"loop must also guard with is_instance_valid so a freed combatant doesn't crash the count")


func test_legacy_dead_counting_path_is_gone() -> void:
	var text := _read(BATTLE_SCENE_PATH)
	var idx := text.find(ANCHOR)
	var rest := text.substr(idx, 400)
	var lines := rest.split("\n")
	var saw_meta_check := false
	var saw_alive_check := false
	for line in lines:
		var s: String = str(line).strip_edges()
		if s.begins_with("#"):
			continue
		if s.contains("get_meta(\"monster_type\""):
			saw_meta_check = true
		if s.contains("is_alive"):
			saw_alive_check = true
	assert_true(saw_meta_check and saw_alive_check,
		"summon naming loop must combine the meta lookup with is_alive in the live code (not just the comment)")
