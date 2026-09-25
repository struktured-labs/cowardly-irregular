extends GutTest

## Touching a field elite emits "<species>@elite". Encounter data scales that
## marker (3x HP, 8x EXP, 5x gold, and the rest of field_elites.json). The
## battle looked the id up in monsters.json, missed, and substituted a random
## hardcoded monster — so the rare never fought and never paid.

const MONSTERS := "res://data/monsters.json"


class SpawnHost:
	extends Node
	var encounter_enemies: Array = []
	var forced_enemies: Array = []
	var autogrind_enemy_data: Array = []
	var force_miniboss: bool = false
	var enemy_positions: Array = [0, 0, 0]
	var test_enemies: Array = []
	var _boss_dialogue_data = null

	func log_message(_message: String) -> void:
		pass

	func _update_ui() -> void:
		pass

	func _on_enemy_hp_changed(_old_value, _new_value, _enemy_idx) -> void:
		pass

	func _on_enemy_died(_enemy_idx) -> void:
		pass

	func _on_status_added(_status, _combatant) -> void:
		pass

	func _on_status_removed(_status, _combatant) -> void:
		pass

	func _on_status_tick_damage(_amount, _source, _target) -> void:
		pass

	func _on_status_tick_heal(_amount, _source, _target) -> void:
		pass


func _monsters() -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(MONSTERS))
	assert_true(parsed is Dictionary, "monsters.json must parse")
	return parsed


func _host() -> SpawnHost:
	var host := SpawnHost.new()
	add_child_autofree(host)
	return host


func _pin_party(gs: Node) -> Array:
	var saved: Array = gs.player_party.duplicate()
	var party: Array[Dictionary] = []
	for i in range(4):
		party.append({"name": "probe%d" % i, "job_level": 10})
	gs.player_party = party
	return saved


## The numbers the overworld comment says the fight is built from.
func _scaled_for_spawn(es: Node, species: String) -> Dictionary:
	var base: Dictionary = es._create_enemy_data(species)
	if bool(base.get("field_elite", false)):
		return base
	return es._apply_field_elite_scaling(base)


func test_a_promoted_elite_fights_and_pays_as_the_scaled_rare() -> void:
	var es: Node = get_tree().root.get_node_or_null("EncounterSystem")
	var gs: Node = get_tree().root.get_node_or_null("GameState")
	var bm: Node = get_tree().root.get_node_or_null("BattleManager")
	assert_not_null(es, "EncounterSystem autoload")
	assert_not_null(gs, "GameState autoload")
	assert_not_null(bm, "BattleManager autoload")
	if es == null or gs == null or bm == null:
		return

	var species := "brass_golem"
	var authored: Dictionary = _monsters()[species]
	var authored_hp := int(authored["stats"]["max_hp"])
	var authored_gold := int(authored.get("gold_reward", 0))
	var authored_exp := int(authored.get("exp_reward", 0))
	var saved: Array = _pin_party(gs)
	var scaled: Dictionary = _scaled_for_spawn(es, species)
	assert_gt(int(scaled.get("max_hp", 0)), authored_hp,
		"CONTROL: the elite table must raise HP above the catalog or this cannot see a drop")
	assert_gt(int(scaled.get("gold_reward", 0)), authored_gold, "CONTROL: elite gold is above the catalog")
	assert_gt(int(scaled.get("exp_reward", 0)), authored_exp, "CONTROL: elite EXP is above the catalog")
	assert_false((scaled.get("elemental_weaknesses", []) as Array).is_empty(),
		"CONTROL: brass_golem must author a weakness")

	var host := _host()
	host.encounter_enemies = [species + EncounterSystem.ELITE_SUFFIX]
	BattleEnemySpawner.new(host).spawn_encounter_enemies()
	assert_eq(host.test_enemies.size(), 1, "touching one elite must start one fight, not a random substitute")
	var enemy: Combatant = host.test_enemies[0]
	assert_eq(str(enemy.get_meta("monster_type", "")), species,
		"the fight substituted %s for the %s elite" % [str(enemy.get_meta("monster_type", "")), species])
	assert_eq(enemy.max_hp, int(scaled["max_hp"]),
		"elite HP %d; the table scales this species to %d" % [enemy.max_hp, int(scaled["max_hp"])])
	assert_eq(enemy.attack, int(scaled["attack"]),
		"elite attack %d; the table scales it to %d" % [enemy.attack, int(scaled["attack"])])
	assert_eq(enemy.magic_defense, int(scaled["magic_defense"]),
		"elite M.DEF %d; the table scales it to %d" % [enemy.magic_defense, int(scaled["magic_defense"])])
	assert_eq(enemy.elemental_weaknesses, scaled["elemental_weaknesses"],
		"the elite dropped its weaknesses %s" % str(scaled["elemental_weaknesses"]))
	assert_eq(enemy.elemental_resistances, scaled["elemental_resistances"],
		"the elite dropped its resistances %s" % str(scaled["elemental_resistances"]))
	assert_eq(int(enemy.get_meta("gold_reward", -1)), int(scaled["gold_reward"]),
		"the combatant kept catalog gold instead of the scaled rare payout")
	assert_eq(int(enemy.get_meta("exp_reward", -1)), int(scaled["exp_reward"]),
		"the combatant kept catalog EXP instead of the scaled rare payout")
	assert_eq(bm._authored_reward(enemy, es.monster_database, "gold_reward", 0), int(scaled["gold_reward"]),
		"victory gold still reads the catalog row (%d) for a scaled rare" % authored_gold)
	assert_eq(bm._authored_reward(enemy, es.monster_database, "exp_reward", 25), int(scaled["exp_reward"]),
		"victory EXP still reads the catalog row (%d) for a scaled rare" % authored_exp)
	gs.player_party = saved


func test_a_flagged_elite_is_scaled_once_not_twice() -> void:
	var es: Node = get_tree().root.get_node_or_null("EncounterSystem")
	var gs: Node = get_tree().root.get_node_or_null("GameState")
	assert_not_null(es)
	assert_not_null(gs)
	if es == null or gs == null:
		return
	var saved: Array = _pin_party(gs)
	var once: Dictionary = es._create_enemy_data("dark_knight")
	var twice: Dictionary = es._create_enemy_data("dark_knight" + EncounterSystem.ELITE_SUFFIX)
	assert_gt(int(twice.get("max_hp", 0)), int(once.get("max_hp", 0)),
		"CONTROL: feeding the suffix back into _create_enemy_data double-scales a flagged species")
	var host := _host()
	host.encounter_enemies = ["dark_knight" + EncounterSystem.ELITE_SUFFIX]
	BattleEnemySpawner.new(host).spawn_encounter_enemies()
	assert_eq(host.test_enemies.size(), 1, "the Dark Knight elite must be the fight")
	var enemy: Combatant = host.test_enemies[0]
	assert_eq(str(enemy.get_meta("monster_type", "")), "dark_knight",
		"monster_type must stay the catalog id so sprites and the bestiary still resolve")
	assert_eq(enemy.max_hp, int(once["max_hp"]),
		"Dark Knight elite HP %d; one application of the table is %d (the suffix path is %d)" % [enemy.max_hp, int(once["max_hp"]), int(twice["max_hp"])])
	gs.player_party = saved


func test_an_ordinary_encounter_is_not_elite_scaled() -> void:
	var es: Node = get_tree().root.get_node_or_null("EncounterSystem")
	assert_not_null(es)
	if es == null:
		return
	var authored_hp := int(_monsters()["brass_golem"]["stats"]["max_hp"])
	var host := _host()
	host.encounter_enemies = ["brass_golem"]
	BattleEnemySpawner.new(host).spawn_encounter_enemies()
	assert_eq(host.test_enemies.size(), 1, "an ordinary id must still spawn")
	var enemy: Combatant = host.test_enemies[0]
	assert_eq(enemy.max_hp, authored_hp,
		"an ordinary brass golem fought at %d HP; the catalog is %d" % [enemy.max_hp, authored_hp])
	assert_false(enemy.has_meta("gold_reward"),
		"an ordinary fight must keep paying the catalog gold, not an elite override")
	assert_eq(es._create_enemy_data("brass_golem").get("field_elite", false), false,
		"CONTROL: brass_golem is elite only when the spawn says so")
