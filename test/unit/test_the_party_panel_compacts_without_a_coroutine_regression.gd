extends GutTest

## .841-.843 gates: 35-52 engine ERRORs per run, "Resumed function '_compact_party_panel()' after await, but class instance is gone".
## Compaction awaited process_frame in a loop, so a scene freed mid-step resumed dead; it now steps on a frame connection.
## GUT 9.4 cannot see engine errors, so the seat counts that line in this file's own log (as the lunge fix did).

const SCENE := preload("res://src/battle/BattleScene.gd")
const UIManager := preload("res://src/battle/BattleUIManager.gd")


## A script-only scene with a PARTY panel whose bottom sits at `bottom_y`.
func _scene(bottom_y: float) -> Node:
	var scene = SCENE.new()
	add_child(scene)
	var ui := Control.new()
	ui.name = "UI"
	scene.add_child(ui)
	var panel := Control.new()
	panel.name = "PartyStatusPanel"
	panel.position = Vector2(0, bottom_y - 40.0)
	panel.size = Vector2(200, 40)
	ui.add_child(panel)
	scene._ui_manager = UIManager.new(scene)
	scene._party_compacting = false
	return scene


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _tree_holds_a_dead_compaction() -> bool:
	for c in get_tree().process_frame.get_connections():
		var cb: Callable = c["callable"]
		if cb.get_method() == "_compact_party_panel_tick" and not is_instance_valid(cb.get_object()):
			return true
	return false


func test_control_an_overrunning_panel_drops_every_tier_and_stops() -> void:
	var scene := _scene(get_viewport().get_visible_rect().size.y + 200.0)
	scene._compact_party_panel()
	assert_true(scene._party_compacting, "CONTROL: compaction started")
	await _frames(12)
	assert_eq(scene._ui_manager.party_compact_tier, UIManager.PARTY_COMPACT_TIERS.size(), "an overrun panel drops one tier per settled layout until none is left")
	assert_false(scene._party_compacting, "and compaction ends when nothing is left to drop")
	assert_false(get_tree().process_frame.is_connected(scene._compact_party_panel_tick), "and lets go of the frame signal")
	scene.free()


func test_control_a_panel_that_fits_drops_nothing() -> void:
	var scene := _scene(100.0)
	scene._compact_party_panel()
	await _frames(6)
	assert_eq(scene._ui_manager.party_compact_tier, 0, "a panel inside its floor keeps every row")
	assert_false(scene._party_compacting, "and compaction ends")
	scene.free()


func test_a_scene_freed_mid_compaction_leaves_nothing_to_resume() -> void:
	var scene := _scene(get_viewport().get_visible_rect().size.y + 200.0)
	scene._compact_party_panel()
	await _frames(1)
	assert_true(scene._party_compacting, "CONTROL: the scene is freed while a step is still waiting")
	scene.free()
	await _frames(6)
	assert_false(_tree_holds_a_dead_compaction(), "a freed scene must leave no compaction step on the tree's frame signal")


func test_a_scene_leaving_the_tree_mid_compaction_stops_it() -> void:
	var scene := _scene(get_viewport().get_visible_rect().size.y + 200.0)
	scene._compact_party_panel()
	remove_child(scene)
	await _frames(4)
	assert_false(scene._party_compacting, "a scene taken out of the tree ends its compaction")
	assert_false(get_tree().process_frame.is_connected(scene._compact_party_panel_tick), "and lets go of the frame signal")
	scene.free()
