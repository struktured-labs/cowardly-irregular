extends GutTest

## tick 412: create_restore_point meta_effect now actually pushes
## a snapshot onto save_history via the existing
## record_history_checkpoint helper. Pre-fix (tick 404) only set a
## flag with no consumer — 35 MP burned.
##
## record_history_checkpoint(true) bypasses the rewind_enabled
## gate (the meta ability IS the override), so a player who hasn't
## unlocked Time Mage rewind can still create restore points via
## the ability.

const BATTLE_MANAGER_PATH := "res://src/battle/BattleManager.gd"
const COMBATANT_PATH := "res://src/battle/Combatant.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


func _make(name_str: String) -> Combatant:
	var c_script: GDScript = load(COMBATANT_PATH)
	var c: Combatant = c_script.new()
	c.initialize({"name": name_str, "max_hp": 100, "max_mp": 100,
		"attack": 10, "defense": 10, "magic": 10, "speed": 10})
	add_child_autofree(c)
	return c


func test_arm_calls_record_history_checkpoint() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	var arm_idx: int = src.find("\"create_restore_point\":")
	assert_gt(arm_idx, -1)
	var window: String = src.substr(arm_idx, 1200)
	assert_true(window.contains("record_history_checkpoint(true)"),
		"create_restore_point arm must call record_history_checkpoint(true)")
	assert_true(window.contains("checkpointed"),
		"arm must surface success/failure via a checkpointed bool")


func test_arm_kept_flag_for_downstream() -> void:
	# Flag stays for any future UI consumer that wants to know "a
	# restore point was just created".
	var src := _read(BATTLE_MANAGER_PATH)
	var arm_idx: int = src.find("\"create_restore_point\":")
	var window: String = src.substr(arm_idx, 1200)
	assert_true(window.contains("meta_restore_point_pending\"] = true"),
		"arm must keep writing the flag for downstream awareness")


func test_record_history_checkpoint_force_bypasses_gate() -> void:
	# Sanity: the helper does what we expect for force=true.
	if not GameState:
		pending("GameState autoload required")
		return
	# Force false (no rewind unlock): rewind_enabled defaults to false.
	var prior_enabled: bool = bool(GameState.meta_features.get("rewind_enabled", false))
	GameState.meta_features["rewind_enabled"] = false
	var prior_history: int = GameState.save_history.size()
	# force=false should refuse.
	var soft_result: bool = GameState.record_history_checkpoint(false)
	assert_false(soft_result,
		"record_history_checkpoint(false) must refuse when rewind_enabled=false")
	assert_eq(GameState.save_history.size(), prior_history,
		"refused checkpoint must NOT push to save_history")
	# force=true should succeed regardless of the gate.
	var hard_result: bool = GameState.record_history_checkpoint(true)
	assert_true(hard_result,
		"record_history_checkpoint(true) must succeed regardless of rewind_enabled")
	assert_eq(GameState.save_history.size(), prior_history + 1,
		"forced checkpoint must push a snapshot to save_history")
	# Restore.
	GameState.meta_features["rewind_enabled"] = prior_enabled
	GameState.save_history.pop_back()  # remove our test snapshot


func test_runtime_arm_creates_checkpoint() -> void:
	# End-to-end: cast the meta ability, verify save_history grew.
	if not GameState:
		pending("GameState autoload required")
		return
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	if bm == null:
		pending("BattleManager autoload required")
		return
	var caster: Combatant = _make("TimeMage")
	var prior_history: int = GameState.save_history.size()
	var ability: Dictionary = {
		"id": "test_restore_point",
		"meta_effect": "create_restore_point",
	}
	bm._execute_meta_ability(caster, ability, [caster])
	assert_eq(GameState.save_history.size(), prior_history + 1,
		"create_restore_point meta cast must push a snapshot onto save_history")
	# Clean up.
	GameState.save_history.pop_back()
