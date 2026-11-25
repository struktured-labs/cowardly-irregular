extends GutTest

## Battle 27609/27612/27616, main 27611/27613: every boss row's in-battle intro was erased on the encounter path because
## a dungeon cutscene usually plays it. A floor re-level (meta_knight@L23), a pool miniboss and a Vertex trial have no
## cutscene, so their intro was lost; the forced-miniboss door set no dialogue at all. Now only the door whose cutscene
## actually played drops the intro, once.

const MONSTERS := "res://data/monsters.json"


class SpawnHost:
	extends Node
	var encounter_enemies: Array = []
	var forced_enemies: Array = []
	var autogrind_enemy_data: Array = []
	var force_miniboss: bool = false
	var autogrind_console_mode: bool = false
	var enemy_positions: Array = [0, 0, 0]
	var test_enemies: Array = []
	var _boss_dialogue_data = null

	func log_message(_message: String) -> void:
		pass

	func _update_ui() -> void:
		pass

	func _announce_boss_banner(_lines: Array, _title: String) -> void:
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


class ProbeCave:
	extends "res://src/maps/dungeons/DragonCave.gd"

	func _ready() -> void:
		pass


class ProbeDirector:
	extends Node
	var played: Array = []

	func play_cutscene(cutscene_id: String) -> void:
		played.append(cutscene_id)


class ProbeLoop:
	extends Node
	var director: Node = null

	func get_cutscene_director() -> Node:
		return director


func before_each() -> void:
	GameState.boss_intro_cutscene_for = ""


func after_each() -> void:
	GameState.boss_intro_cutscene_for = ""


func _row(species: String) -> Dictionary:
	return (JSON.parse_string(FileAccess.get_file_as_string(MONSTERS)) as Dictionary)[species]


func _spawn(ids: Array) -> SpawnHost:
	var host := SpawnHost.new()
	add_child_autofree(host)
	host.encounter_enemies = ids
	BattleEnemySpawner.new(host).spawn_encounter_enemies()
	return host


func _lines(host: SpawnHost, key: String) -> Array:
	return (host._boss_dialogue_data as Dictionary).get(key, []) if host._boss_dialogue_data is Dictionary else []


func test_a_boss_whose_cutscene_spoke_the_intro_drops_it_once() -> void:
	var row := _row("fire_dragon")
	assert_false((row["dialogue"]["intro"] as Array).is_empty(), "CONTROL: fire_dragon authors an intro")
	GameState.boss_intro_cutscene_for = "fire_dragon"
	var host := _spawn(["fire_dragon"])
	assert_eq(_lines(host, "intro"), [], "Pyrroth's intro played in battle right after his cutscene spoke it")
	assert_eq(_lines(host, "low_hp"), row["dialogue"]["low_hp"], "CONTROL: the rest of the cutscene boss's lines still reach the fight")
	assert_eq(GameState.boss_intro_cutscene_for, "", "the cutscene note outlived the fight it introduced")
	var again := _spawn(["fire_dragon"])
	assert_eq(_lines(again, "intro"), row["dialogue"]["intro"], "a later fight with no cutscene still dropped the intro")


func test_a_floor_relevel_boss_keeps_its_intro() -> void:
	var row := _row("meta_knight")
	assert_true(bool(row.get("boss", false)), "CONTROL: meta_knight is a boss row")
	var host := _spawn(["meta_knight@L23"])
	assert_eq(host.test_enemies.size(), 1, "CONTROL: Harmonia F3's meta_knight@L23 spawns")
	assert_eq(_lines(host, "intro"), row["dialogue"]["intro"], "the Meta Knight on Harmonia F3 lost its intro though no cutscene played it")
	assert_eq(_lines(host, "low_hp"), row["dialogue"]["low_hp"], "the Meta Knight lost its wounded line")


func test_a_pool_miniboss_keeps_its_intro_and_the_rest() -> void:
	var row := _row("crystal_golem")
	assert_true(bool(row.get("miniboss", false)), "CONTROL: crystal_golem is a miniboss row")
	var host := _spawn(["crystal_golem"])
	for key in ["intro", "low_hp", "defeat"]:
		assert_eq(_lines(host, key), row["dialogue"][key], "the pool-rolled Crystal Golem is missing its %s" % key)


func test_a_stale_cutscene_note_does_not_erase_another_species() -> void:
	GameState.boss_intro_cutscene_for = "fire_dragon"
	var host := _spawn(["crystal_golem"])
	assert_eq(_lines(host, "intro"), _row("crystal_golem")["dialogue"]["intro"],
		"a cutscene note left for another boss erased the Crystal Golem's intro")
	assert_eq(GameState.boss_intro_cutscene_for, "", "the stale note survived a spawn")


func test_the_forced_miniboss_door_carries_its_row_dialogue() -> void:
	var host := SpawnHost.new()
	add_child_autofree(host)
	BattleEnemySpawner.new(host).spawn_miniboss()
	assert_eq(host.test_enemies.size(), 1, "CONTROL: the forced miniboss door spawns one enemy")
	if host.test_enemies.is_empty():
		return
	var species := str(host.test_enemies[0].get_meta("monster_type", ""))
	var row := _row(species)
	assert_true(row.has("dialogue"), "CONTROL: %s authors dialogue" % species)
	for key in ["intro", "low_hp", "defeat"]:
		assert_eq(_lines(host, key), row["dialogue"][key], "the forced-door %s is missing its %s" % [species, key])


func test_a_dungeon_notes_the_boss_its_cutscene_introduced() -> void:
	assert_null(get_tree().root.get_node_or_null("GameLoop"), "FLOOR: a real GameLoop is up; this arm's stub would shadow it")
	if get_tree().root.get_node_or_null("GameLoop") != null:
		return
	var director := ProbeDirector.new()
	var loop := ProbeLoop.new()
	loop.name = "GameLoop"
	loop.director = director
	loop.add_child(director)
	get_tree().root.add_child(loop)
	var cave := ProbeCave.new()
	cave.boss_id = "fire_dragon"
	cave.boss_cutscene_id = "world1_pyrroth_intro"
	add_child_autofree(cave)
	await cave._show_boss_intro()
	assert_eq(director.played, ["world1_pyrroth_intro"], "CONTROL: the cave played its boss cutscene")
	assert_eq(GameState.boss_intro_cutscene_for, "fire_dragon", "the cave played Pyrroth's cutscene and did not say so to the spawner")
	get_tree().root.remove_child(loop)
	loop.free()


func test_every_door_that_plays_a_boss_cutscene_leaves_the_note() -> void:
	var doors := {
		"res://src/maps/dungeons/DragonCave.gd": "GameState.boss_intro_cutscene_for = boss_id",
		"res://src/exploration/MasteriteEncounter.gd": "GameState.boss_intro_cutscene_for = monster_id",
		"res://src/maps/dungeons/WhisperingCave.gd": "GameState.boss_intro_cutscene_for = \"cave_rat_king\"",
	}
	for path in doors:
		var src := FileAccess.get_file_as_string(path)
		assert_true(src.contains("play_cutscene("), "CONTROL: %s plays a cutscene" % path)
		assert_true(src.contains(doors[path]), "%s plays a boss cutscene and never tells the spawner, so the boss repeats its intro" % path)


func test_every_vertex_trial_boss_opens_on_its_own_line() -> void:
	## Story 27655/27657: no cutscene introduces a trial, so each occupant's intro must survive the encounter spawn.
	var trials: Dictionary = TrialRouting.TRIAL_MONSTERS
	assert_eq(trials.size(), 3, "CONTROL: the three Vertex trials")
	for trial in trials:
		var species := str(trials[trial])
		var intro: Array = _row(species).get("dialogue", {}).get("intro", [])
		assert_false(intro.is_empty(), "CONTROL: %s authors an intro" % species)
		var host := _spawn([species])
		assert_eq(_lines(host, "intro"), intro, "the %s trial's %s lost its opening line" % [trial, species])


func test_the_antechamber_plays_no_cutscene_so_leaves_no_note() -> void:
	var room = autofree(load("res://src/maps/dungeons/VertexAntechamber.gd").new())
	assert_eq(str(room.boss_cutscene_id), "", "the Antechamber gained a boss cutscene; its trial intro would now be dropped after it")
	var cave := ProbeCave.new()
	cave.boss_id = "the_operator"
	add_child_autofree(cave)
	await cave._show_boss_intro()
	assert_eq(GameState.boss_intro_cutscene_for, "", "a door with no cutscene told the spawner one had spoken")


func test_the_render_smokes_wipe_boss_skips_its_cave_so_leaves_its_note() -> void:
	## .826 pre-gate: the wipe leg starts Umbraxis as an encounter without his cave, so his kept intro held the battle unstarted.
	var src := FileAccess.get_file_as_string("res://src/GameLoop.gd")
	var start := src.find('await _start_battle_async(["shadow_dragon"], true)')
	assert_gt(start, 0, "CONTROL: the smoke's wipe leg still starts Umbraxis through the encounter path")
	var lead := src.substr(maxi(0, start - 300), 300)
	assert_true(lead.contains('GameState.boss_intro_cutscene_for = "shadow_dragon"'),
		"the smoke's wipe leg starts Umbraxis without the note his cave leaves; his intro panel holds the battle and no wipe comes")
