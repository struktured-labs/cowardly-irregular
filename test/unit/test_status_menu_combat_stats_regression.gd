extends GutTest

## The status screen's Combat Stats block did not report the numbers combat uses.
## Multipliers were formatted with "%.0f", so Iron Skin's 1.25 defense and Glass
## Cannon's 0.6 defense both rendered as "1x", and 1.8 rendered as "2x".
## Crit Chance showed only the passive bonus (0% with nothing equipped) while
## battle crits from a 5% base plus speed plus gear. Evasion ignored equipment
## evasion_bonus, so an Elven Cloak read as 0% dodge.

const SM := preload("res://src/ui/StatusMenu.gd")
const CombatantScript := preload("res://src/battle/Combatant.gd")


func _member(name_str: String) -> Combatant:
	var c: Combatant = CombatantScript.new()
	c.combatant_name = name_str
	c.base_speed = 10
	c.speed = 10
	add_child_autofree(c)
	return c


func _lines(c: Combatant) -> Array:
	var menu: StatusMenu = SM.new()
	add_child_autofree(menu)
	menu.character = c
	var panel: Control = menu._create_stats_panel(Vector2(320, 480))
	add_child_autofree(panel)
	var found: Array = []
	_collect(panel, found)
	return found


func _collect(n: Node, found: Array) -> void:
	if n is Label:
		found.append((n as Label).text)
	for child in n.get_children():
		_collect(child, found)


func _line(lines: Array, prefix: String) -> String:
	for text in lines:
		if str(text).begins_with(prefix):
			return str(text)
	return ""


func test_fractional_multipliers_keep_their_decimals() -> void:
	var glass := _member("Glass")
	assert_true(PassiveSystem.equip_passive(glass, "glass_cannon"), "glass_cannon must equip")
	var glass_lines := _lines(glass)
	assert_eq(_line(glass_lines, "Attack Mult"), "Attack Mult: 1.8x",
		"1.8 attack must not round up to 2x — got %s" % str(glass_lines))
	assert_eq(_line(glass_lines, "Magic Mult"), "Magic Mult: 1.8x",
		"1.8 magic must not round up to 2x — got %s" % str(glass_lines))
	assert_eq(_line(glass_lines, "Defense Mult"), "Defense Mult: 0.6x",
		"0.6 defense must not round up to 1x — got %s" % str(glass_lines))

	var tank := _member("Tank")
	assert_true(PassiveSystem.equip_passive(tank, "iron_skin"), "iron_skin must equip")
	var tank_lines := _lines(tank)
	assert_eq(_line(tank_lines, "Defense Mult"), "Defense Mult: 1.25x",
		"Iron Skin's 1.25 defense must not round down to 1x — got %s" % str(tank_lines))


func test_unmodified_multiplier_stays_a_whole_number() -> void:
	var bare := _member("Bare")
	var lines := _lines(bare)
	assert_eq(_line(lines, "Attack Mult"), "Attack Mult: 1x",
		"a 1.0 multiplier stays '1x' — got %s" % str(lines))


func test_crit_line_matches_the_battle_chance() -> void:
	var c := _member("Blade")
	c.equipped_weapon = "assassin_blade"
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	assert_not_null(bm, "BattleManager autoload must be present")
	var chance := float(bm._calculate_crit_chance(c))
	assert_gt(chance, 0.05, "assassin blade plus speed must beat the 5% base — the control that the battle formula moved")
	var lines := _lines(c)
	var expected := "Crit Chance: %d%%" % int(roundf(chance * 100.0))
	assert_eq(_line(lines, "Crit Chance"), expected,
		"status crit must be the battle chance (%s), not the passive-only bonus — got %s" % [expected, str(lines)])


func test_evasion_line_includes_equipment() -> void:
	var c := _member("Cloak")
	c.equipped_accessory = "elven_cloak"
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	assert_not_null(bm, "BattleManager autoload must be present")
	var equip := float(bm._sum_equipment_special_effect(c, "evasion_bonus"))
	assert_almost_eq(equip, 0.1, 0.0001, "elven_cloak must still author a 0.1 evasion_bonus")
	# Passive roll, then equipment roll — the same order _target_dodges_physical uses.
	var passive := 0.0
	var standing := passive + (1.0 - passive) * clampf(equip, 0.0, 0.50)
	var lines := _lines(c)
	var expected := "Evasion: %d%%" % int(roundf(standing * 100.0))
	assert_eq(_line(lines, "Evasion"), expected,
		"an Elven Cloak must show on the evasion line (%s), not as 0%% — got %s" % [expected, str(lines)])


func test_evasion_line_stacks_passive_and_equipment_as_two_rolls() -> void:
	var c := _member("Both")
	assert_true(PassiveSystem.equip_passive(c, "evasion_up"), "evasion_up must equip")
	c.equipped_accessory = "elven_cloak"
	var mods: Dictionary = PassiveSystem.get_passive_mods(c)
	var passive := clampf(float(mods.get("evasion", 0.0)), 0.0, 0.50)
	assert_almost_eq(passive, 0.2, 0.0001, "evasion_up must still be a 0.2 dodge")
	var equip := 0.1
	# Adding the two percents would print 30. Battle rolls them separately, so the chance of either is 28.
	var standing := passive + (1.0 - passive) * equip
	var lines := _lines(c)
	var expected := "Evasion: %d%%" % int(roundf(standing * 100.0))
	assert_eq(_line(lines, "Evasion"), expected,
		"passive 20%% then a 10%% cloak is %s, not 20%% and not 30%% — got %s" % [expected, str(lines)])
