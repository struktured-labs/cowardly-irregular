extends GutTest

## Regression (cowir-main's .615 gate log, 67 "add_child on a null value" SCRIPT ERRORs): .605's speed indicator wrote to
## $UI, which a BattleScene built from its script (most battle tests do this) does not have. The error aborted only the
## indicator builder (an error kills its own frame, so _ready carried on), but it orphaned the half-built panel on every
## such scene and buried real errors under 67 lines per gate. The indicator now returns when there is no UI.

const BattleStateHelper := preload("res://test/unit/helpers/battle_state.gd")
const BattleSceneScript := preload("res://src/battle/BattleScene.gd")

var _bm: RefCounted = null


func before_each() -> void:
	_bm = BattleStateHelper.new()
	_bm.snapshot()


func after_each() -> void:
	if _bm != null:
		_bm.restore()


func _orphans() -> int:
	return int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))


func test_a_script_built_scene_orphans_no_speed_panel() -> void:
	var before := _orphans()
	var scene = BattleSceneScript.new()
	add_child(scene)
	await get_tree().process_frame
	assert_null(scene.get_node_or_null("UI"), "SCOPE: a script-built scene has no UI node")
	remove_child(scene)
	scene.free()
	await get_tree().process_frame
	assert_eq(_orphans() - before, 0, "building and freeing a UI-less scene must leave no orphaned speed panel behind")


func test_the_real_scene_still_builds_its_speed_readout() -> void:
	var scene = load("res://src/battle/BattleScene.tscn").instantiate()
	add_child_autofree(scene)
	await get_tree().process_frame
	assert_not_null(scene.get_node_or_null("UI/SpeedPanel"), "CONTROL: with a UI the speed readout is still built")
