extends GutTest

## Feature 2026-07-04: the enemy panel showed name/AP/HP but no elemental
## weakness. Now, once you've DEFEATED a monster before (it's in the
## bestiary), its panel appends " · Weak: <elements>" — rewarding
## fighting + aiding autobattle/optimization planning ("you've beaten
## this, you know it's weak to fire"). Unfought monsters reveal nothing.

const UIM := preload("res://src/battle/BattleUIManager.gd")

var _saved_defeated: Dictionary = {}


func before_each() -> void:
	_saved_defeated = GameState.game_constants.get("defeated_monsters", {}).duplicate(true)
	GameState.game_constants["defeated_monsters"] = {}


func after_each() -> void:
	GameState.game_constants["defeated_monsters"] = _saved_defeated


func _enemy(mtype: String, weaks: Array, immunes: Array = [], resists: Array = []) -> Combatant:
	var c := Combatant.new()
	autofree(c)
	c.combatant_name = "Foe"
	if mtype != "":
		c.set_meta("monster_type", mtype)
	var tw: Array[String] = []
	for w in weaks:
		tw.append(str(w))
	c.elemental_weaknesses = tw
	var ti: Array[String] = []
	for im in immunes:
		ti.append(str(im))
	c.elemental_immunities = ti
	var tr: Array[String] = []
	for r in resists:
		tr.append(str(r))
	c.elemental_resistances = tr
	return c


func _hint(enemy: Combatant) -> String:
	var uim = UIM.new(null)
	return uim._enemy_intel_hint(enemy)


func test_defeated_monster_reveals_weakness() -> void:
	BestiarySystem.mark_defeated("slime")
	var e := _enemy("slime", ["fire"])
	var h := _hint(e)
	assert_string_contains(h, "Weak:", "a previously-defeated monster must show a weakness line")
	assert_string_contains(h, "Fire", "the weakness element must be named (capitalized)")


func test_unfought_monster_reveals_nothing() -> void:
	# goblin NOT marked defeated this test (before_each cleared the dict)
	var e := _enemy("goblin", ["ice"])
	assert_eq(_hint(e), "",
		"an unfought monster must give no weakness intel — you haven't earned it")


func test_defeated_but_no_weaknesses_is_blank() -> void:
	BestiarySystem.mark_defeated("bat")
	var e := _enemy("bat", [])
	assert_eq(_hint(e), "", "a monster with no authored weaknesses shows nothing even when defeated")


func test_missing_monster_type_meta_is_safe() -> void:
	var e := _enemy("", ["fire"])  # no monster_type meta
	assert_eq(_hint(e), "", "no monster_type meta → no crash, no hint")


func test_multiple_weaknesses_joined() -> void:
	BestiarySystem.mark_defeated("slime")
	var e := _enemy("slime", ["fire", "ice"])
	var h := _hint(e)
	assert_string_contains(h, "Fire, Ice", "multiple weaknesses must be comma-joined")


func test_defeated_monster_reveals_immunity() -> void:
	# Immunity is the higher-value intel (attacking it wastes a turn).
	BestiarySystem.mark_defeated("slime")
	var e := _enemy("slime", [], ["holy"])
	var h := _hint(e)
	assert_string_contains(h, "Immune: Holy",
		"a defeated monster's immunities must surface — don't waste a turn on 0x damage")


func test_weak_and_immune_both_shown() -> void:
	BestiarySystem.mark_defeated("slime")
	var e := _enemy("slime", ["fire"], ["ice"])
	var h := _hint(e)
	assert_string_contains(h, "Weak: Fire")
	assert_string_contains(h, "Immune: Ice")


func test_unfought_hides_immunity_too() -> void:
	var e := _enemy("goblin", [], ["dark"])
	assert_eq(_hint(e), "", "unfought monster reveals neither weakness nor immunity")


func test_defeated_monster_reveals_resistance() -> void:
	# Resistance (0.5x) is the low-priority third: worth avoiding, not fatal.
	BestiarySystem.mark_defeated("slime")
	var e := _enemy("slime", [], [], ["earth"])
	var h := _hint(e)
	assert_string_contains(h, "Resist: Earth",
		"a defeated monster's resistances must surface so you skip the 0.5x element")


func test_resistance_only_still_gated_on_defeat() -> void:
	# A monster with ONLY resistances (no weak/immune) must still hide when unfought.
	var e := _enemy("goblin", [], [], ["fire"])
	assert_eq(_hint(e), "", "resistance-only intel is still earned by defeating the monster")


func test_all_three_elemental_lines_shown() -> void:
	BestiarySystem.mark_defeated("slime")
	var e := _enemy("slime", ["fire"], ["ice"], ["earth"])
	var h := _hint(e)
	assert_string_contains(h, "Weak: Fire")
	assert_string_contains(h, "Immune: Ice")
	assert_string_contains(h, "Resist: Earth")
