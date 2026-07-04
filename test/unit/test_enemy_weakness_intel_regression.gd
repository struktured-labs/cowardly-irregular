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


func _enemy(mtype: String, weaks: Array) -> Combatant:
	var c := Combatant.new()
	autofree(c)
	c.combatant_name = "Foe"
	if mtype != "":
		c.set_meta("monster_type", mtype)
	var typed: Array[String] = []
	for w in weaks:
		typed.append(str(w))
	c.elemental_weaknesses = typed
	return c


func _hint(enemy: Combatant) -> String:
	var uim = UIM.new(null)
	return uim._weakness_hint(enemy)


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
