extends GutTest

## Repel says it keeps monsters incurious for 50 steps. The world map turned
## step-rolls off (visible monsters are the encounters) and the charm only
## ticked inside that roll, so walking the map neither spent a charge nor
## stopped a chase. A cave step already spent one; this pins the field.

const ControllerScript := preload("res://src/exploration/OverworldController.gd")
const RoamingScript := preload("res://src/exploration/RoamingMonster.gd")

var _saved: Dictionary = {}


class FakePlayer:
	extends Node2D
	func set_can_move(_v: bool) -> void:
		pass


func _es() -> Node:
	return get_tree().root.get_node_or_null("EncounterSystem")


func _gs() -> Node:
	return get_tree().root.get_node_or_null("GameState")


func before_each() -> void:
	_saved.clear()
	var es := _es()
	var gs := _gs()
	if es != null:
		_saved["repel"] = int(es.repel_steps_remaining)
		_saved["steps"] = int(es.steps_since_last_encounter)
		_saved["enabled"] = bool(es.encounters_enabled)
		_saved["forced"] = bool(es.forced_encounter_next_step)
	if gs != null:
		_saved["mult"] = float(gs.encounter_rate_multiplier)


func after_each() -> void:
	var es := _es()
	var gs := _gs()
	if es != null and _saved.has("repel"):
		es.repel_steps_remaining = _saved["repel"]
		es.steps_since_last_encounter = _saved["steps"]
		es.encounters_enabled = _saved["enabled"]
		es.forced_encounter_next_step = _saved["forced"]
	if gs != null and _saved.has("mult"):
		gs.encounter_rate_multiplier = _saved["mult"]
	var lock := get_tree().root.get_node_or_null("InputLockManager")
	if lock and lock.has_method("pop_lock"):
		lock.pop_lock("repel_field_test")


func _world_map_controller() -> Node:
	var ctrl := ControllerScript.new()
	ctrl.encounter_enabled = false
	ctrl._is_safe_zone = false
	ctrl._paused = false
	add_child_autofree(ctrl)
	return ctrl


func _roamer(elite: bool) -> Node:
	var host := Node2D.new()
	add_child_autofree(host)
	var m: Node = RoamingScript.new()
	m.elite = elite
	host.add_child(m)
	return m


func test_a_world_map_step_spends_one_repel_charge_without_rolling() -> void:
	var es := _es()
	assert_not_null(es, "EncounterSystem autoload")
	if es == null:
		return
	es.repel_steps_remaining = 50
	es.forced_encounter_next_step = false
	var steps_before := int(es.steps_since_last_encounter)
	var ctrl := _world_map_controller()
	var battles := [0]
	ctrl.battle_triggered.connect(func(_enemies): battles[0] += 1)
	ctrl._on_player_moved(1)
	assert_eq(battles[0], 0, "a world-map step must not start a hidden step-roll battle")
	assert_eq(int(es.steps_since_last_encounter), steps_before,
		"a world-map step must not move the dungeon spacing counter")
	assert_eq(int(es.repel_steps_remaining), 49,
		"walking the world map spent no Repel charge (still %d)" % int(es.repel_steps_remaining))


func test_touching_a_visible_monster_does_not_fight_while_repel_holds() -> void:
	var es := _es()
	assert_not_null(es)
	if es == null:
		return
	es.repel_steps_remaining = 12
	var m := _roamer(false)
	var player := FakePlayer.new()
	add_child_autofree(player)
	var fired := [0]
	m.touched.connect(func(_id, _types, _elite): fired[0] += 1)
	m._active = true
	m._on_body_entered(player)
	assert_eq(fired[0], 0, "a visible monster started a fight while Repel still had charges")


func test_a_visible_monster_does_not_chase_while_repel_holds() -> void:
	var es := _es()
	assert_not_null(es)
	if es == null:
		return
	es.repel_steps_remaining = 12
	var m := _roamer(false)
	var player := FakePlayer.new()
	add_child_autofree(player)
	player.global_position = Vector2(40, 0)
	m.global_position = Vector2.ZERO
	m.set_player_ref(player)
	m._tick_mood(0.016)
	m._tick_state(0.016)
	assert_eq(m._mood, m.Mood.CALM, "Repel left the monster alerted instead of incurious")
	assert_ne(m._state, 2, "Repel left the monster chasing")


func test_a_field_elite_still_asks_while_repel_holds() -> void:
	var es := _es()
	assert_not_null(es)
	if es == null:
		return
	es.repel_steps_remaining = 12
	var m := _roamer(true)
	var player := FakePlayer.new()
	add_child_autofree(player)
	var fired := [0]
	m.touched.connect(func(_id, _types, _elite): fired[0] += 1)
	m._active = true
	m._on_body_entered(player)
	assert_eq(fired[0], 0, "an elite must not ambush, Repel or not")
	assert_true(m._prompt_open, "Repel must not swallow the choice to fight a field elite")


func test_town_and_locked_steps_do_not_spend_repel() -> void:
	var es := _es()
	assert_not_null(es)
	if es == null:
		return
	es.repel_steps_remaining = 50
	var town := _world_map_controller()
	town._is_safe_zone = true
	town._on_player_moved(1)
	assert_eq(int(es.repel_steps_remaining), 50, "a town step spent a Repel charge")
	var locked := _world_map_controller()
	var lock := get_tree().root.get_node_or_null("InputLockManager")
	assert_not_null(lock, "InputLockManager autoload")
	if lock == null:
		return
	lock.push_lock("repel_field_test")
	locked._on_player_moved(1)
	lock.pop_lock("repel_field_test")
	assert_eq(int(es.repel_steps_remaining), 50, "a step during a fade or cutscene lock spent a Repel charge")


func test_a_dungeon_step_spends_repel_once() -> void:
	var es := _es()
	var gs := _gs()
	assert_not_null(es)
	assert_not_null(gs)
	if es == null or gs == null:
		return
	es.repel_steps_remaining = 50
	es.encounters_enabled = true
	es.forced_encounter_next_step = false
	gs.encounter_rate_multiplier = 1.0
	var ctrl := ControllerScript.new()
	ctrl.encounter_enabled = true
	ctrl._is_safe_zone = false
	ctrl._paused = false
	add_child_autofree(ctrl)
	ctrl._on_player_moved(1)
	assert_eq(int(es.repel_steps_remaining), 49,
		"one dungeon step spent Repel down to %d (once is 49)" % int(es.repel_steps_remaining))


func test_spent_repel_lets_the_next_touch_fight() -> void:
	var es := _es()
	assert_not_null(es)
	if es == null:
		return
	es.repel_steps_remaining = 1
	var ctrl := _world_map_controller()
	ctrl._on_player_moved(1)
	assert_eq(int(es.repel_steps_remaining), 0, "the last world-map step must spend the last charge")
	var m := _roamer(false)
	var player := FakePlayer.new()
	add_child_autofree(player)
	var fired := [0]
	m.touched.connect(func(_id, _types, _elite): fired[0] += 1)
	m._active = true
	m._on_body_entered(player)
	assert_eq(fired[0], 1, "once Repel is spent, touching a visible monster must start the fight")
