extends GutTest

## Regression tests for the UI affordances paired with the W1 spotlight
## unlock engine (see test_spotlight_engine_regression.gd for the engine
## side). Covers: PartyStatusScreen [AUTO] badge, SettingsMenu debug-only
## Unlock toggle, TutorialHints spotlight_unlock entry. Catches silent
## drift in the informational display while the engine flips
## autobattle_locked under it.

const PARTY_STATUS_PATH := "res://src/ui/PartyStatusScreen.gd"
const SETTINGS_MENU_PATH := "res://src/ui/SettingsMenu.gd"
const TUTORIAL_HINTS_PATH := "res://src/ui/TutorialHints.gd"
const COMBATANT_PATH := "res://src/battle/Combatant.gd"


func _read(path: String) -> String:
	var file = FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "file should exist: %s" % path)
	var text = file.get_as_text()
	file.close()
	return text


func _find_node_recursive(root: Node, target_name: String) -> Node:
	if root.name == target_name:
		return root
	for child in root.get_children():
		var found = _find_node_recursive(child, target_name)
		if found:
			return found
	return null


func _build_locked_combatant(name_str: String, job_id: String, locked: bool):
	var combatant_script = load(COMBATANT_PATH)
	var c = combatant_script.new()
	c.initialize({"name": name_str, "max_hp": 100, "max_mp": 100,
		"attack": 10, "defense": 10, "magic": 10, "speed": 10})
	c.autobattle_locked = locked
	c.job = {"id": job_id, "name": job_id.capitalize()}
	return c


func _stand_up_party_status(party: Array):
	var screen_script = load(PARTY_STATUS_PATH)
	var screen = screen_script.new()
	add_child_autofree(screen)
	screen.party = party
	screen.focused_index = 0
	screen._build_ui()
	return screen


func test_party_status_renders_auto_badge_for_locked_pc() -> void:
	var c = _build_locked_combatant("TestMage", "mage", true)
	var prev_debug = false
	if GameState and "debug_all_pcs_unlocked" in GameState:
		prev_debug = GameState.debug_all_pcs_unlocked
		GameState.debug_all_pcs_unlocked = false

	var screen = _stand_up_party_status([c])
	assert_not_null(_find_node_recursive(screen, "AutoBadge"),
		"AUTO badge must materialize when PC.autobattle_locked == true")

	if GameState and "debug_all_pcs_unlocked" in GameState:
		GameState.debug_all_pcs_unlocked = prev_debug
	c.free()


func test_party_status_no_badge_when_unlocked() -> void:
	var c = _build_locked_combatant("TestFighter", "fighter", false)
	var screen = _stand_up_party_status([c])
	assert_null(_find_node_recursive(screen, "AutoBadge"),
		"AUTO badge must NOT appear for unlocked PCs")
	c.free()


func test_party_status_no_badge_when_debug_override_active() -> void:
	# autobattle_locked = true BUT debug_all_pcs_unlocked = true → hidden.
	# Mirrors BattleManager/BattleCommandMenu UI-gate semantics.
	var c = _build_locked_combatant("TestBard", "bard", true)
	var prev_debug = false
	if GameState and "debug_all_pcs_unlocked" in GameState:
		prev_debug = GameState.debug_all_pcs_unlocked
		GameState.debug_all_pcs_unlocked = true

	var screen = _stand_up_party_status([c])
	assert_null(_find_node_recursive(screen, "AutoBadge"),
		"AUTO badge must hide when debug_all_pcs_unlocked override is on")

	if GameState and "debug_all_pcs_unlocked" in GameState:
		GameState.debug_all_pcs_unlocked = prev_debug
	c.free()


func test_settings_menu_has_debug_unlock_toggle() -> void:
	var text = _read(SETTINGS_MENU_PATH)
	assert_true(text.find("var debug_all_pcs_unlocked: bool") > -1,
		"SettingsMenu must declare the debug_all_pcs_unlocked field")
	assert_true(text.find("\"debug_all_pcs_unlocked\"") > -1,
		"SettingsMenu._adjust_setting must dispatch the debug_all_pcs_unlocked toggle id")
	assert_true(text.find("_save_debug_all_pcs_unlocked_setting") > -1,
		"SettingsMenu must expose _save_debug_all_pcs_unlocked_setting helper")
	# Toggle is now always visible (the gate behind `debug_log_enabled` was
	# removed 2026-06-04 because users couldn't find the entry point). The
	# label still says "Debug:" so it's self-documenting. When we're ready
	# to ship, the right move is a per-build flag instead of a runtime
	# debug-log gate.
	assert_true(text.find("Debug: Unlock All Party") > -1,
		"Settings toggle label 'Debug: Unlock All Party' must be present")


func test_tutorial_hints_has_spotlight_unlock_entry() -> void:
	var text = _read(TUTORIAL_HINTS_PATH)
	assert_true(text.find("\"spotlight_unlock\"") > -1,
		"TutorialHints.HINTS must include a 'spotlight_unlock' entry for the engine to fire on flip")
