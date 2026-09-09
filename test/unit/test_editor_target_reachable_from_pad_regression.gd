extends GutTest

## Choosing WHO an autobattle action targets was keyboard-only and advertised nowhere.
##
## MEASURED by sweeping bindings against legends (the reverse of the legend-truth ratchet):
## AutobattleGridEditor binds KEY_C, KEY_F5 and KEY_T while naming none of them on any legend.
## KEY_T is the one that matters — `_open_target_picker` had exactly ONE caller, that key, and it
## is the only route to `kind: "target_type"`. Picking an ability assigns a DEFAULT target from the
## ability's own target_type, so a pad player got that default and could never change it. Targeting
## decides what a rule does: "heal lowest_hp_ally" and "heal self" are different rules.

const ED := "res://src/ui/autobattle/AutobattleGridEditor.gd"

var _vp: SubViewport = null
var _ed: Node = null


## Own viewport per test — the shared one latches is_input_handled() and disarms later arms.
func before_each() -> void:
	_vp = SubViewport.new()
	_vp.size = Vector2i(1280, 720)
	add_child_autofree(_vp)
	_ed = load(ED).new()
	_vp.add_child(_ed)
	_ed.setup("hero", "Hero")
	await get_tree().process_frame
	await get_tree().process_frame


func after_each() -> void:
	if _ed and is_instance_valid(_ed):
		_ed.queue_free()
	_ed = null


## Behavioural: the ring must actually offer it. A source pin passes on a row that dispatches
## nowhere, which is the exact hollowness this file family keeps hitting.
func test_the_pad_ring_offers_targeting() -> void:
	_ed._portrait_focused = true
	var left := InputEventAction.new()
	left.action = "ui_left"
	left.pressed = true
	_ed._input(left)
	assert_not_null(_ed._option_picker, "PRECONDITION: D-pad left from the portrait opens the ring")
	var spec: Dictionary = _ed._option_picker.get_meta("spec")
	var ids := []
	for opt in (spec.get("options", []) as Array):
		ids.append(str(opt.get("id", "")))
	assert_has(ids, "set_target",
		"the ring must offer targeting — it was the only way to choose who an action hits, and it was KEY_T only")


## Enumerate from the other side: the offered id must reach a method that exists.
func test_the_offered_id_dispatches_to_the_real_handler() -> void:
	var src := FileAccess.get_file_as_string(ED)
	var at := src.find("func _commit_more_action")
	assert_gt(at, -1, "the dispatcher must exist")
	var body := src.substr(at, src.find("\nfunc ", at + 10) - at)
	assert_true(body.contains('"set_target"'),
		"the offered id has no arm — the row would render and do nothing")
	assert_true(body.contains("_open_target_picker"),
		"and must call the SAME handler KEY_T calls, so pad and keyboard cannot drift")
	assert_true(_ed.has_method("_open_target_picker"), "which must exist on the class")
	assert_false(_ed.has_method("_zzq_not_a_handler"),
		"CONTROL: has_method must be able to say NO")


## The keyboard half was unadvertised too — T named on no legend in the file.
func test_the_legend_names_the_target_key() -> void:
	var src := FileAccess.get_file_as_string(ED)
	assert_true(src.contains("T:Target"),
		"a keyboard player had no way to learn T either — it appeared on no legend")


## The key must keep working; this adds a route, it replaces nothing.
func test_the_keyboard_route_survives() -> void:
	var src := FileAccess.get_file_as_string(ED)
	assert_true(src.contains("event.keycode == KEY_T"),
		"KEY_T must still open the target picker")


## CONTROL: targeting was genuinely absent before. If the ring had always carried it this file
## defends nothing, so pin that the OTHER established rows are still there beside it.
func test_the_ring_still_carries_its_existing_rows() -> void:
	_ed._portrait_focused = true
	var left := InputEventAction.new()
	left.action = "ui_left"
	left.pressed = true
	_ed._input(left)
	var spec: Dictionary = _ed._option_picker.get_meta("spec")
	var ids := []
	for opt in (spec.get("options", []) as Array):
		ids.append(str(opt.get("id", "")))
	for established in ["toggle_row", "export", "import", "compose"]:
		assert_has(ids, established, "%s must survive — the new row is an addition, not a replacement" % established)
