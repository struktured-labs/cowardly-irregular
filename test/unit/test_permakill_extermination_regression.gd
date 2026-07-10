extends GutTest

## Permakill's second promise (2026-07-09): the tooltip said 'cannot be
## encountered again' but nothing persisted — permakilled species respawned
## forever. Now: the species lands in GameState.permakilled_monster_types
## (typed-array save-coerced, New-Game-cleared), encounter draws filter it,
## and a fully exterminated pool grants a free pass instead of an empty
## battle.

var _saved: Array[String] = []


func before_each() -> void:
	_saved = GameState.permakilled_monster_types.duplicate()
	GameState.permakilled_monster_types.clear()


func after_each() -> void:
	GameState.permakilled_monster_types.clear()
	for x in _saved:
		GameState.permakilled_monster_types.append(x)


func test_permakill_records_the_species() -> void:
	var caster := Combatant.new()
	add_child_autofree(caster)
	caster.initialize({"name": "Nec", "max_hp": 50, "max_mp": 99, "attack": 5, "defense": 5, "magic": 30, "speed": 10})
	var victim := Combatant.new()
	add_child_autofree(victim)
	victim.initialize(EncounterSystem._create_enemy_data("slime"))
	victim.set_meta("monster_type", "slime")

	BattleManager._execute_meta_ability(caster,
		{"id": "permakill", "meta_effect": "permanent_death", "corruption_risk": 0.5}, [victim])

	assert_false(victim.is_alive, "the victim dies")
	assert_true("slime" in GameState.permakilled_monster_types, "the SPECIES is recorded")
	# idempotent — a second cast doesn't duplicate
	var victim2 := Combatant.new()
	add_child_autofree(victim2)
	victim2.initialize(EncounterSystem._create_enemy_data("slime"))
	victim2.set_meta("monster_type", "slime")
	BattleManager._execute_meta_ability(caster,
		{"id": "permakill", "meta_effect": "permanent_death", "corruption_risk": 0.5}, [victim2])
	assert_eq(GameState.permakilled_monster_types.count("slime"), 1, "no duplicate entries")


func test_encounter_draws_exclude_exterminated_species() -> void:
	GameState.permakilled_monster_types.append("slime")
	var filtered: Array = EncounterSystem._filter_permakilled(["slime", "bat", "goblin"])
	assert_false("slime" in filtered, "exterminated species filtered from draws")
	assert_eq(filtered.size(), 2, "survivors remain")
	assert_eq(EncounterSystem._filter_permakilled(["slime"]).size(), 0,
		"fully exterminated pool draws empty (free pass upstream)")


func test_extermination_survives_save_and_dies_on_new_game() -> void:
	GameState.permakilled_monster_types.append("slime")
	var save: Dictionary = GameState.to_dict()
	# JSON round-trip: the generic-Array path the typed-array coercion guards
	var reloaded = JSON.parse_string(JSON.stringify(save))
	GameState.permakilled_monster_types.clear()
	GameState._apply_save_data(reloaded)
	assert_true("slime" in GameState.permakilled_monster_types,
		"extermination survives the JSON save round-trip (typed-array coercion)")
	GameState.reset_game_state()
	assert_true(GameState.permakilled_monster_types.is_empty(),
		"New Game resurrects the ecosystem (the reset-leak class)")
