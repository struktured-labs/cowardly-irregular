extends GutTest

## Display-polish regression (2026-07-09): two raw-id leaks in player-facing
## text. (1) The victory screen's level-up payoff joined RAW ability ids —
## "Learned: fira, blizzara" instead of "Learned: Fira, Blizzara". (2) The
## bestiary showed lowercase element ids ("Weak: fire") while the battle UI
## capitalizes ("Weak: Fire"). Pins name resolution in both.


func test_victory_screen_resolves_ability_names() -> void:
	var src := FileAccess.get_file_as_string("res://src/battle/BattleResultsDisplay.gd")
	assert_true("JobSystem.get_ability(str(aid))" in src,
		"learned-abilities line must resolve ids through JobSystem")
	assert_false("\", \".join(PackedStringArray(learned))" in src,
		"the raw-id join must not return")
	# The resolution path itself: a real ability id resolves to a display name.
	var ab: Dictionary = JobSystem.get_ability("fire")
	assert_false(ab.is_empty(), "sanity: 'fire' exists")
	assert_ne(str(ab.get("name", "")), "", "abilities carry display names to resolve to")


func test_bestiary_capitalizes_elements() -> void:
	var src := FileAccess.get_file_as_string("res://src/ui/BestiaryMenu.gd")
	assert_true("_caps(entry.weaknesses)" in src and "_caps(entry.resistances)" in src,
		"bestiary weak/resist lines route through the capitalizer")
	assert_true("func _caps(" in src, "helper exists")
