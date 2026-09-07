extends GutTest

## Mordaine-readiness pass 2026-07-16: three overworld NPC hint tiers
## keyed on `w1_boss_defeated` — a flag NOTHING sets (dead since the
## progression rework moved W2-unlock to Mordaine). Those post-endgame
## hint lines could never fire. Two rat-king tiers also still described
## "a portal appeared" when the Rat King now reveals the CASTLE (the
## portal is post-Mordaine). Flags swapped to world1_mordaine_defeated
## (resolves via is_story_flag_set's cutscene_flag_ prefix); wording
## realigned to the shipped progression.


func test_no_hint_keys_on_the_dead_flag() -> void:
	var src := FileAccess.get_file_as_string("res://src/exploration/OverworldScene.gd")
	# w1_boss_defeated must not appear as a hint gate anywhere — it has no setter.
	assert_eq(src.count("\"flag\": \"w1_boss_defeated\""), 0,
		"w1_boss_defeated is a dead flag (no setter) — hint tiers keyed on it never fire")


func test_post_mordaine_hints_use_the_live_flag() -> void:
	var src := FileAccess.get_file_as_string("res://src/exploration/OverworldScene.gd")
	assert_gte(src.count("\"flag\": \"world1_mordaine_defeated\""), 3,
		"post-endgame hint tiers must key on world1_mordaine_defeated — the flag Mordaine's defeat actually sets")


func test_rat_king_hints_describe_the_castle_not_a_portal() -> void:
	# The Rat King reveals Castle Harmonia; the W2 portal is post-Mordaine.
	var src := FileAccess.get_file_as_string("res://src/exploration/OverworldScene.gd")
	var i := src.find("\"flag\": \"rat_king_defeated\", \"text\": \"A strange light")
	assert_eq(i, -1,
		"the old rat-king 'portal appeared' hint contradicts the shipped progression (castle reveal)")
	assert_gte(src.count("castle"), 2,
		"rat-king hint tiers should point the player at the castle reveal")
