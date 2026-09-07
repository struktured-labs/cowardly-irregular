extends GutTest

## Feature 2026-07-04: the equipment compare preview showed only stat_mods
## deltas — so an item's special_effects (the 1800-gold Flame Sword's fire
## damage bonus, crit bonus, on-hit procs) were invisible when comparing gear.
## EquipmentMenu now appends a compact "✦ Fire Dmg" summary to the stat line.
## Helpers _special_effects_summary / _humanize_special_effect are pure.

const EM := preload("res://src/ui/EquipmentMenu.gd")


func _menu() -> EquipmentMenu:
	var m: EquipmentMenu = EM.new()
	autofree(m)  # not added to the tree — helpers are pure, no _ready needed
	return m


func test_humanize_damage_bonus() -> void:
	assert_eq(_menu()._humanize_special_effect("fire_damage_bonus"), "Fire Dmg")
	assert_eq(_menu()._humanize_special_effect("lightning_damage_bonus"), "Lightning Dmg")


func test_humanize_generic_bonus() -> void:
	assert_eq(_menu()._humanize_special_effect("critical_bonus"), "Critical")
	assert_eq(_menu()._humanize_special_effect("steal_bonus"), "Steal")


func test_summary_surfaces_special_effect() -> void:
	var summary := _menu()._special_effects_summary({"special_effects": {"fire_damage_bonus": 1.5}})
	assert_string_contains(summary, "✦", "a special-effects marker must be present")
	assert_string_contains(summary, "Fire Dmg", "the fire damage bonus must be named")


func test_summary_empty_when_no_special_effects() -> void:
	assert_eq(_menu()._special_effects_summary({"stat_mods": {"attack": 5}}), "",
		"an item with no special_effects yields no summary")
	assert_eq(_menu()._special_effects_summary({"special_effects": {}}), "",
		"an empty special_effects dict yields no summary")


func test_real_flame_sword_shows_fire() -> void:
	# End-to-end against the actual authored weapon, not a mock.
	var flame := EquipmentSystem.get_weapon("flame_sword")
	assert_false(flame.is_empty(), "flame_sword must exist")
	assert_string_contains(_menu()._special_effects_summary(flame), "Fire Dmg",
		"the real Flame Sword's fire bonus must surface in the compare preview")
