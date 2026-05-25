extends GutTest

## Regression tests for the W1 spotlight unlock pattern (2026-05-25).
##
## Design: 5-PC party from prologue. Non-lead PCs default autobattle_locked
## so their turn is forced through autobattle eval and their manual command
## menu + autobattle editor tab are hidden. Each spotlight cutscene flips
## the matching PC's autobattle_locked flag to false. Debug flag
## GameState.debug_all_pcs_unlocked overrides every lock at decision time.
##
## See cowir-story msgs 1751-1768 for the design thread.


const COMBATANT_PATH := "res://src/battle/Combatant.gd"
const GAMELOOP_PATH := "res://src/GameLoop.gd"
const GAMESTATE_PATH := "res://src/meta/GameState.gd"
const BATTLEMANAGER_PATH := "res://src/battle/BattleManager.gd"
const COMMANDMENU_PATH := "res://src/battle/BattleCommandMenu.gd"
const EDITOR_PATH := "res://src/ui/autobattle/AutobattleGridEditor.gd"


func _read(path: String) -> String:
	var file = FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "file should exist: %s" % path)
	var text = file.get_as_text()
	file.close()
	return text


func test_combatant_has_autobattle_locked_field() -> void:
	var text = _read(COMBATANT_PATH)
	assert_true(text.find("var autobattle_locked: bool") > -1,
		"Combatant must declare autobattle_locked: bool")
	assert_true(text.find("\"autobattle_locked\": autobattle_locked") > -1,
		"to_dict must persist autobattle_locked")
	assert_true(text.find("data.has(\"autobattle_locked\")") > -1,
		"from_dict must restore autobattle_locked from save data")


func test_combatant_autobattle_locked_roundtrips_through_save() -> void:
	# Direct instance test — flip the field, serialize, deserialize, assert.
	var combatant_script = load(COMBATANT_PATH)
	var c1 = combatant_script.new()
	c1.initialize({"name": "TestBard", "max_hp": 100, "max_mp": 100,
		"attack": 10, "defense": 10, "magic": 10, "speed": 10})
	c1.autobattle_locked = true
	var data = c1.to_dict()
	assert_true(data.has("autobattle_locked"), "to_dict must include autobattle_locked")
	assert_true(data["autobattle_locked"], "to_dict value should be true after we set it")

	var c2 = combatant_script.new()
	c2.from_dict(data)
	assert_true(c2.autobattle_locked,
		"Loaded combatant must have autobattle_locked=true after roundtrip")
	c1.free()
	c2.free()


func test_gamestate_has_debug_all_pcs_unlocked() -> void:
	var text = _read(GAMESTATE_PATH)
	assert_true(text.find("var debug_all_pcs_unlocked: bool") > -1,
		"GameState must declare debug_all_pcs_unlocked: bool (default false)")
	# Default must be false so the W1 spotlight arc plays normally.
	var line_start = text.find("debug_all_pcs_unlocked: bool")
	var line_end = text.find("\n", line_start)
	var line = text.substr(line_start, line_end - line_start)
	assert_true(line.find("= false") > -1,
		"debug_all_pcs_unlocked must default to false; got: %s" % line)


func test_cutscene_completion_flag_map_has_5_spotlight_entries() -> void:
	var text = _read(GAMELOOP_PATH)
	for job_id in ["fighter", "cleric", "mage", "rogue", "bard"]:
		var slug = "world1_spotlight_" + job_id
		var flag = "cutscene_flag_spotlight_unlocked_" + job_id
		assert_true(text.find("\"" + slug + "\"") > -1,
			"_CUTSCENE_COMPLETION_FLAGS must map %s (matches the cutscene JSON file ID)" % slug)
		assert_true(text.find("\"" + flag + "\"") > -1,
			"_CUTSCENE_COMPLETION_FLAGS must include %s flag" % flag)


func test_gameloop_has_reconcile_spotlight_locks() -> void:
	var text = _read(GAMELOOP_PATH)
	assert_true(text.find("func _reconcile_spotlight_locks()") > -1,
		"GameLoop must expose _reconcile_spotlight_locks()")
	# Must be called from _create_party (NG start) and _restore_party_from_save_data (load).
	var create_idx = text.find("func _create_party()")
	var create_end = text.find("\n\nfunc ", create_idx)
	var create_body = text.substr(create_idx, create_end - create_idx) if create_end > -1 else ""
	assert_true(create_body.find("_reconcile_spotlight_locks()") > -1,
		"_create_party must call _reconcile_spotlight_locks() to handle NG+/debug states")

	var restore_idx = text.find("func _restore_party_from_save_data()")
	var restore_end = text.find("\n\nfunc ", restore_idx)
	var restore_body = text.substr(restore_idx, restore_end - restore_idx) if restore_end > -1 else ""
	assert_true(restore_body.find("_reconcile_spotlight_locks()") > -1,
		"_restore_party_from_save_data must call _reconcile_spotlight_locks() after load")


func test_battle_manager_routes_locked_pcs_through_ai() -> void:
	var text = _read(BATTLEMANAGER_PATH)
	assert_true(text.find("is_spotlight_locked") > -1,
		"BattleManager._process_next_selection must compute is_spotlight_locked")
	assert_true(text.find("debug_all_pcs_unlocked") > -1,
		"BattleManager turn routing must honor debug_all_pcs_unlocked override")


func test_command_menu_suppresses_for_locked_pcs() -> void:
	var text = _read(COMMANDMENU_PATH)
	assert_true(text.find("autobattle_locked") > -1,
		"BattleCommandMenu.show_win98_command_menu must check autobattle_locked")
	assert_true(text.find("debug_all_pcs_unlocked") > -1,
		"BattleCommandMenu must honor debug_all_pcs_unlocked override")


func test_autobattle_editor_skips_locked_pcs_on_cycle() -> void:
	var text = _read(EDITOR_PATH)
	# _cycle_character must walk past locked PCs.
	var cycle_idx = text.find("func _cycle_character")
	var cycle_end = text.find("\n\nfunc ", cycle_idx)
	var body = text.substr(cycle_idx, cycle_end - cycle_idx) if cycle_end > -1 else ""
	assert_true(body.find("autobattle_locked") > -1,
		"_cycle_character must skip autobattle_locked PCs")
	assert_true(body.find("debug_all_pcs_unlocked") > -1,
		"_cycle_character must honor debug_all_pcs_unlocked override")


func test_starter_party_has_bard_as_5th_member() -> void:
	var text = _read(GAMELOOP_PATH)
	var create_idx = text.find("func _create_party()")
	var create_end = text.find("\nfunc _on_battle_ended", create_idx)
	var body = text.substr(create_idx, create_end - create_idx) if create_end > -1 else ""
	# Bard combatant must be created + appended to party.
	assert_true(body.find("var bard = Combatant.new()") > -1,
		"_create_party must create a Bard combatant")
	assert_true(body.find("JobSystem.assign_job(bard, \"bard\")") > -1,
		"Bard must be assigned the bard job")
	assert_true(body.find("EquipmentSystem.equip_weapon(bard, \"piano_scythe\")") > -1,
		"Bard must start equipped with piano_scythe (just shipped in d8d1824)")
	assert_true(body.find("bard.autobattle_locked = true") > -1,
		"Bard must start autobattle_locked (spotlight unlock via ch.7)")
	assert_true(body.find("party.append(bard)") > -1,
		"Bard must be appended to the party")
