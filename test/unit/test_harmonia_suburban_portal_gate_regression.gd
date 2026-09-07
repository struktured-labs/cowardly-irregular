extends GutTest

## Dead-flag sweep 2026-07-16: HarmoniaVillage's in-village Suburban
## portal ("Strange Device") was gated on w1_boss_defeated — a flag with
## NO setter since the progression rework moved W2-unlock to Mordaine.
## The portal could NEVER spawn. The overworld WorldPortal got the
## tick-278 fix; this sibling gate was missed. Now mirrors the overworld
## gate exactly (is_world_unlocked(2) OR cutscene_flag_world1_mordaine_defeated).


func test_village_portal_gate_uses_live_flags() -> void:
	var src := FileAccess.get_file_as_string("res://src/maps/villages/HarmoniaVillage.gd")
	# Target CODE consumption forms only — the fix's own comment may name the flag.
	assert_eq(src.count("is_story_flag_set(\"w1_boss_defeated\")"), 0,
		"w1_boss_defeated has no setter — any gate on it is permanently closed")
	assert_eq(src.count("\"flag\": \"w1_boss_defeated\""), 0,
		"no hint tier may key on the dead flag either")
	var i := src.find("SuburbanPortal")
	assert_gt(i, -1)
	var window := src.substr(maxi(0, i - 600), 800)
	assert_true("is_world_unlocked(2)" in window,
		"village portal gate must mirror the overworld WorldPortal gate")
	assert_true("cutscene_flag_world1_mordaine_defeated" in window,
		"village portal gate must accept the flag Mordaine's defeat actually sets")


func test_overworld_and_village_portal_gates_agree() -> void:
	# Both W2 portals must open on the same condition — split-brain gates
	# strand the player at whichever portal kept the stale flag.
	var village := FileAccess.get_file_as_string("res://src/maps/villages/HarmoniaVillage.gd")
	var overworld := FileAccess.get_file_as_string("res://src/exploration/OverworldScene.gd")
	var gate := "is_world_unlocked(2) or gs.game_constants.get(\"cutscene_flag_world1_mordaine_defeated\", false)"
	assert_true(gate in village, "village gate must use the canonical condition")
	assert_true(gate in overworld, "overworld gate must use the canonical condition")
