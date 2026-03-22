extends SceneTree

## Smoke test for the battle system end-to-end.
## Usage: godot --headless -s test/smoke/test_battle_smoke.gd
##
## Tests that:
## - BattleScene instantiates and initializes without errors
## - BattleManager starts a battle with player and enemy combatants
## - Party sprite nodes and enemy sprite nodes are created
## - BattleTransition autoload is present
## - BattleManager state transitions correctly out of INACTIVE
##
## Exits with code 0 on full pass, code 1 on any failure.

const BATTLE_SCENE_PATH = "res://src/battle/BattleScene.tscn"
const GLOBAL_TIMEOUT_SEC = 12.0
const BATTLE_LOAD_TIMEOUT_SEC = 5.0

var _pass_count: int = 0
var _fail_count: int = 0
var _battle_scene: Node = null
var _timed_out: bool = false
var _test_ran: bool = false


func _init() -> void:
	# Use _init to hook into the tree as early as possible.
	# All autoloads are registered by the time _init fires in -s mode,
	# though their scripts may have partially-failed compilation.
	# We use call_deferred so one full frame passes, giving all autoloads
	# a chance to finish their _ready() calls before we inspect them.
	call_deferred("_start_suite")


func _start_suite() -> void:
	if _test_ran:
		return
	_test_ran = true

	# Global timeout guard
	var timer = create_timer(GLOBAL_TIMEOUT_SEC)
	timer.timeout.connect(_on_global_timeout)

	print("[SMOKE] Starting battle smoke tests...")
	print("")

	await _test_battle_transition_autoload()
	if _timed_out: return

	await _test_battle_manager_autoload()
	if _timed_out: return

	await _test_battle_scene_instantiates()
	if _timed_out: return

	await _test_battle_has_players()
	if _timed_out: return

	await _test_battle_has_enemies()
	if _timed_out: return

	await _test_battle_manager_active()
	if _timed_out: return

	await _test_party_sprite_nodes()
	if _timed_out: return

	await _test_enemy_sprite_nodes()
	if _timed_out: return

	await _test_battle_scene_visible()
	if _timed_out: return

	await _test_battle_transition_structure()
	if _timed_out: return

	_print_results()
	quit(0 if _fail_count == 0 else 1)


func _on_global_timeout() -> void:
	if _timed_out:
		return
	_timed_out = true
	print("")
	print("[SMOKE] GLOBAL TIMEOUT after %.0fs — force exiting" % GLOBAL_TIMEOUT_SEC)
	_record("global_timeout_guard", false,
		"Test suite timed out after %ds" % int(GLOBAL_TIMEOUT_SEC))
	_print_results()
	quit(1)


# -----------------------------------------------------------------------
# Individual tests
# -----------------------------------------------------------------------

func _test_battle_transition_autoload() -> void:
	var bt = _get_autoload("BattleTransition")
	if bt == null:
		_record("test_battle_transition_autoload", false,
			"BattleTransition autoload not found in tree")
	else:
		_record("test_battle_transition_autoload", true, "")


func _test_battle_manager_autoload() -> void:
	var bm = _get_autoload("BattleManager")
	if bm == null:
		_record("test_battle_manager_autoload", false,
			"BattleManager autoload not found in tree")
		return

	# Use 'in' operator to check properties/methods safely — avoids crash when
	# the autoload script had a compile error and the node is a bare Node.
	var has_start   = bm.has_method("start_battle")
	var has_active  = bm.has_method("is_battle_active")
	var has_players = "player_party" in bm
	var has_enemies = "enemy_party" in bm

	if not has_start or not has_active or not has_players or not has_enemies:
		var missing: Array[String] = []
		if not has_start:   missing.append("start_battle()")
		if not has_active:  missing.append("is_battle_active()")
		if not has_players: missing.append("player_party")
		if not has_enemies: missing.append("enemy_party")
		_record("test_battle_manager_autoload", false,
			"BattleManager script not fully loaded — missing: %s" % ", ".join(missing))
	else:
		_record("test_battle_manager_autoload", true, "")


func _test_battle_scene_instantiates() -> void:
	var scene_res = load(BATTLE_SCENE_PATH)
	if scene_res == null:
		_record("test_battle_scene_instantiates", false,
			"Failed to load %s" % BATTLE_SCENE_PATH)
		return

	_battle_scene = scene_res.instantiate()
	if _battle_scene == null:
		_record("test_battle_scene_instantiates", false, "instantiate() returned null")
		return

	root.add_child(_battle_scene)

	# Allow _ready() and all deferred calls to complete (3 frames is sufficient)
	await _wait_frames(3)

	_record("test_battle_scene_instantiates", true, "")


func _test_battle_has_players() -> void:
	if _battle_scene == null:
		_record("test_battle_has_players", false,
			"BattleScene not instantiated (prerequisite failed)")
		return

	var bm = _get_autoload("BattleManager")
	if bm == null or not ("player_party" in bm):
		_record("test_battle_has_players", false, "BattleManager unavailable")
		return

	var deadline_ms = Time.get_ticks_msec() + int(BATTLE_LOAD_TIMEOUT_SEC * 1000)
	while (bm.player_party as Array).size() == 0 \
			and Time.get_ticks_msec() < deadline_ms \
			and not _timed_out:
		await _wait_frames(1)

	var count: int = (bm.player_party as Array).size()
	if count == 0:
		_record("test_battle_has_players", false,
			"player_party empty after %.1fs" % BATTLE_LOAD_TIMEOUT_SEC)
	else:
		_record("test_battle_has_players", true, "%d player(s)" % count)


func _test_battle_has_enemies() -> void:
	if _battle_scene == null:
		_record("test_battle_has_enemies", false,
			"BattleScene not instantiated (prerequisite failed)")
		return

	var bm = _get_autoload("BattleManager")
	if bm == null or not ("enemy_party" in bm):
		_record("test_battle_has_enemies", false, "BattleManager unavailable")
		return

	var deadline_ms = Time.get_ticks_msec() + int(BATTLE_LOAD_TIMEOUT_SEC * 1000)
	while (bm.enemy_party as Array).size() == 0 \
			and Time.get_ticks_msec() < deadline_ms \
			and not _timed_out:
		await _wait_frames(1)

	var count: int = (bm.enemy_party as Array).size()
	if count == 0:
		_record("test_battle_has_enemies", false,
			"enemy_party empty after %.1fs" % BATTLE_LOAD_TIMEOUT_SEC)
	else:
		_record("test_battle_has_enemies", true, "%d enemy/enemies" % count)


func _test_battle_manager_active() -> void:
	var bm = _get_autoload("BattleManager")
	if bm == null or not bm.has_method("is_battle_active"):
		_record("test_battle_manager_active", false, "BattleManager unavailable")
		return

	var deadline_ms = Time.get_ticks_msec() + int(BATTLE_LOAD_TIMEOUT_SEC * 1000)
	while not bm.is_battle_active() \
			and Time.get_ticks_msec() < deadline_ms \
			and not _timed_out:
		await _wait_frames(1)

	if not bm.is_battle_active():
		var state_name := "UNKNOWN"
		if "current_state" in bm:
			# BattleManager.BattleState enum isn't accessible outside the autoload in -s mode;
			# read the integer and map manually.
			var s: int = bm.current_state
			var names = ["INACTIVE","STARTING","SELECTION_PHASE","PLAYER_SELECTING",
				"ENEMY_SELECTING","EXECUTION_PHASE","PROCESSING_ACTION","VICTORY","DEFEAT"]
			if s >= 0 and s < names.size():
				state_name = names[s]
			else:
				state_name = str(s)
		_record("test_battle_manager_active", false,
			"Still INACTIVE after %.1fs (state=%s)" % [BATTLE_LOAD_TIMEOUT_SEC, state_name])
	else:
		var state_name := "ACTIVE"
		if "current_state" in bm:
			var s: int = bm.current_state
			var names = ["INACTIVE","STARTING","SELECTION_PHASE","PLAYER_SELECTING",
				"ENEMY_SELECTING","EXECUTION_PHASE","PROCESSING_ACTION","VICTORY","DEFEAT"]
			if s >= 0 and s < names.size():
				state_name = names[s]
		_record("test_battle_manager_active", true, "state=%s" % state_name)


func _test_party_sprite_nodes() -> void:
	if _battle_scene == null:
		_record("test_party_sprite_nodes", false,
			"BattleScene not instantiated (prerequisite failed)")
		return

	if not ("party_sprite_nodes" in _battle_scene):
		_record("test_party_sprite_nodes", false,
			"BattleScene missing party_sprite_nodes property")
		return

	var nodes := _battle_scene.party_sprite_nodes as Array
	if nodes.size() == 0:
		_record("test_party_sprite_nodes", false, "party_sprite_nodes is empty")
	else:
		_record("test_party_sprite_nodes", true, "%d party sprite(s)" % nodes.size())


func _test_enemy_sprite_nodes() -> void:
	if _battle_scene == null:
		_record("test_enemy_sprite_nodes", false,
			"BattleScene not instantiated (prerequisite failed)")
		return

	if not ("enemy_sprite_nodes" in _battle_scene):
		_record("test_enemy_sprite_nodes", false,
			"BattleScene missing enemy_sprite_nodes property")
		return

	var nodes := _battle_scene.enemy_sprite_nodes as Array
	if nodes.size() == 0:
		_record("test_enemy_sprite_nodes", false, "enemy_sprite_nodes is empty")
	else:
		_record("test_enemy_sprite_nodes", true, "%d enemy sprite(s)" % nodes.size())


func _test_battle_scene_visible() -> void:
	if _battle_scene == null:
		_record("test_battle_scene_visible", false,
			"BattleScene not instantiated (prerequisite failed)")
		return

	if not _battle_scene.is_inside_tree():
		_record("test_battle_scene_visible", false, "BattleScene not in the scene tree")
		return

	var visible: bool = true
	if "visible" in _battle_scene:
		visible = _battle_scene.visible

	if not visible:
		_record("test_battle_scene_visible", false, "BattleScene.visible == false")
	else:
		_record("test_battle_scene_visible", true, "in tree and marked visible")


func _test_battle_transition_structure() -> void:
	var bt = _get_autoload("BattleTransition")
	if bt == null:
		_record("test_battle_transition_structure", false, "BattleTransition not found")
		return

	var missing: Array[String] = []
	if not bt.has_method("play_battle_transition"):
		missing.append("play_battle_transition()")
	if not bt.has_method("fade_out"):
		missing.append("fade_out()")
	if not bt.has_signal("transition_midpoint"):
		missing.append("signal:transition_midpoint")

	if missing.size() > 0:
		_record("test_battle_transition_structure", false,
			"Missing: %s" % ", ".join(missing))
	else:
		_record("test_battle_transition_structure", true,
			"play_battle_transition, fade_out, transition_midpoint all present")


# -----------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------

func _get_autoload(autoload_name: String) -> Node:
	return root.get_node_or_null("/root/" + autoload_name)


func _wait_frames(n: int) -> void:
	for _i in range(n):
		await process_frame


func _record(test_name: String, passed: bool, detail: String) -> void:
	if passed:
		_pass_count += 1
	else:
		_fail_count += 1

	var label := "PASS" if passed else "FAIL"
	# Pad test name to 45 chars for alignment
	var padded := test_name
	while padded.length() < 45:
		padded = " " + padded

	if detail == "":
		print("[SMOKE] %s ... %s" % [padded, label])
	elif passed:
		print("[SMOKE] %s ... %s  -- %s" % [padded, label, detail])
	else:
		print("[SMOKE] %s ... %s (%s)" % [padded, label, detail])


func _print_results() -> void:
	var total := _pass_count + _fail_count
	print("")
	print("[SMOKE] -------------------------------------------")
	if _fail_count == 0:
		print("[SMOKE] RESULT: %d/%d passed - ALL PASS" % [_pass_count, total])
	else:
		print("[SMOKE] RESULT: %d/%d passed, %d FAILED" % [_pass_count, total, _fail_count])
	print("[SMOKE] -------------------------------------------")
