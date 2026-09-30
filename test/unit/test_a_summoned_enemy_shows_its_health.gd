extends GutTest

## A monster SUMMONED mid-battle got its name label and status icons but no HP bar — the spawn path in
## _present_summoned_enemy simply never called _create_enemy_hp_bar, so a player could not see a summon's health
## at all. Its bar is now built by the same builder as every other enemy's, so it sits under its name
## (test_the_hp_bar_sits_under_the_name) and drains with its HP through the same _update_enemy_hp_bars.

const SoundState := preload("res://test/unit/helpers/sound_state.gd")
const BattleState := preload("res://test/unit/helpers/battle_state.gd")
const SCENE := "res://src/battle/BattleScene.tscn"

var _guard: RefCounted = null


func before_each() -> void:
	_guard = BattleState.new()
	_guard.snapshot()


func after_each() -> void:
	if _guard != null:
		_guard.restore()


func after_all() -> void:
	SoundState.restore()


func _summon(scene: Node, monster_type: String) -> Combatant:
	var enemy := Combatant.new()
	enemy.combatant_name = monster_type.capitalize()
	enemy.max_hp = 100
	enemy.current_hp = 100
	enemy.is_alive = true
	autofree(enemy)
	scene._present_summoned_enemy(enemy, monster_type, scene.enemy_sprite_nodes.size(), enemy.combatant_name)
	return enemy


func test_a_summon_gets_an_hp_bar_under_its_name() -> void:
	var scene = load(SCENE).instantiate()
	add_child_autofree(scene)
	await get_tree().process_frame
	var enemy := _summon(scene, "goblin")
	var sprite: Node = scene.enemy_sprite_nodes[scene.enemy_sprite_nodes.size() - 1]
	assert_not_null(sprite.get_node_or_null("NameLabel"), "CONTROL: the summon was presented with its name")
	assert_true(scene._enemy_hp_bars.has(enemy), "a summoned enemy has no HP bar — its health is invisible")
	if not scene._enemy_hp_bars.has(enemy):
		return
	var bar: ColorRect = scene._enemy_hp_bars[enemy]["bar_bg"]
	assert_eq(bar.get_parent(), sprite, "the bar belongs to the summon's own sprite")
	var label: Label = sprite.get_node("NameLabel")
	assert_gte(bar.position.y, label.position.y + label.get_minimum_size().y - 0.01, "and sits under its name")


func test_a_summon_s_bar_drains_with_its_hp() -> void:
	var scene = load(SCENE).instantiate()
	add_child_autofree(scene)
	await get_tree().process_frame
	var enemy := _summon(scene, "goblin")
	if not scene._enemy_hp_bars.has(enemy):
		fail_test("a summoned enemy has no HP bar")
		return
	var fill: ColorRect = scene._enemy_hp_bars[enemy]["bar_fill"]
	var full := fill.size.x
	enemy.current_hp = 25
	scene._update_enemy_hp_bars()
	await get_tree().create_timer(0.3).timeout
	assert_lt(fill.size.x, full * 0.5, "the summon's bar must drain when it takes damage (was %.1f, now %.1f)" % [full, fill.size.x])
