extends GutTest

## The bestiary prints monsters.json magic_defense. Encounter, boss, flat, and
## headless spawns rebuilt the combatant without that key, so Combatant fell
## back to defense/2 and spells hit a different monster than the codex describes.

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


func _codex_mdef(monster_id: String) -> int:
	var stats: Dictionary = _monsters()[monster_id]["stats"]
	return int(stats.get("magic_defense", int(stats.get("defense", 0) * 0.5)))


func _half_defense(monster_id: String) -> int:
	var stats: Dictionary = _monsters()[monster_id]["stats"]
	return int(int(stats.get("defense", 0)) * 0.5)


func _host() -> SpawnHost:
	var host := SpawnHost.new()
	add_child_autofree(host)
	return host


func _spell_damage(mdef: int, defense_val: int) -> int:
	var probe := Combatant.new()
	probe.max_hp = 99999
	probe.current_hp = probe.max_hp
	probe.defense = defense_val
	probe.magic_defense = mdef
	var dealt := probe.take_damage(400, true)
	probe.free()
	return dealt


func test_a_random_encounter_fights_the_codex_magic_defense() -> void:
	var authored := _codex_mdef("bat")
	var halved := _half_defense("bat")
	assert_ne(authored, halved,
		"CONTROL: bat's authored M.DEF must differ from defense/2 or this cannot see the drop")
	assert_ne(_spell_damage(authored, 50), _spell_damage(halved, 50),
		"CONTROL: those two M.DEF values must change spell damage")
	var host := _host()
	host.encounter_enemies = ["bat"]
	BattleEnemySpawner.new(host).spawn_encounter_enemies()
	assert_eq(host.test_enemies.size(), 1, "a bat encounter must spawn the bat")
	var bat: Combatant = host.test_enemies[0]
	assert_eq(bat.attack, int(_monsters()["bat"]["stats"]["attack"]),
		"CONTROL: attack must be the JSON value, not the hardcoded MONSTER_TYPES bat")
	assert_eq(bat.magic_defense, authored,
		"the fight's M.DEF is %d; the codex prints %d, so a spell hits a different bat than the entry" % [bat.magic_defense, authored])
	assert_eq(bat.take_damage(400, true), _spell_damage(authored, bat.defense),
		"spell damage must follow the codex M.DEF")


func test_a_forced_fight_fights_the_codex_magic_defense() -> void:
	var authored := _codex_mdef("ogre")
	var halved := _half_defense("ogre")
	assert_ne(authored, halved,
		"CONTROL: ogre's authored M.DEF must differ from defense/2 or this cannot see the drop")
	var host := _host()
	host.forced_enemies = ["ogre"]
	BattleEnemySpawner.new(host).spawn_forced_enemies()
	assert_eq(host.test_enemies.size(), 1, "a forced ogre must spawn")
	var ogre: Combatant = host.test_enemies[0]
	assert_eq(ogre.magic_defense, authored,
		"the boss-path ogre fights at M.DEF %d; the codex prints %d" % [ogre.magic_defense, authored])


func test_a_flat_spawn_keeps_an_explicit_magic_defense() -> void:
	var host := _host()
	BattleEnemySpawner.new(host).spawn_from_data([{
		"id": "probe",
		"name": "Probe",
		"max_hp": 500,
		"defense": 50,
		"magic_defense": 20,
		"attack": 10,
	}])
	assert_eq(host.test_enemies.size(), 1, "a flat enemy dict must spawn")
	var enemy: Combatant = host.test_enemies[0]
	assert_eq(enemy.magic_defense, 20,
		"a flat spawn with magic_defense 20 fought at %d (defense/2)" % enemy.magic_defense)


func test_a_flat_spawn_without_magic_defense_still_derives_it() -> void:
	var host := _host()
	BattleEnemySpawner.new(host).spawn_from_data([{
		"id": "probe",
		"name": "Probe",
		"max_hp": 500,
		"defense": 44,
		"attack": 10,
	}])
	var enemy: Combatant = host.test_enemies[0]
	assert_eq(enemy.magic_defense, 22,
		"a block with no magic_defense must still derive defense/2")


func test_encounter_data_carries_magic_defense_into_the_combatant() -> void:
	var authored := _codex_mdef("bat")
	assert_ne(authored, _half_defense("bat"), "CONTROL: bat M.DEF must disagree with defense/2")
	var data: Dictionary = EncounterSystem._create_enemy_data("bat")
	assert_eq(int(data.get("magic_defense", -1)), authored,
		"encounter data dropped magic_defense, so anything that initializes it fights at defense/2")
	var enemy := Combatant.new()
	enemy.initialize(data)
	assert_eq(enemy.magic_defense, authored,
		"initializing encounter data for a bat yielded M.DEF %d, codex %d" % [enemy.magic_defense, authored])
	enemy.free()


func test_headless_spawn_fights_the_codex_magic_defense() -> void:
	var authored := _codex_mdef("bat")
	assert_ne(authored, _half_defense("bat"), "CONTROL: bat M.DEF must disagree with defense/2")
	var gl = load("res://src/GameLoop.gd").new()
	var stats: Dictionary = _monsters()["bat"]["stats"]
	var enemy: Combatant = gl._combatant_for_headless({
		"id": "bat",
		"name": "Bat",
		"stats": stats,
	})
	assert_eq(enemy.magic_defense, authored,
		"ludicrous-speed bat fought at M.DEF %d; the codex prints %d" % [enemy.magic_defense, authored])
	var code := GdSource.code_of("res://src/GameLoop.gd")
	assert_true(code.contains("func _resolve_headless_battle"),
		"CONTROL: the headless function must survive comment stripping")
	assert_true(code.contains("_combatant_for_headless"),
		"headless resolution must build the combatant through the path this test calls")
	enemy.free()
	gl.free()
