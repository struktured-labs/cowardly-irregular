extends GutTest

## Regression (found in the .587 gate's SCRIPT ERRORs, "Out of bounds get index '0'" in _add_and_condition): an empty
## autogrind profile makes the grid editor skip building and open the Rule Composer. Cancelling the composer rebuilt
## nothing, so the player was left on a grid with zero rules, and the first add-condition crashed on rules[0].
## Cancelling on an empty profile now seeds the same default rule the non-splash path does.

const AutogrindState := preload("res://test/unit/helpers/autogrind_state.gd")
const ABProfiles := preload("res://test/unit/helpers/autobattle_profiles.gd")
const ED := "res://src/ui/autogrind/AutogrindGridEditor.gd"

var _ag_state: Dictionary
var _ab_entry: Dictionary = {}
var _ed: Node = null


func before_each() -> void:
	_ag_state = AutogrindState.snapshot()
	_ab_entry = ABProfiles.snapshot(AutobattleSystem)
	AutogrindSystem._test_disable_persistence = true


func after_each() -> void:
	if _ed and is_instance_valid(_ed):
		_ed.queue_free()
	_ed = null
	AutogrindSystem._test_disable_persistence = false
	AutogrindState.restore(_ag_state)
	ABProfiles.restore(AutobattleSystem, _ab_entry)


func _editor_on_an_empty_profile() -> Node:
	AutogrindSystem._ensure_autogrind_profiles()
	var data: Dictionary = AutogrindSystem.autogrind_profiles
	var idx := int(data.get("active", 0))
	(data["profiles"][idx] as Dictionary)["rules"] = []
	var vp := SubViewport.new()
	vp.size = Vector2i(1280, 720)
	add_child_autofree(vp)
	_ed = load(ED).new()
	vp.add_child(_ed)
	await get_tree().process_frame
	_ed.setup([])
	await get_tree().process_frame
	await get_tree().process_frame
	return _ed


func test_cancelling_the_composer_leaves_a_rule_to_edit() -> void:
	var ed: Node = await _editor_on_an_empty_profile()
	assert_true(ed.rules.is_empty(), "SCOPE: the profile is empty, so the editor took the composer splash")
	assert_not_null(ed._rule_composer_overlay, "SCOPE: the splash opened the composer")
	if ed._rule_composer_overlay == null:
		return
	ed._rule_composer_overlay.cancelled.emit()
	assert_eq(ed.rules.size(), 1, "a cancelled composer must leave the default rule, not an empty grid")


func test_cancelling_the_composer_builds_the_grid() -> void:
	var ed: Node = await _editor_on_an_empty_profile()
	if ed._rule_composer_overlay == null:
		fail_test("SCOPE: the splash did not open the composer")
		return
	ed._rule_composer_overlay.cancelled.emit()
	await get_tree().process_frame
	assert_not_null(ed._grid_container, "the grid is built after a cancel, not left absent")
	assert_gt(ed._grid_container.get_child_count() if ed._grid_container else 0, 0, "the seeded rule is drawn as cells")
	ed._add_and_condition()
	assert_eq(ed.rules.size(), 1, "CONTROL: an editor input on the seeded rule runs (it aborted on rules[0] before)")
