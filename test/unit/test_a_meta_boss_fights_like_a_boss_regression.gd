extends GutTest

## Autogrind builds its enemies as inline dicts and spawns them through BattleEnemySpawner.spawn_from_data, the one spawn
## path that never set the is_boss / is_miniboss meta. spawn_forced_enemies derives it from monsters.json; spawn_from_data
## has no catalog entry to read, because the flags ARE the dict ("is_meta_boss" / "is_collapse_boss"). So a WATCHED grind
## announced "META-BOSS APPEARS" and then fought it as a random encounter: BattleScene._check_for_boss() read false, so no
## boss banner and no boss music, and the boss-damage passive (BattleManager:3480) and boss memory (:951) stayed dark.
## Found by cowir-music's 2026-10-12 sweep of the sibling encounter path, reported unverified for this one.

const SpawnerScript = preload("res://src/battle/BattleEnemySpawner.gd")
const AutogrindState := preload("res://test/unit/helpers/autogrind_state.gd")

const STUB_SCENE := """
extends Node2D
var enemy_positions: Array = [Vector2(100, 100), Vector2(200, 100), Vector2(300, 100)]
var test_enemies: Array = []
func log_message(_t): pass
func _update_ui(): pass
func _on_enemy_died(_e): pass
func _on_enemy_hp_changed(_a, _b): pass
func _on_status_added(_a, _b): pass
func _on_status_removed(_a, _b): pass
func _on_status_tick_damage(_a, _b, _c): pass
func _on_status_tick_heal(_a, _b, _c): pass
"""

var _ag: Dictionary


func before_each() -> void:
	_ag = AutogrindState.snapshot()
	AutogrindSystem._test_disable_persistence = true


func after_each() -> void:
	AutogrindState.restore(_ag)


func _spawn(data: Array) -> Array:
	var script := GDScript.new()
	script.source_code = STUB_SCENE
	script.reload()
	var scene: Node2D = script.new()
	add_child_autofree(scene)
	var spawner = SpawnerScript.new(scene)
	spawner.spawn_from_data(data)
	return scene.test_enemies


func _is_boss(e) -> bool:
	return bool(e.get_meta("is_boss", false))


## BattleScene._check_for_boss reads is_miniboss specifically — that is the one the banner and the music key on.
func _is_miniboss(e) -> bool:
	return bool(e.get_meta("is_miniboss", false))


func test_a_meta_boss_is_spawned_as_a_boss() -> void:
	var data: Dictionary = AutogrindSystem.build_meta_boss_enemy_data(false)
	assert_true(bool(data.get("is_meta_boss", false)), "CONTROL: the grind's own data must carry the meta-boss flag")
	var spawned: Array = _spawn([data])
	assert_eq(spawned.size(), 1, "CONTROL: one meta-boss must spawn")
	assert_true(_is_boss(spawned[0]), "a meta-boss must carry is_boss, or the boss-damage passive and boss memory stay dark")
	assert_true(_is_miniboss(spawned[0]), "and is_miniboss, which is what the boss banner and boss music read")


func test_a_collapse_boss_is_spawned_as_a_boss() -> void:
	var data: Dictionary = AutogrindSystem.build_meta_boss_enemy_data(true)
	assert_true(bool(data.get("is_collapse_boss", false)), "CONTROL: the collapse boss's data must say so")
	var spawned: Array = _spawn([data])
	assert_true(_is_boss(spawned[0]) and _is_miniboss(spawned[0]), "a system-collapse boss must fight as a boss")


func test_an_ordinary_grind_enemy_is_not_a_boss() -> void:
	var spawned: Array = _spawn([{"id": "slime", "name": "Slime", "max_hp": 60, "attack": 8}])
	assert_eq(spawned.size(), 1, "CONTROL: the ordinary enemy must spawn")
	assert_false(_is_boss(spawned[0]), "a random grind enemy must NOT be promoted to a boss")
	assert_false(_is_miniboss(spawned[0]), "or the banner and boss music would fire on every battle")


func test_a_catalog_shaped_boss_dict_is_honoured_too() -> void:
	var spawned: Array = _spawn([{"id": "rat_king", "name": "Rat King", "max_hp": 900, "boss": true}])
	assert_true(_is_boss(spawned[0]), "a dict carrying the catalog's own 'boss' key must be tagged as well")


func test_a_mixed_wave_tags_only_the_boss() -> void:
	var data: Dictionary = AutogrindSystem.build_meta_boss_enemy_data(false)
	var spawned: Array = _spawn([{"id": "slime", "name": "Slime", "max_hp": 60}, data])
	assert_eq(spawned.size(), 2, "CONTROL: both enemies must spawn")
	assert_false(_is_boss(spawned[0]), "the escort must stay an ordinary enemy")
	assert_true(_is_boss(spawned[1]), "while the meta-boss beside it is a boss")
