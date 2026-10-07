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


## Read with NO frame between: _ready runs inside add_child, while other files' leftovers are only freed at a frame
## boundary (they moved a frame-spanning count by -3 in the gate), so this delta is the scene's own orphans.
func _orphans() -> int:
	return int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))


func test_a_script_built_scene_orphans_no_speed_panel() -> void:
	var scene = BattleSceneScript.new()
	var before := _orphans()
	add_child(scene)
	var leaked := _orphans() - before
	assert_null(scene.get_node_or_null("UI"), "SCOPE: a script-built scene has no UI node")
	remove_child(scene)
	scene.free()
	# The scene was itself an orphan until add_child: -1 is "the scene left the orphan set and nothing joined it".
	assert_eq(leaked, -1, "a UI-less scene's _ready must leave no orphaned speed panel behind")


func test_the_real_scene_still_builds_its_speed_readout() -> void:
	var scene = load("res://src/battle/BattleScene.tscn").instantiate()
	add_child_autofree(scene)
	await get_tree().process_frame
	assert_not_null(scene.get_node_or_null("UI/SpeedPanel"), "CONTROL: with a UI the speed readout is still built")
