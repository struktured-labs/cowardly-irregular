extends GutTest

## struktured 2026-10-03: "auto -> run auto kind of sucks. auto should immediately do 'Run auto'
## again without a sub menu. and auto can't advance since the number of turns is based on the
## rules. it needs to be disabled when you start advancing. pressing advance when auto is selected
## should just invoke run auto too I think ... for now, any confirm style button is just run auto
## ... Also, Auto Rules is definitely a button and not a menu item."
##
## BEHAVIOURAL against the real Win98Menu, not a source pin — a string pin cannot tell a row
## that runs on press from one that queues.

const W98 := "res://src/ui/Win98Menu.gd"


func _auto_row(combatant_marker: String = "pc") -> Dictionary:
	return {"id": "autobattle", "label": "Auto", "data": {"action": "autobattle", "combatant": combatant_marker}}


func _menu(rows: Array) -> Node:
	var m = load(W98).new()
	m.is_root_menu = true
	m.battle_mode = true
	add_child_autofree(m)
	m.setup("Command", rows, Vector2(10, 10), "fighter")
	m._can_accept_input = true
	m.set_max_queue_size(4)
	return m


## Confirm on Auto must run it directly — no submenu to expand first.
func test_confirm_on_auto_runs_it_with_no_submenu() -> void:
	var m = _menu([_auto_row(), {"id": "attack", "label": "Attack"}])
	m.selected_index = 0
	assert_false(m.menu_items[0].has("submenu"), "CONTROL: Auto must not carry a submenu")
	var got: Array = []
	m.item_selected.connect(func(id, data): got.append({"id": id, "data": data}))
	m._submit_actions()
	assert_eq(got.size(), 1, "confirm on Auto must emit item_selected once")
	if got.size() != 1:
		return
	assert_eq(got[0]["id"], "autobattle", "and it must be the autobattle action, not a submenu expand")


## Mutant to kill: restoring a submenu on the Auto row. If "submenu" comes back, confirm would
## expand it instead of running auto and the assertion above would start failing for a different
## reason (no item_selected at all, since _submit_actions refuses submenu rows).
func test_mutant_a_submenu_on_auto_is_rejected_by_the_control() -> void:
	var m = _menu([_auto_row()])
	m.menu_items[0]["submenu"] = [{"id": "trust_toggle", "label": "Trust: OFF"}]
	m.selected_index = 0
	var got: Array = []
	m.item_selected.connect(func(id, data): got.append(id))
	m._submit_actions()
	assert_eq(got.size(), 0, "CONTROL: a submenu row cannot submit directly — proves the real row must have none")


## Pressing Advance (R / W key) while Auto is selected must run auto immediately, not queue it.
func test_advance_on_auto_runs_it_instead_of_queueing() -> void:
	var m = _menu([_auto_row(), {"id": "attack", "label": "Attack"}])
	m.selected_index = 0
	var got: Array = []
	m.item_selected.connect(func(id, data): got.append(id))
	Win98Menu._last_advance_ms = -1000000
	m._handle_advance_input()
	assert_eq(m.get_queue_count(), 0, "Auto must never sit in the queue")
	assert_eq(got, ["autobattle"], "Advance on Auto must run it the same way Confirm does")


## Once >=1 action is queued, Auto is disabled; undoing back to zero re-enables it.
func test_auto_disables_once_something_is_queued_and_re_enables_on_undo() -> void:
	var m = _menu([{"id": "attack", "label": "Attack"}, _auto_row()])
	m.selected_index = 0
	Win98Menu._last_advance_ms = -1000000
	m._handle_advance_input()  # queues "attack"
	assert_eq(m.get_queue_count(), 1, "CONTROL: the queue actually has one action")
	assert_true(bool(m.menu_items[1].get("disabled", false)), "Auto must be disabled while anything is queued")

	m._undo_last_action()
	assert_eq(m.get_queue_count(), 0, "CONTROL: the undo actually emptied the queue")
	assert_false(bool(m.menu_items[1].get("disabled", false)), "Auto must be re-enabled once the queue is empty again")


## A disabled Auto row must not be reachable by navigation — the cursor skips it, same as any
## other disabled row (_step_selection's existing contract).
func test_the_cursor_cannot_rest_on_a_disabled_auto_row() -> void:
	var m = _menu([_auto_row(), {"id": "attack", "label": "Attack"}])
	m.selected_index = 0
	Win98Menu._last_advance_ms = -1000000
	m.selected_index = 1
	m._handle_advance_input()  # queues "attack" from row 1, disabling Auto at row 0
	assert_true(bool(m.menu_items[0].get("disabled", false)), "CONTROL: Auto is now disabled")
	m.selected_index = 0
	m._sync_auto_row_disabled()
	assert_ne(m.selected_index, 0, "the cursor must not be left resting on the disabled Auto row")


## Auto Rules must not exist as a menu row anywhere the Auto block used to host it.
func test_auto_rules_has_no_menu_row() -> void:
	var m = _menu([_auto_row(), {"id": "trust_toggle", "label": "Trust: OFF"}])
	for item in m.menu_items:
		assert_ne(str((item as Dictionary).get("id", "")), "autobattle_edit",
			"Auto Rules must not be a menu row — it is the Start/F5 button")


## The permanent hint bar must advertise the Auto Rules button, derived per connected pad via
## InputProfileManager.hint_for_action — never a hardcoded letter.
func test_hint_bar_names_auto_rules_derived_per_pad() -> void:
	var bar: String = Win98Menu.hint_text()
	assert_true(bar.contains("Rules"), "the permanent hint bar must advertise the Auto Rules button: %s" % bar)
	# The source line must call hint_for_action("ui_menu") rather than freezing a literal glyph —
	# matching the pattern Defer/Advance/Auto already use.
	var src := FileAccess.get_file_as_string("res://src/ui/Win98Menu.gd")
	assert_true(src.contains('InputProfileManager.hint_for_action("ui_menu")'),
		"Rules must be derived via InputProfileManager.hint_for_action, not a hardcoded letter")


## Mutant to kill: freezing the Rules token to a literal (e.g. restoring "[Start] Rules" instead
## of the derived %s) must not quietly pass — the derived pad bar must carry no frozen face-glyph
## or button literal for Rules.
func test_mutant_a_frozen_rules_literal_is_not_the_derived_bar() -> void:
	var src := FileAccess.get_file_as_string("res://src/ui/Win98Menu.gd")
	var at := src.find("static func hint_text")
	assert_gt(at, -1, "CONTROL: hint_text must still exist")
	var body := src.substr(at, src.find("\nfunc ", at + 10) - at)
	assert_false(body.contains('"[Start]'), "the derived pad bar must not freeze a Start literal for Rules")
	assert_true(body.contains("rules"), "and must actually reference a derived rules variable")
