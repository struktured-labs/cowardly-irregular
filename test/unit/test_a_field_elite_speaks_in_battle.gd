extends GutTest

## Story 27423: field elites never spoke. The spawner stored dialogue only for boss/miniboss rows, and an elite is
## neither. Their lines live in field_elites.json `elite_lines`, keyed by species, and reach the battle only when
## the spawn is a touched elite ("<species>@elite"). A pool spawn of the same species stays quiet, and the one boss
## elite (optimization_itself) keeps speaking from monsters.json.

const SceneScript := preload("res://src/battle/BattleScene.gd")
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


var _saved_party: Array = []


func before_each() -> void:
	var gs: Node = get_tree().root.get_node_or_null("GameState")
	if gs == null:
		return
	_saved_party = gs.player_party.duplicate()
	var party: Array[Dictionary] = []
	for i in range(4):
		party.append({"name": "probe%d" % i, "job_level": 10})
	gs.player_party = party


func after_each() -> void:
	var gs: Node = get_tree().root.get_node_or_null("GameState")
	if gs != null:
		gs.player_party = _saved_party


func _es() -> Node:
	return get_tree().root.get_node_or_null("EncounterSystem")


func _spawn(enemy_id: String) -> SpawnHost:
	var host := SpawnHost.new()
	add_child_autofree(host)
	host.encounter_enemies = [enemy_id]
	BattleEnemySpawner.new(host).spawn_encounter_enemies()
	return host


func _elite_species() -> Array:
	var lines: Dictionary = _es()._load_field_elite_cfg().get("elite_lines", {})
	var out: Array = []
	for k in lines.keys():
		if not str(k).begins_with("_"):
			out.append(str(k))
	return out


func test_every_field_elite_with_lines_speaks_them_in_its_fight() -> void:
	var es := _es()
	assert_not_null(es, "EncounterSystem autoload")
	if es == null:
		return
	var species_list := _elite_species()
	assert_gt(species_list.size(), 4, "CONTROL: field_elites.json must carry elite_lines for the five non-boss elites")
	for species in species_list:
		var expected: Dictionary = es.field_elite_lines(species)
		assert_true(expected.has("intro") and expected.has("low_hp") and expected.has("defeat"),
			"CONTROL: %s's elite_lines must carry intro, low_hp and defeat" % species)
		var host := _spawn(species + EncounterSystem.ELITE_SUFFIX)
		assert_eq(host.test_enemies.size(), 1, "touching the %s elite must start one fight" % species)
		if host.test_enemies.is_empty():
			continue
		var enemy: Node = host.test_enemies[0]
		assert_eq(host._boss_dialogue_data, expected,
			"the %s elite's fight carries no lines of its own: its elite_lines never reached the battle" % species)
		assert_true(enemy.has_meta("field_elite_speaker"), "the %s elite is not marked as the fight's speaker" % species)
		assert_false(enemy.has_meta("is_boss"),
			"the %s elite became a boss to speak: that brings boss music and the banner to a field fight" % species)


func test_an_ordinary_pool_spawn_of_an_elite_species_says_nothing() -> void:
	var es := _es()
	assert_not_null(es, "EncounterSystem autoload")
	if es == null:
		return
	assert_false(es.field_elite_lines("brass_golem").is_empty(),
		"CONTROL: brass_golem must carry elite lines, or its silence below proves nothing")
	var host := _spawn("brass_golem")
	assert_eq(host.test_enemies.size(), 1, "CONTROL: a pool brass_golem must still spawn")
	assert_null(host._boss_dialogue_data, "an ordinary brass_golem from a steampunk pool announced itself with the elite's lines")
	for enemy in host.test_enemies:
		assert_false(enemy.has_meta("field_elite_speaker"), "an ordinary brass_golem was marked as a speaker")


func test_the_boss_elite_speaks_as_the_boss_not_twice() -> void:
	var es := _es()
	assert_not_null(es, "EncounterSystem autoload")
	if es == null:
		return
	assert_true(es.field_elite_lines("optimization_itself").is_empty(),
		"optimization_itself has elite_lines AND a boss row's dialogue: two sources for one panel")
	var row: Dictionary = (JSON.parse_string(FileAccess.get_file_as_string(MONSTERS)) as Dictionary)["optimization_itself"]
	assert_true(bool(row.get("boss", false)), "CONTROL: optimization_itself must still be a boss row")
	var host := _spawn("optimization_itself" + EncounterSystem.ELITE_SUFFIX)
	assert_eq(host.test_enemies.size(), 1, "touching the abstract elite must start one fight")
	if host.test_enemies.is_empty():
		return
	var enemy: Node = host.test_enemies[0]
	assert_true(enemy.has_meta("is_boss"), "the abstract elite lost its boss flag")
	assert_false(enemy.has_meta("field_elite_speaker"), "the abstract elite took the field-elite path instead of the boss path")
	assert_true(host._boss_dialogue_data is Dictionary, "the abstract elite's fight lost its boss dialogue")
	if host._boss_dialogue_data is Dictionary:
		assert_eq(host._boss_dialogue_data.get("low_hp", []), row["dialogue"]["low_hp"],
			"the abstract elite's wounded line is not its monsters.json line")


func test_the_battle_names_the_elite_as_its_speaker() -> void:
	var scene: Node = autofree(SceneScript.new())
	var pool_enemy := Combatant.new()
	pool_enemy.combatant_name = "Gear Beetle"
	var elite := Combatant.new()
	elite.combatant_name = "Brass Golem"
	elite.set_meta("field_elite_speaker", true)
	autofree(pool_enemy)
	autofree(elite)
	assert_true("test_enemies" in scene, "FLOOR: BattleScene must still hold its enemies in test_enemies")
	scene.test_enemies.clear()
	scene.test_enemies.append(pool_enemy)
	scene.test_enemies.append(elite)
	assert_eq(scene._boss_combatant(), elite,
		"the elite's lines would be spoken in the name of the first enemy on the field, not the elite")
	assert_eq(scene._get_boss_intro_speaker(), "Brass Golem", "the elite's intro names the wrong speaker")
	var boss := Combatant.new()
	boss.combatant_name = "Some Boss"
	boss.set_meta("is_boss", true)
	autofree(boss)
	scene.test_enemies.clear()
	scene.test_enemies.append(elite)
	scene.test_enemies.append(boss)
	assert_eq(scene._boss_combatant(), boss, "CONTROL: a real boss still outranks an elite speaker")
