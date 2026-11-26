extends GutTest

## Switching autogrind profiles was reachable only through the grind editor's Shift+Tab, a key no pad has.
## The console's OPTIONS ring now offers "Switch Profile: <name>", which saves this grid to its own profile first,
## then adopts the next profile's rules. A grid the validator refuses stays on screen, and so does a grind in progress.
## Arms: CONTROL (the ring offers the row, naming the active profile) · the row moves to the next profile and shows
## its rules · the grid on screen is saved to the profile it came from, a cleared one included · refused rules block the switch · a grind
## blocks the switch · one profile has nothing to switch to.

const AutogrindState := preload("res://test/unit/helpers/autogrind_state.gd")
const UI := "res://src/ui/autogrind/AutogrindUI.gd"
const PLANTED_RULE := {"enabled": true, "conditions": [{"type": "battles_done", "op": ">=", "value": 7}], "actions": [{"type": "stop_grinding"}]}

var _ag: Dictionary
var _vp: SubViewport
var _ui: Control


func before_each() -> void:
	_ag = AutogrindState.snapshot()
	AutogrindSystem._test_disable_persistence = true
	AutobattleSystem._test_disable_persistence = true
	_vp = SubViewport.new()
	_vp.size = Vector2i(1280, 720)
	add_child_autofree(_vp)
	_ui = load(UI).new()
	_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vp.add_child(_ui)
	await get_tree().process_frame
	_ui._is_grinding = false
	assert_gt(AutogrindSystem.get_autogrind_profiles().size(), 1, "PRECONDITION: the shipped set has a second profile to switch to")
	AutogrindSystem.set_active_autogrind_profile(0)
	_ui.rules = AutogrindSystem.get_autogrind_rules().duplicate(true)


func after_each() -> void:
	if _ui and is_instance_valid(_ui):
		_ui.queue_free()
	AutogrindState.restore(_ag)


func _row_label(id: String) -> String:
	for opt in (_ui._options_ring_spec().get("options", []) as Array):
		if str(opt.get("id", "")) == id:
			return str(opt.get("label", ""))
	return ""


func _profile_rules(i: int) -> Array:
	return (AutogrindSystem.get_autogrind_profiles()[i] as Dictionary).get("rules", []) as Array


func test_the_ring_offers_the_row_naming_the_active_profile() -> void:
	var label := _row_label("next_profile")
	assert_ne(label, "", "the options ring has no row to switch profiles, so a pad cannot reach it")
	assert_true(label.contains(AutogrindSystem.get_active_autogrind_profile_name()), "and the row names the profile in use: %s" % label)


func test_the_row_moves_to_the_next_profile_and_shows_its_rules() -> void:
	_ui._commit_autogrind_option("next_profile")
	assert_eq(AutogrindSystem.get_active_autogrind_profile_index(), 1, "the row did not move to the next profile")
	assert_eq(_ui.rules, AutogrindSystem.get_autogrind_rules(), "the console shows the old profile's rules after a switch")
	assert_true(_row_label("next_profile").contains(AutogrindSystem.get_active_autogrind_profile_name()), "and the row now names the new profile")


func test_the_grid_on_screen_is_saved_to_the_profile_it_came_from() -> void:
	_ui.rules = [PLANTED_RULE.duplicate(true)]
	assert_ne(_profile_rules(0), _ui.rules, "CONTROL: the planted grid is not yet in the profile")
	_ui._commit_autogrind_option("next_profile")
	assert_eq(AutogrindSystem.get_active_autogrind_profile_index(), 1, "PRECONDITION: the switch happened")
	assert_eq(_profile_rules(0), [PLANTED_RULE], "switching dropped the grid that was on screen instead of saving it to its profile")


func test_a_cleared_grid_is_saved_too() -> void:
	assert_false(_profile_rules(0).is_empty(), "CONTROL: the shipped first profile has rules to clear")
	_ui.rules = []
	_ui._commit_autogrind_option("next_profile")
	assert_eq(AutogrindSystem.get_active_autogrind_profile_index(), 1, "PRECONDITION: the switch happened")
	assert_eq(_profile_rules(0), [], "a grid the player cleared on purpose came back with its old rules after a switch")


func test_refused_rules_block_the_switch() -> void:
	var junk: Array = ["not a rule"]
	_ui.rules = junk.duplicate(true)
	_ui._commit_autogrind_option("next_profile")
	assert_eq(AutogrindSystem.get_active_autogrind_profile_index(), 0, "a grid the validator refuses must not be switched away from, or it is lost")
	assert_eq(_ui.rules, junk, "and the refused grid stays on screen")


func test_a_grind_blocks_the_switch() -> void:
	_ui._is_grinding = true
	_ui._commit_autogrind_option("next_profile")
	_ui._is_grinding = false
	assert_eq(AutogrindSystem.get_active_autogrind_profile_index(), 0, "switching mid-grind would change the rules the running grind reads")


func test_one_profile_has_nothing_to_switch_to() -> void:
	var profiles: Array = AutogrindSystem.autogrind_profiles.get("profiles", [])
	profiles.resize(1)
	assert_eq(AutogrindSystem.get_autogrind_profiles().size(), 1, "CONTROL: one profile left")
	var before: Array = _ui.rules.duplicate(true)
	_ui._commit_autogrind_option("next_profile")
	assert_eq(AutogrindSystem.get_active_autogrind_profile_index(), 0, "one profile stays active")
	assert_eq(_ui.rules, before, "and the grid is unchanged")
