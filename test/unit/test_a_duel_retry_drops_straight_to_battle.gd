extends GutTest

## Spec 2026-06-30 (spotlight duels, locked): the intro plays on the first attempt only; a retry drops straight to battle.
## A retry rebuilt the BattleScene through spawn_forced_enemies, which copied the miniboss's intro every time, so the
## panel replayed after each defeat. The duel step now leaves the intro note on a retry and the forced spawner honours it.

const DUEL_ID := "fighter_skeleton_knight"
const STEP := {"type": "battle", "combatants": ["fighter"], "enemies": [DUEL_ID], "on_defeat": "retry"}


class StubGameLoop extends Node:
	var results: Array = []
	var notes_seen: Array = []

	func start_solo_battle(_job: String, _enemy: String, _opts: Dictionary = {}) -> String:
		notes_seen.append(GameState.boss_intro_cutscene_for)
		await get_tree().process_frame
		return "defeat" if results.is_empty() else str(results.pop_front())


class SpawnHost:
	extends Node
	var encounter_enemies: Array = []
	var forced_enemies: Array = []
	var autogrind_enemy_data: Array = []
	var force_miniboss: bool = false
	var enemy_positions: Array = [0, 0, 0]
	var test_enemies: Array = []
	var _boss_dialogue_data: Dictionary = {}

	func log_message(_m: String) -> void:
		pass

	func _update_ui() -> void:
		pass

	func _on_enemy_hp_changed(_o, _n, _i) -> void:
		pass

	func _on_enemy_died(_i) -> void:
		pass

	func _on_status_added(_s, _c) -> void:
		pass

	func _on_status_removed(_s, _c) -> void:
		pass

	func _on_status_tick_damage(_a, _s, _t) -> void:
		pass

	func _on_status_tick_heal(_a, _s, _t) -> void:
		pass


var _stub: StubGameLoop


func before_each() -> void:
	GameState.boss_intro_cutscene_for = ""
	_stub = StubGameLoop.new()
	_stub.name = "GameLoop"
	get_tree().root.add_child(_stub)


func after_each() -> void:
	GameState.boss_intro_cutscene_for = ""
	if is_instance_valid(_stub):
		get_tree().root.remove_child(_stub)
		_stub.free()


func _forced(note: String) -> SpawnHost:
	var h := SpawnHost.new()
	add_child_autofree(h)
	GameState.boss_intro_cutscene_for = note
	h.forced_enemies = [DUEL_ID]
	BattleEnemySpawner.new(h).spawn_forced_enemies()
	return h


func test_a_first_duel_attempt_opens_on_its_intro() -> void:
	var h := _forced("")
	assert_eq(h.test_enemies.size(), 1, "CONTROL: the Skeleton Knight spawned")
	assert_gt(h._boss_dialogue_data.get("intro", []).size(), 0, "the first attempt at the Fighter's duel lost the Skeleton Knight's intro")


func test_a_retried_duel_drops_its_intro_and_keeps_the_rest() -> void:
	var h := _forced(DUEL_ID)
	assert_eq(h.test_enemies.size(), 1, "CONTROL: the Skeleton Knight spawned")
	assert_false(h._boss_dialogue_data.has("intro"), "a retried duel replayed the Skeleton Knight's intro; the spec says a retry drops straight to battle")
	assert_gt(h._boss_dialogue_data.get("low_hp", []).size(), 0, "a retry dropped the wounded line along with the intro")
	assert_eq(GameState.boss_intro_cutscene_for, "", "the forced spawn left the note for a later fight")
	var row: Dictionary = BattleEnemySpawner.new(h).load_monsters_data().get(DUEL_ID, {})
	assert_gt(row.get("dialogue", {}).get("intro", []).size(), 0, "dropping a retry's intro erased it from the cached monster database: every later first attempt is silent")


func test_another_species_note_leaves_the_intro() -> void:
	var h := _forced("fire_dragon")
	assert_gt(h._boss_dialogue_data.get("intro", []).size(), 0, "a note for another species silenced the Skeleton Knight's intro")


func _duel() -> Node:
	var d: Node = load("res://src/cutscene/CutsceneDirector.gd").new()
	add_child_autofree(d)
	return d


func test_the_duel_step_notes_the_intro_on_retries_only() -> void:
	_stub.results = ["defeat", "defeat", "victory"]
	await _duel()._step_battle(STEP.duplicate(true))
	assert_eq(_stub.notes_seen.size(), 3, "CONTROL: the duel ran three attempts")
	assert_eq(_stub.notes_seen, ["", DUEL_ID, DUEL_ID], "the first attempt must open on the intro and each retry must skip it")
	assert_eq(GameState.boss_intro_cutscene_for, "", "the duel left its intro note behind for the next fight")


func test_an_unrunnable_retry_leaves_no_note() -> void:
	_stub.results = ["defeat", "unavailable"]
	await _duel()._step_battle(STEP.duplicate(true))
	assert_eq(_stub.notes_seen, ["", DUEL_ID], "CONTROL: the retry was attempted with the note")
	assert_eq(GameState.boss_intro_cutscene_for, "", "a retry that never spawned left its note for whatever fight comes next")
