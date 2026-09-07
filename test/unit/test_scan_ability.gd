extends GutTest

## Feature 2026-07-05: Scan (Rogue support ability, effect="scan") reveals a live
## enemy's elemental intel for the rest of the battle — the in-the-moment
## counterpart to the bestiary's defeat-gated reveal. _execute_scan_effect sets
## an intel_revealed meta on each live target; BattleUIManager._enemy_intel_hint
## now shows Weak/Immune/Resist when that meta is set OR the monster was
## previously defeated. This is the capstone of the elemental-intel arc: you no
## longer have to KILL a monster once before you can read it.

const UIM := preload("res://src/battle/BattleUIManager.gd")

var _saved_defeated: Dictionary = {}
var _saved_seen: Dictionary = {}


func before_each() -> void:
	_saved_defeated = GameState.game_constants.get("defeated_monsters", {}).duplicate(true)
	_saved_seen = GameState.game_constants.get("seen_monsters", {}).duplicate(true)
	GameState.game_constants["defeated_monsters"] = {}
	GameState.game_constants["seen_monsters"] = {}


func after_each() -> void:
	GameState.game_constants["defeated_monsters"] = _saved_defeated
	GameState.game_constants["seen_monsters"] = _saved_seen


func _enemy(mtype: String, weaks: Array) -> Combatant:
	var c := Combatant.new()
	autofree(c)
	c.combatant_name = "Foe"
	c.set_meta("monster_type", mtype)
	var tw: Array[String] = []
	for w in weaks:
		tw.append(str(w))
	c.elemental_weaknesses = tw
	return c


func _caster() -> Combatant:
	var c := Combatant.new()
	autofree(c)
	c.combatant_name = "Rogue"
	return c


func test_scan_sets_intel_revealed_meta() -> void:
	var e := _enemy("slime", ["fire"])
	BattleManager._execute_scan_effect(_caster(), [e])
	assert_true(e.get_meta("intel_revealed", false), "scan must flag the target as revealed")


func test_scanned_enemy_shows_intel_without_prior_defeat() -> void:
	# The payoff: intel appears mid-battle for a monster you've NEVER defeated.
	var e := _enemy("slime", ["fire"])
	assert_eq(UIM.new(null)._enemy_intel_hint(e), "",
		"precondition: an unfought, unscanned monster reveals nothing")
	BattleManager._execute_scan_effect(_caster(), [e])
	assert_string_contains(UIM.new(null)._enemy_intel_hint(e), "Weak: Fire",
		"after scan, the enemy's weakness must surface even with no prior defeat")


func test_scan_marks_monster_seen() -> void:
	var e := _enemy("slime", ["fire"])
	BattleManager._execute_scan_effect(_caster(), [e])
	assert_true(BestiarySystem.is_seen("slime"), "scanning a monster records it as seen")


func test_dead_target_not_scanned() -> void:
	var e := _enemy("slime", ["fire"])
	e.is_alive = false
	BattleManager._execute_scan_effect(_caster(), [e])
	assert_false(e.get_meta("intel_revealed", false), "a dead target isn't scanned")


func test_scan_ability_resolves_and_in_rogue_kit() -> void:
	var ability: Dictionary = JobSystem.get_ability("scan")
	assert_false(ability.is_empty(), "scan must resolve in JobSystem")
	assert_eq(str(ability.get("effect", "")), "scan", "scan carries effect=scan (routes to _execute_scan_effect)")
	var rogue: Dictionary = JobSystem.get_job("rogue")
	assert_true("scan" in rogue.get("abilities", []), "scan is in the Rogue kit")
