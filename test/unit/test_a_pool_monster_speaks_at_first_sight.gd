extends GutTest

## Story 27515/27529, main 27530/27532: four abstract-pool monsters carried monsters.json intros that no spawn path showed.
## A pool monster's intro (and the_absence's low_hp) now plays on its FIRST LIVE sighting per save, without is_boss.
## The heard-flag is written only when the panel shows, so an autogrind or scan sighting never spends the line.

const SceneScript := preload("res://src/battle/BattleScene.gd")
const GameStateScript := preload("res://src/meta/GameState.gd")
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


class DialogueProbe:
	extends "res://src/ui/BattleDialogue.gd"
	var shown: Array = []

	func set_party(_party: Array) -> void:
		pass

	func show_boss_intro(boss_name: String, intro_lines: Array, _boss_id: String = "") -> void:
		shown.append([boss_name, intro_lines])


var _saved_constants: Dictionary = {}


func before_each() -> void:
	var gs := _gs()
	if gs == null:
		return
	_saved_constants = gs.game_constants.duplicate(true)
	gs.game_constants.erase("pool_intro_heard")
	var seen = gs.game_constants.get("seen_monsters", {})
	if seen is Dictionary:
		for species in ["null_entity", "forgotten_variable", "empty_set", "the_absence"]:
			(seen as Dictionary).erase(species)


func after_each() -> void:
	var gs := _gs()
	if gs != null:
		gs.game_constants = _saved_constants


func _gs() -> Node:
	return get_tree().root.get_node_or_null("GameState")


func _row(species: String) -> Dictionary:
	return (JSON.parse_string(FileAccess.get_file_as_string(MONSTERS)) as Dictionary)[species]


func _spawn(ids: Array, grinding: bool = false) -> SpawnHost:
	var host := SpawnHost.new()
	host.autogrind_console_mode = grinding
	add_child_autofree(host)
	host.encounter_enemies = ids
	BattleEnemySpawner.new(host).spawn_encounter_enemies()
	return host


func _speakers(host: SpawnHost) -> Array:
	var out: Array = []
	for e in host.test_enemies:
		if e.has_meta("pool_intro_speaker"):
			out.append(str(e.get_meta("monster_type", "")))
	return out


func test_a_first_live_sighting_speaks_its_intro() -> void:
	assert_not_null(_gs(), "GameState autoload")
	var host := _spawn(["the_absence"])
	assert_eq(host.test_enemies.size(), 1, "CONTROL: a pool the_absence must spawn")
	var row := _row("the_absence")
	assert_true(host._boss_dialogue_data is Dictionary, "the first sighting of the_absence carries no lines into its fight")
	if not (host._boss_dialogue_data is Dictionary):
		return
	assert_eq(host._boss_dialogue_data.get("intro", []), row["dialogue"]["intro"], "the first sighting's intro is not its monsters.json intro")
	assert_eq(host._boss_dialogue_data.get("low_hp", []), row["dialogue"]["low_hp"], "the_absence's wounded line did not come with its first fight")
	assert_eq(_speakers(host), ["the_absence"], "the_absence was not marked as the fight's speaker")
	assert_false(host.test_enemies[0].has_meta("is_boss"), "a pool monster became a boss to speak: banner and boss music in a pool fight")


func test_a_second_sighting_of_a_heard_species_is_silent() -> void:
	var gs := _gs()
	assert_not_null(gs, "GameState autoload")
	if gs == null:
		return
	assert_true(_spawn(["empty_set"])._boss_dialogue_data is Dictionary, "CONTROL: an unheard empty_set speaks")
	gs.mark_pool_intro_heard("empty_set")
	var host := _spawn(["empty_set"])
	assert_null(host._boss_dialogue_data, "empty_set spoke its intro again after it was heard")
	assert_eq(_speakers(host), [], "a heard empty_set was still marked as a speaker")


func test_an_autogrind_battle_never_speaks() -> void:
	var host := _spawn(["null_entity"], true)
	assert_eq(host.test_enemies.size(), 1, "CONTROL: the grind's null_entity must spawn")
	assert_null(host._boss_dialogue_data, "an autogrind fight carried null_entity's intro into the grind")
	assert_false(_gs().pool_intro_heard("null_entity"), "an autogrind spawn spent null_entity's intro")


func test_a_species_autogrinded_or_scanned_first_still_speaks_live() -> void:
	BestiarySystem.mark_seen("forgotten_variable")
	assert_true(BestiarySystem.is_seen("forgotten_variable"), "CONTROL: the bestiary records the earlier sighting")
	var host := _spawn(["forgotten_variable"])
	assert_true(host._boss_dialogue_data is Dictionary,
		"forgotten_variable was seen in a grind or scan first, and its first live fight lost the intro")
	assert_eq(_speakers(host), ["forgotten_variable"], "forgotten_variable was not the speaker of its first live fight")


func test_a_fight_with_two_unheard_species_names_the_right_speaker() -> void:
	var host := _spawn(["null_entity", "the_absence"])
	assert_eq(host.test_enemies.size(), 2, "CONTROL: both pool monsters must spawn")
	assert_eq(_speakers(host), ["null_entity"], "with two unheard species, exactly the first in spawn order speaks")
	if host._boss_dialogue_data is Dictionary:
		assert_eq(host._boss_dialogue_data.get("intro", []), _row("null_entity")["dialogue"]["intro"],
			"the fight's lines are not the speaker's own")
	_gs().mark_pool_intro_heard("null_entity")
	var later := _spawn(["null_entity", "the_absence"])
	assert_eq(_speakers(later), ["the_absence"], "once null_entity is heard, the_absence must speak its own first sighting")
	if later._boss_dialogue_data is Dictionary:
		assert_eq(later._boss_dialogue_data.get("intro", []), _row("the_absence")["dialogue"]["intro"],
			"the_absence's fight showed another species' lines")


func test_the_line_is_spent_only_when_its_panel_shows_live() -> void:
	var gs := _gs()
	assert_not_null(gs, "GameState autoload")
	if gs == null:
		return
	var scene: Node = autofree(SceneScript.new())
	var probe: Node = autofree(DialogueProbe.new())
	scene._battle_dialogue = probe
	var speaker := Combatant.new()
	autofree(speaker)
	speaker.combatant_name = "Empty Set"
	speaker.set_meta("monster_type", "empty_set")
	speaker.set_meta("pool_intro_speaker", true)
	scene.test_enemies.clear()
	scene.test_enemies.append(speaker)
	scene._boss_dialogue_data = {"intro": ["*nothing*"]}
	scene.autogrind_console_mode = true
	scene._show_boss_intro_dialogue()
	assert_false(gs.pool_intro_heard("empty_set"), "a console-mode fight spent empty_set's intro")
	scene.autogrind_console_mode = false
	scene._show_boss_intro_dialogue()
	assert_eq(probe.shown.size(), 2, "CONTROL: the intro panel was shown")
	assert_eq(str(probe.shown[-1][0]), "Empty Set", "the pool intro names the wrong speaker")
	assert_true(gs.pool_intro_heard("empty_set"), "showing empty_set's intro live did not record that it was heard")


func test_the_heard_flag_survives_a_save_and_new_game_clears_it() -> void:
	var a = autofree(GameStateScript.new())
	a.mark_pool_intro_heard("the_absence")
	assert_true(a.pool_intro_heard("the_absence"), "CONTROL: the flag reads back in the same session")
	var text := JSON.stringify(a._create_save_data())
	var b = autofree(GameStateScript.new())
	assert_false(b.pool_intro_heard("the_absence"), "CONTROL: a fresh state has heard nothing")
	b._apply_save_data(JSON.parse_string(text))
	assert_true(b.pool_intro_heard("the_absence"), "a save/load forgot that the_absence's intro was heard; it would speak again")
	b.reset_game_state()
	assert_false(b.pool_intro_heard("the_absence"), "New Game kept the previous run's heard intros")
