extends GutTest
## Demo playthrough 2026-11-03: the battle party panel read "ATK+220 DEF+80" on a Fighter whose ATK was 19 —
## the raw x10-unit stat_mods table, not what recalculate_stats actually adds. Every readout uses the applied delta.

func _fighter(weapon: String) -> Combatant:
	var c := Combatant.new()
	add_child_autofree(c)
	JobSystem.assign_job(c, "fighter")
	EquipmentSystem.equip_weapon(c, weapon)
	c.recalculate_stats()
	return c

func test_applied_attack_bonus_is_what_the_stat_gains() -> void:
	var c := _fighter("war_axe")
	var with_gear: int = c.attack
	var applied: int = int(EquipmentSystem.get_applied_equipment_mods(c).get("attack", 0))
	EquipmentSystem.unequip_slot(c, EquipmentSystem.EquipSlot.WEAPON)
	c.recalculate_stats()
	assert_eq(applied, with_gear - c.attack, "the shown ATK bonus is exactly what the axe adds")
	assert_lt(applied, 220, "not the raw authored 220")

func test_battle_panel_label_uses_applied_mods() -> void:
	var src := FileAccess.get_file_as_string("res://src/battle/BattleUIManager.gd")
	assert_true(src.contains("EquipmentSystem.get_applied_equipment_mods(member)"))
