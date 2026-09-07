extends GutTest

## Feature 2026-07-05: the autobattle grid editor's _short_target labeled only 5
## of 10 targets — weakest_to_ability (v3.33.4) plus 4 pre-existing ones
## (highest_speed_enemy, highest_atk_enemy, lowest_magic_defense_enemy,
## all_allies) fell through to raw snake_case in the grid cells. Now every
## AutobattleSystem.TARGET_TYPES entry renders a friendly short label.

const GE := preload("res://src/ui/autobattle/AutobattleGridEditor.gd")


func _short(target: String) -> String:
	var ed = GE.new()
	autofree(ed)
	return ed._short_target(target)


func test_exploit_weakness_has_friendly_label() -> void:
	assert_eq(_short("weakest_to_ability"), "Weak Foe", "the Exploit Weakness target needs a readable grid label")


func test_every_target_type_has_a_friendly_label() -> void:
	# Sync guard: no engine target may render as raw snake_case in the grid.
	for key in AutobattleSystem.TARGET_TYPES.keys():
		var label: String = _short(str(key))
		assert_ne(label, str(key),
			"target '%s' falls through to raw snake_case in the grid editor — add a _short_target label" % key)
