extends GutTest

## Regression: a one-shot trigger switched itself off with `monitoring = false` from inside its own
## body_entered, which runs inside the physics step. The engine refuses that write:
##   ERROR: Function blocked during in/out signal. Use set_deferred("monitoring", true/false).
## (struktured's play log of 2026-09-26, touching the Arbiter outside Grimhollow), so the trigger
## kept monitoring after it fired. Two sites, found by following each body_entered handler through
## its same-file callees: MasteriteEncounter._on_body_entered and QuestChicken._on_body_entered ->
## _catch -> _poof. Each arm walks a real player body into the trigger.

const MasteriteScript := preload("res://src/exploration/MasteriteEncounter.gd")
const ChickenScript := preload("res://src/exploration/QuestChicken.gd")
const CHICKEN_QUEST := "world1_one_chicken_problem"


class BattleHost:
	extends Node2D
	var fired: Array = []

	func _on_battle_triggered(ids: Array) -> void:
		fired.append(ids)


var _vp: SubViewport


func before_each() -> void:
	_vp = SubViewport.new()
	_vp.world_2d = World2D.new()
	_vp.size = Vector2i(320, 240)
	add_child_autofree(_vp)
	_reset_state()


func after_each() -> void:
	_reset_state()


func _reset_state() -> void:
	if GameState == null:
		return
	GameState.set_story_flag("w1_warden_defeated", false)
	GameState.pending_boss_defeat = {}
	GameState.quests.clear()
	GameState.set_story_flag("chicken_caught_" + ChickenScript.ALL_CHICKEN_IDS[0], false)


func _player_at(pos: Vector2) -> CharacterBody2D:
	var body := CharacterBody2D.new()
	body.collision_layer = 2
	body.collision_mask = 0
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 6.0
	shape.shape = circle
	body.add_child(shape)
	body.add_to_group("player")
	body.position = pos
	return body


func _let_physics_run() -> void:
	for _i in 6:
		await get_tree().physics_frame
	await get_tree().process_frame


func test_a_masterite_stops_monitoring_once_it_fires() -> void:
	var host := BattleHost.new()
	_vp.add_child(host)
	var trig: Area2D = MasteriteScript.new()
	trig.archetype = "warden"
	trig.monster_id = "masterite_warden_medieval"
	trig.cutscene_id = ""
	trig.position = Vector2(100, 100)
	host.add_child(trig)
	await _let_physics_run()
	assert_true(trig.monitoring, "CONTROL: an armed Masterite is monitoring")
	host.add_child(_player_at(trig.position))
	await _let_physics_run()
	assert_eq(host.fired.size(), 1, "CONTROL: the real overlap fired the encounter")
	assert_false(trig.monitoring, "the fired Masterite is still monitoring — the write was refused mid-signal")


func test_a_caught_chicken_stops_monitoring() -> void:
	var qs := get_tree().root.get_node_or_null("QuestSystem")
	assert_not_null(qs, "CONTROL: QuestSystem autoload")
	if qs == null:
		return
	qs.accept(CHICKEN_QUEST)
	var hen: Area2D = ChickenScript.new()
	hen.chicken_id = ChickenScript.ALL_CHICKEN_IDS[0]
	hen.position = Vector2(100, 100)
	_vp.add_child(hen)
	await _let_physics_run()
	assert_true(hen.monitoring, "CONTROL: an uncaught hen is monitoring")
	_vp.add_child(_player_at(hen.position))
	await _let_physics_run()
	assert_true(hen._caught, "CONTROL: the real overlap caught the hen")
	assert_false(hen.monitoring, "the caught hen is still monitoring — the write was refused mid-signal")
