extends GutTest

## Opening a mimic shows "It has teeth." for 0.6s and does not lock the field.
## Cancel in that window opens the overworld menu (pause does not stop the timer).
## The timer then sets chest_<id> and emits battle_triggered. GameLoop drops that
## emit while the menu is open, a battle transition is already starting, or a
## world dissolve is in flight. The chest stays spent and the ambush never happens.
## Leaving the floor skips a spent chest, so the mimic is gone.

const ContrarianDepthsScript = preload("res://src/maps/dungeons/ContrarianDepths.gd")
const MimicChestScript = preload("res://src/exploration/MimicChest.gd")
const GameLoopScript = preload("res://src/GameLoop.gd")

const _LOCK := "mimic_ambush"

var _stub: Node = null
var _cid: String = ""
var _flavor_was_set: bool = false
var _flavor_before: Variant = null


class RefusalStub extends Node:
	var drop: bool = true
	func battle_trigger_would_be_dropped() -> bool:
		return drop


func after_each() -> void:
	if InputLockManager and InputLockManager.has_lock(_LOCK):
		InputLockManager.pop_lock(_LOCK)
	if InputLockManager and InputLockManager.has_lock("world_transition"):
		InputLockManager.pop_lock("world_transition")
	if _cid != "":
		GameState.story_flags.erase("chest_" + _cid)
		_cid = ""
	if GameState and "game_constants" in GameState:
		if _flavor_was_set:
			GameState.game_constants["pending_battle_flavor_line"] = _flavor_before
		else:
			GameState.game_constants.erase("pending_battle_flavor_line")
		_flavor_was_set = false
	if _stub != null and is_instance_valid(_stub):
		_stub.free()
		_stub = null


func _remember_flavor() -> void:
	_flavor_was_set = GameState.game_constants.has("pending_battle_flavor_line")
	_flavor_before = GameState.game_constants.get("pending_battle_flavor_line", null)


func _new_mimic() -> MimicChest:
	_cid = "zz_mimic_refused_%d" % Time.get_ticks_usec()
	var chest := MimicChestScript.new()
	chest.chest_id = _cid
	chest.mimic_monster_id = "treasure_mimic"
	var fake_cave := ContrarianDepthsScript.new()
	autofree(fake_cave)
	chest.cave_ref = fake_cave
	add_child(chest)
	return chest


func test_a_refused_ambush_does_not_spend_the_mimic() -> void:
	_remember_flavor()
	_stub = RefusalStub.new()
	_stub.name = "GameLoop"
	get_tree().root.add_child(_stub)
	var chest := _new_mimic()
	var battle_fired := [false]
	chest.cave_ref.battle_triggered.connect(func(_enemies: Array) -> void:
		battle_fired[0] = true
	)

	chest._open_chest(null)
	await get_tree().create_timer(0.8).timeout

	assert_false(GameState.get_story_flag("chest_" + _cid),
		"a mimic whose ambush the field refused must stay closed — spending it deletes the chest with no fight")
	assert_false(battle_fired[0],
		"a refused ambush must not emit battle_triggered")
	assert_false(chest._ambush_started,
		"the player has to be able to open the same mimic again once the menu or transition is gone")
	var leftover := str(GameState.game_constants.get("pending_battle_flavor_line", ""))
	assert_false(leftover in MimicChestScript._TELLS,
		"a fight that never started must not leave the mimic's tell on the next battle")

	# The first open already spent it on the broken path. Clear that and require a NEW ambush.
	GameState.story_flags.erase("chest_" + _cid)
	battle_fired[0] = false
	_stub.drop = false
	chest._open_chest(null)
	await get_tree().create_timer(0.8).timeout
	assert_true(battle_fired[0],
		"the same mimic still ambushes once the field will accept the fight")
	assert_true(GameState.get_story_flag("chest_" + _cid),
		"the chest is spent only when that later ambush is actually emitted")


func test_the_teeth_line_freezes_the_field() -> void:
	_remember_flavor()
	var chest := _new_mimic()
	chest._open_chest(null)
	assert_true(InputLockManager.has_lock(_LOCK),
		"It has teeth. must lock the field — cancel opens the menu, the timer still fires, and the ambush is dropped after the chest is spent")
	chest.queue_free()
	await get_tree().process_frame
	assert_false(InputLockManager.has_lock(_LOCK),
		"removing the mimic during the line must release the lock — a floor change used to delete it")
	assert_false(GameState.get_story_flag("chest_" + _cid),
		"a mimic removed before its battle must still be closed")


func test_an_open_menu_is_a_reason_to_drop_the_ambush() -> void:
	var gl: Node = autofree(GameLoopScript.new())
	assert_true(gl.has_method("battle_trigger_would_be_dropped"),
		"GameLoop must answer whether it would drop a battle, so a mimic can refuse to spend itself")
	if not gl.has_method("battle_trigger_would_be_dropped"):
		return
	assert_false(bool(gl.call("battle_trigger_would_be_dropped")),
		"exploration with nothing open must accept a battle")
	gl._battle_transition_starting = true
	assert_true(bool(gl.call("battle_trigger_would_be_dropped")),
		"a battle transition already starting drops a second trigger")
	gl._battle_transition_starting = false
	gl._transition_in_progress = true
	assert_true(bool(gl.call("battle_trigger_would_be_dropped")),
		"an area transition in flight drops the encounter")
	gl._transition_in_progress = false
	gl.current_state = GameLoopScript.LoopState.BATTLE
	assert_true(bool(gl.call("battle_trigger_would_be_dropped")),
		"a battle trigger outside exploration is dropped")
	gl.current_state = GameLoopScript.LoopState.EXPLORATION
	var menu := Control.new()
	autofree(menu)
	gl._overworld_menu = menu
	assert_true(bool(gl.call("battle_trigger_would_be_dropped")),
		"an open overworld menu is why the mimic's emit is dropped after the chest is spent")
	gl._overworld_menu = null
	var editor := Control.new()
	autofree(editor)
	gl._autobattle_editor = editor
	assert_true(bool(gl.call("battle_trigger_would_be_dropped")),
		"an open autobattle editor drops the encounter")
	gl._autobattle_editor = null
	var grind := Control.new()
	grind.visible = true
	add_child(grind)
	gl._autogrind_ui = grind
	assert_true(bool(gl.call("battle_trigger_would_be_dropped")),
		"an open autogrind console drops the encounter")
	gl._autogrind_ui = null
	grind.queue_free()
	InputLockManager.push_lock("world_transition")
	assert_true(bool(gl.call("battle_trigger_would_be_dropped")),
		"a world dissolve suppresses battle entry after the caller has already committed")
	InputLockManager.pop_lock("world_transition")
