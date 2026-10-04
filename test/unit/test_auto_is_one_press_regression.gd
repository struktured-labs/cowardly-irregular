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


func before_each() -> void:
	Input.action_release("ui_accept")


func after_each() -> void:
	Input.action_release("ui_accept")  # the Input singleton leaks across tests
	Engine.time_scale = 1.0


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
	var return_line_at := body.rfind("\n\treturn \"")
	assert_gt(return_line_at, -1, "CONTROL: must find the derived bar's return line")
	var return_line := body.substr(return_line_at)
	for frozen in ["[Start]", "[Plus]", "[Options]", "Start/Plus/Options"]:
		assert_false(return_line.contains(frozen),
			"the derived pad bar must not freeze a literal button name for Rules: %s" % return_line)
	assert_true(return_line.contains(", rules]") or return_line.contains(", rules,"), "and must actually format in the derived rules variable: %s" % return_line)


## ---- Tap vs hold (struktured 2026-10-03): "pressing confirm and releasing before the hold
## threshold runs auto; holding past ~0.5s wall-clock opens that character's rule editor and does
## NOT run auto." ----

## THE REQUIRED MUTANT GUARD: a press alone must do NOTHING — neither run auto nor open the
## editor — until release or the threshold decides which. If a future edit reverts to acting on
## PRESS (the pre-2026-10-03 shape), this reds immediately, before any release/threshold logic
## even runs.
func test_pressing_confirm_alone_does_nothing_until_release_or_threshold() -> void:
	var m = _menu([_auto_row("pc1")])
	m.selected_index = 0
	var ran: Array = []
	var opened: Array = []
	m.item_selected.connect(func(id, data): ran.append(id))
	m.auto_hold_editor_requested.connect(func(c): opened.append(c))
	Input.action_press("ui_accept")
	m._begin_auto_hold(0)
	assert_eq(ran.size(), 0, "a bare press must not run auto yet")
	assert_eq(opened.size(), 0, "a bare press must not open the editor yet")
	assert_true(m._auto_hold_active, "CONTROL: the hold is actually armed")


func test_tap_runs_auto_and_does_not_open_the_editor() -> void:
	var m = _menu([_auto_row("pc1")])
	m.selected_index = 0
	var ran: Array = []
	var opened: Array = []
	m.item_selected.connect(func(id, data): ran.append(id))
	m.auto_hold_editor_requested.connect(func(c): opened.append(c))
	Input.action_press("ui_accept")
	m._begin_auto_hold(0)
	Input.action_release("ui_accept")  # released almost immediately — well under the threshold
	m._process(0.016)
	assert_eq(ran, ["autobattle"], "a tap (release before threshold) must run auto")
	assert_eq(opened.size(), 0, "a tap must not open the editor")
	assert_false(m._auto_hold_active, "CONTROL: the hold state is cleared after resolving")


func test_hold_opens_the_editor_and_does_not_run_auto() -> void:
	var m = _menu([_auto_row("pc1")])
	m.selected_index = 0
	var ran: Array = []
	var opened: Array = []
	m.item_selected.connect(func(id, data): ran.append(id))
	m.auto_hold_editor_requested.connect(func(c): opened.append(c))
	Input.action_press("ui_accept")
	m._begin_auto_hold(0)
	# Still held, and the wall clock already crossed the threshold.
	m._auto_hold_start_ms = Time.get_ticks_msec() - (Win98Menu.AUTO_HOLD_THRESHOLD_MS + 50)
	m._process(0.016)
	assert_eq(opened, ["pc1"], "a hold past the threshold must open the editor for the held combatant")
	assert_eq(ran.size(), 0, "a hold must NOT run auto")
	assert_false(m._auto_hold_active, "CONTROL: the hold state is cleared after resolving")


## Battle runs at Engine.time_scale 0.25 by default; a hold measured off accumulated `delta`
## would need ~4x as long to reach what should be a 0.5s threshold. Feeding a quarter-sized delta
## (what 0.25 scale actually hands _process) must still fire at the backdated wall-clock mark —
## proving the decision reads Time.get_ticks_msec(), not delta accumulation.
func test_hold_threshold_is_wall_clock_not_scaled_by_time_scale() -> void:
	Engine.time_scale = 0.25
	var m = _menu([_auto_row("pc1")])
	m.selected_index = 0
	var opened: Array = []
	m.auto_hold_editor_requested.connect(func(c): opened.append(c))
	Input.action_press("ui_accept")
	m._begin_auto_hold(0)
	m._auto_hold_start_ms = Time.get_ticks_msec() - (Win98Menu.AUTO_HOLD_THRESHOLD_MS + 50)
	m._process(0.004)  # a quarter of a normal 0.016 frame delta, matching time_scale 0.25
	assert_eq(opened, ["pc1"], "the threshold must fire off real elapsed ms regardless of a scaled delta")


func test_progress_indicator_appears_during_a_hold_and_clears_after() -> void:
	var m = _menu([_auto_row("pc1"), {"id": "attack", "label": "Attack"}])
	m.selected_index = 0
	await get_tree().process_frame
	await get_tree().process_frame
	var container = m._get_items_container()
	assert_not_null(container, "CONTROL: the menu built its rows")
	var row: Control = container.get_child(0)
	assert_null(row.get_node_or_null("HoldProgress"), "CONTROL: no progress indicator before any hold starts")

	Input.action_press("ui_accept")
	m._begin_auto_hold(0)
	m._auto_hold_start_ms = Time.get_ticks_msec() - int(Win98Menu.AUTO_HOLD_THRESHOLD_MS / 2)
	m._process(0.016)
	var bar := row.get_node_or_null("HoldProgress")
	assert_not_null(bar, "a progress indicator must appear on the row while holding")
	assert_gt((bar as Control).size.x, 0.0, "and it must actually be filling, not a zero-width placeholder")

	# Resolve via the HOLD path (not a tap): a tap runs auto, which submits and force_closes the
	# whole menu — there would be no `row` left to inspect at all. The hold path only emits a
	# signal here (BattleScene owns closing the menu for real), so the row survives to check.
	m._auto_hold_start_ms = Time.get_ticks_msec() - (Win98Menu.AUTO_HOLD_THRESHOLD_MS + 50)
	m._process(0.016)
	await get_tree().process_frame  # _clear_auto_hold_progress uses queue_free, not free
	assert_null(row.get_node_or_null("HoldProgress"), "the progress indicator must clear once the hold resolves")
	Input.action_release("ui_accept")


## Moving the cursor off Auto mid-hold must cancel it silently — neither a tap nor a hold fires
## for a row the player is no longer on.
func test_moving_off_auto_mid_hold_cancels_without_acting() -> void:
	var m = _menu([_auto_row("pc1"), {"id": "attack", "label": "Attack"}])
	m.selected_index = 0
	var ran: Array = []
	var opened: Array = []
	m.item_selected.connect(func(id, data): ran.append(id))
	m.auto_hold_editor_requested.connect(func(c): opened.append(c))
	Input.action_press("ui_accept")
	m._begin_auto_hold(0)
	m.selected_index = 1
	m._process(0.016)
	assert_false(m._auto_hold_active, "the hold must be cancelled once selection moves away")
	assert_eq(ran.size(), 0, "no tap fires for a hold that moved off its row")
	assert_eq(opened.size(), 0, "no editor opens for a hold that moved off its row")
