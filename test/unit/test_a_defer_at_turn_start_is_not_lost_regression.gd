extends GutTest

## The battle command menu ignores ALL input for 80ms after it spawns, and it respawns for EVERY
## character's turn — so that is one deaf window per character per round, five a round on a full
## party. A Defer pressed in it was silently lost. Measured on main, one fresh menu per row:
##
##   t=1ms   can_accept=false -> deferred=false     t=151ms can_accept=true -> deferred=true
##   t=34ms  can_accept=false -> deferred=false     t=303ms can_accept=true -> deferred=true
##   t=58ms  can_accept=false -> deferred=false
##
## The delay is not wrong — its own comment says it prevents an accidental SELECTION, a confirm
## landing on a row that may not be drawn yet. Defer ignores the highlighted row entirely, so it is
## not that hazard, and it is the press a player makes fastest at the top of a turn.
##
## 📌 ONLY the delay is waived, and the arm below pins that a hidden or closing menu still swallows
## the defer. ⚠️ It does NOT prove the exemption is what keeps them blocked: widening the exemption
## to ignore EVERY block leaves all five arms green, because hidden / closing / submenu / tutorial
## hint are each enforced AGAIN downstream of this branch (measured, four blockers, both arms of the
## mutation). So the arm guards the OUTCOME, which is what a player feels, and the scope clause in
## the source is a second line of defence no test here can see. Saying so beats a comment claiming
## a coverage this file does not have.

const W98 := preload("res://src/ui/Win98Menu.gd")


func _menu() -> Win98Menu:
	W98._defer_axis_held = false
	W98._advance_axis_held = false
	var m = W98.new()
	m.is_root_menu = true
	m.battle_mode = true
	add_child(m)
	m.setup("Command", [{"id": "attack", "label": "Attack"}], Vector2(10, 10), "fighter")
	await get_tree().process_frame
	assert_false(m._can_accept_input,
		"PRECONDITION: the menu is inside its open delay — the window that swallowed the press")
	return m


func _ev(action: String) -> InputEventAction:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = true
	return e


func after_each() -> void:
	W98._defer_axis_held = false
	W98._advance_axis_held = false
	for a in ["battle_defer", "battle_advance", "ui_accept", "ui_cancel"]:
		Input.action_release(a)


func test_a_defer_in_the_open_delay_defers() -> void:
	var m := await _menu()
	var deferred := [false]
	m.defer_requested.connect(func(): deferred[0] = true)
	m._input(_ev("battle_defer"))
	assert_true(deferred[0],
		"the Defer a player presses at the top of a turn was swallowed by the menu's own open delay")
	if is_instance_valid(m):
		m.queue_free()


## CONTROL: the hazard the delay exists for must survive. A confirm acts ON the highlighted row.
func test_control_confirm_in_the_open_delay_still_selects_nothing() -> void:
	var m := await _menu()
	var acted := [false]
	m.item_selected.connect(func(_id, _d): acted[0] = true)
	m.actions_submitted.connect(func(_a): acted[0] = true)
	m._input(_ev("ui_accept"))
	assert_false(acted[0], "a confirm in the open delay must still pick nothing")
	if is_instance_valid(m):
		m.queue_free()


## CONTROL: Advance queues the highlighted row, so it shares the hazard and stays blocked.
func test_control_advance_in_the_open_delay_still_queues_nothing() -> void:
	var m := await _menu()
	m.set_max_queue_size(4)
	m._input(_ev("battle_advance"))
	assert_eq(m.get_queue_count(), 0, "an advance in the open delay must still queue nothing")
	if is_instance_valid(m):
		m.queue_free()


## Only the delay is waived: a menu blocked for any OTHER reason must still swallow the defer. See
## the header — this pins the outcome, not which layer enforces it.
func test_other_blocks_still_block_a_defer_in_the_delay() -> void:
	for blocker in ["hidden", "closing"]:
		var m := await _menu()
		match blocker:
			"hidden":
				m.visible = false
			"closing":
				m._is_closing = true
		var deferred := [false]
		m.defer_requested.connect(func(): deferred[0] = true)
		m._input(_ev("battle_defer"))
		assert_false(deferred[0],
			"a %s menu must still swallow the defer — only the open delay is exempt" % blocker)
		if is_instance_valid(m):
			m.queue_free()
		await get_tree().process_frame


## CONTROL: the ordinary path is untouched — a Defer after the delay still defers.
func test_control_defer_after_the_delay_still_defers() -> void:
	var m := await _menu()
	var waited := 0
	while not m._can_accept_input and waited < 120:
		await get_tree().process_frame
		waited += 1
	assert_true(m._can_accept_input, "PRECONDITION: the delay elapsed")
	var deferred := [false]
	m.defer_requested.connect(func(): deferred[0] = true)
	m._input(_ev("battle_defer"))
	assert_true(deferred[0], "CONTROL: Defer works once the menu is accepting input")
	if is_instance_valid(m):
		m.queue_free()
