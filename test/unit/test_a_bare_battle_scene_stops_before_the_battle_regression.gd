extends GutTest

## 16 test files stand up `load("res://src/battle/BattleScene.gd").new()` — the bare script, with none of
## BattleScene.tscn's nodes — to host a command menu. Its `_ready` died at `btn_attack.pressed.connect` on a
## null button, logging 2 SCRIPT ERRORs per instance (with RetroFont.configure_battle_log(null)): 100 of the
## 215 in a full gate run (cowir-main's run_tests_last.337251.log, 2026-09-28).
## ⛔ THAT CRASH WAS LOAD-BEARING: `_ready` ENDS with set_autobattle_script("Aggressive") and
## _start_test_battle(), so the abort was the only thing keeping 16 tests from starting a real battle and
## leaking the BattleManager autoload. BattleScene now returns at that line when the .tscn nodes are absent.
## These arms pin what the crash used to hold by accident, and that the real scene is unchanged.

const BattleStateHelper := preload("res://test/unit/helpers/battle_state.gd")
const SoundState := preload("res://test/unit/helpers/sound_state.gd")
const SENTINEL := {"name": "sentinel-not-a-real-script"}

var _bm: RefCounted = null


func before_each() -> void:
	_bm = BattleStateHelper.new()
	_bm.snapshot()


func after_each() -> void:
	if _bm != null:
		_bm.restore()


func after_all() -> void:
	SoundState.restore()


func _connections_to(target: Object) -> int:
	var n := 0
	for sig in BattleManager.get_signal_list():
		for c in BattleManager.get_signal_connection_list(sig["name"]):
			var cb: Callable = c["callable"]
			if cb.get_object() == target:
				n += 1
	return n


func test_a_bare_battle_scene_never_starts_a_battle() -> void:
	BattleManager.autobattle_script = SENTINEL.duplicate()
	var active_before: bool = BattleManager.is_battle_active()
	var scene: Node = load("res://src/battle/BattleScene.gd").new()
	add_child_autofree(scene)
	await get_tree().process_frame
	assert_not_null(scene._command_menu, "CONTROL: _ready ran far enough to build what the tests use")
	assert_eq(scene.party_members.size(), 0, "a bare BattleScene built the default party — it started a battle")
	assert_eq(BattleManager.is_battle_active(), active_before, "a bare BattleScene changed whether a battle is active")
	assert_eq(str(BattleManager.autobattle_script.get("name", "")), SENTINEL["name"],
		"a bare BattleScene replaced the autoload's autobattle script")


func test_the_real_battle_scene_still_starts_its_battle() -> void:
	BattleManager.autobattle_script = SENTINEL.duplicate()
	var scene: Node = load("res://src/battle/BattleScene.tscn").instantiate()
	add_child_autofree(scene)
	await get_tree().process_frame
	assert_not_null(scene.btn_attack, "CONTROL: the .tscn carries the command buttons")
	assert_gt(scene.party_members.size(), 0, "the real BattleScene must still start its battle on _ready")
	assert_ne(str(BattleManager.autobattle_script.get("name", "")), SENTINEL["name"],
		"the real BattleScene must still load its default autobattle script")


func test_leaving_the_tree_disconnects_every_battle_manager_signal() -> void:
	var scene: Node = load("res://src/battle/BattleScene.gd").new()
	add_child(scene)
	await get_tree().process_frame
	var live := _connections_to(scene)
	assert_gt(live, 10, "CONTROL: the bare _ready connected BattleManager signals before stopping (%d)" % live)
	remove_child(scene)
	var left := _connections_to(scene)
	scene.free()
	assert_eq(left, 0, "%d BattleManager connections still point at a BattleScene that left the tree" % left)
