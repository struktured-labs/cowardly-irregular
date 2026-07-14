extends GutTest

## tick 409: BattleManager exposes meta_autobattle_editor_requested
## signal that BattleScene listens for. The Scriptweaver's
## create_autobattle_script meta ability emits this signal when the
## cast lands, so the editor opens immediately instead of waiting
## for the next poll.
##
## Pairs with the existing meta_autobattle_editor_requested
## game_constant flag — flag is the durable signal for post-battle /
## mid-frame readers; this signal is the immediate hook for the
## BattleScene UI.

const BATTLE_MANAGER_PATH := "res://src/battle/BattleManager.gd"
const BATTLE_SCENE_PATH := "res://src/battle/BattleScene.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


func test_signal_declared_on_battle_manager() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	assert_true(src.contains("signal meta_autobattle_editor_requested(caster: Combatant)"),
		"BattleManager must declare meta_autobattle_editor_requested signal")


func test_autobattle_editor_arm_emits_signal() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	var arm_idx: int = src.find("\"autobattle_editor\":")
	assert_gt(arm_idx, -1)
	var window: String = src.substr(arm_idx, 1000)
	assert_true(window.contains("meta_autobattle_editor_requested.emit(caster)"),
		"autobattle_editor arm must emit the new signal with caster")


func test_battle_scene_connects_signal() -> void:
	var src := _read(BATTLE_SCENE_PATH)
	assert_true(src.contains("meta_autobattle_editor_requested.connect"),
		"BattleScene must connect to meta_autobattle_editor_requested")
	assert_true(src.contains("func _on_meta_autobattle_editor_requested"),
		"BattleScene must define the handler _on_meta_autobattle_editor_requested")


func test_handler_clears_flag() -> void:
	var src := _read(BATTLE_SCENE_PATH)
	var fn_idx: int = src.find("func _on_meta_autobattle_editor_requested")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	# Clear the game_constants flag after handling so a follow-up
	# save/load doesn't accidentally re-open the editor.
	assert_true(body.contains("meta_autobattle_editor_requested\"] = false"),
		"handler must clear meta_autobattle_editor_requested after opening the editor")
	assert_true(body.contains("_open_autobattle_editor_for(caster)"),
		"handler must open the editor for the caster")
