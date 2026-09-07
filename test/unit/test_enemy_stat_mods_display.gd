extends GutTest

## Feature 2026-07-05: the enemy battle panel showed name/AP/HP/status/intel but
## NOT the enemy's active stat buffs/debuffs — so a player couldn't confirm their
## attack-down / defense-down actually landed or how long it had left. The panel
## now appends a compact " · ATK-30%(2)" readout (buffs aqua, debuffs penalty
## color), mirroring the party stat-mod display. Shown only when the enemy has
## active multipliers.

const UIM := preload("res://src/battle/BattleUIManager.gd")


func _hint(enemy: Combatant) -> String:
	return UIM.new(null)._enemy_stat_mods_hint(enemy)


func _enemy() -> Combatant:
	var c := Combatant.new()
	autofree(c)
	c.combatant_name = "Foe"
	return c


func test_no_mods_is_blank() -> void:
	assert_eq(_hint(_enemy()), "", "an enemy with no buffs/debuffs shows nothing")


func test_debuff_is_surfaced_with_turns() -> void:
	var e := _enemy()
	e.add_debuff("weaken", "attack", 0.7, 2)
	var h := _hint(e)
	assert_string_contains(h, "ATK-30%", "an attack-down debuff shows the stat + magnitude")
	assert_string_contains(h, "(2)", "the remaining-turn count is shown")
	assert_string_starts_with(h, " · ", "the readout is separated from the rest of the panel line")


func test_buff_is_surfaced() -> void:
	var e := _enemy()
	e.add_buff("bless", "defense", 1.5, 3)
	assert_string_contains(_hint(e), "DEF+50%", "an enemy defense buff is shown too")
