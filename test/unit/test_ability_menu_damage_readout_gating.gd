extends GutTest

## Bugfix 2026-07-05: the ability→enemy submenu showed "~N dmg" (and, since
## v3.33.10, a bogus "[KILL]") for NON-damaging single_enemy support abilities —
## steal, taunt, web_shot, scan, ~24 in all — because estimate_ability_damage
## falls back to power=10 when an ability authors no damage. The readout is now
## gated on _ability_deals_damage: true only for physical/magic or an explicit
## positive damage figure.

const BCM := preload("res://src/battle/BattleCommandMenu.gd")


func _deals(ability: Dictionary) -> bool:
	return BCM.new(null)._ability_deals_damage(ability)


func test_physical_and_magic_deal_damage() -> void:
	assert_true(_deals({"type": "physical"}), "physical abilities deal damage")
	assert_true(_deals({"type": "magic"}), "magic abilities deal damage")


func test_support_debuff_deals_no_damage() -> void:
	assert_false(_deals({"type": "support", "effect": "speed_down"}),
		"a debuff must not advertise a damage estimate")


func test_null_power_is_not_damage() -> void:
	# JSON carries "power": null for non-damaging abilities — must not count.
	assert_false(_deals({"type": "support", "power": null}))


func test_explicit_positive_damage_counts() -> void:
	assert_true(_deals({"type": "summon", "damage_multiplier": 1.5}),
		"a summon with a real damage multiplier still shows an estimate")


func test_real_scan_and_steal_are_nondamaging() -> void:
	for aid in ["scan", "steal", "taunt", "web_shot"]:
		var ab: Dictionary = JobSystem.get_ability(aid)
		assert_false(ab.is_empty(), "%s must resolve in JobSystem" % aid)
		assert_false(_deals(ab), "%s is a utility/debuff — no damage readout" % aid)


func test_real_fire_is_damaging() -> void:
	assert_true(_deals(JobSystem.get_ability("fire")), "fire deals damage — keeps its estimate")


func test_label_build_is_gated_in_source() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/battle/BattleCommandMenu.gd")
	assert_string_contains(src, "if _ability_deals_damage(ability):",
		"the enemy-target damage readout must be gated on _ability_deals_damage")
