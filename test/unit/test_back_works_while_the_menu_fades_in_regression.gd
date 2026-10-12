extends GutTest

## The field menu fades in over 0.15s and its _input returned early for the whole tween, so EVERY
## press in that window was silently lost — including Back. Measured on main (2026-10-12), one menu
## per row, Back sent at a real delay:
##
##   t=50ms  alpha 0.95 -> closed=false      t=164ms alpha 1.00 -> closed=true
##   t=55ms  alpha 0.32 -> closed=false      t=304ms alpha 1.00 -> closed=true
##   t=103ms alpha 0.65 -> closed=false
##
## Open the menu, change your mind, press Back: nothing happens, and pressing again works. That is
## the "sometimes works" shape struktured reported for Back long before the keys moved.
##
## The guard is not wrong, it was too wide: its own comment says it stops a held CONFIRM picking a
## stale option while the panel is invisible. LEAVING is not that hazard — a close is never the
## wrong row. So cancel and the toggle now pass; confirm and navigation stay blocked.

const OverworldScript := preload("res://src/ui/OverworldMenu.gd")


func _party() -> Array:
	var out := []
	for j in ["fighter", "cleric"]:
		var c := Combatant.new()
		c.combatant_name = j.capitalize()
		add_child_autofree(c)
		JobSystem.assign_job(c, j)
		out.append(c)
	return out


## A live menu. Callers put it in the fade state with _fading() immediately before the press.
func _menu(party: Array) -> OverworldMenu:
	var m := OverworldScript.new()
	add_child(m)
	m.setup(party)
	await get_tree().process_frame
	return m


## The state the bug lives in, PINNED rather than timed. A headless frame can be longer than the
## whole 0.15s tween, so "await a frame and hope alpha < 1" flakes — measured: the same arm caught
## alpha 0.32 one run and 1.00 the next. The caller presses on the very next line with no await, so
## the tween cannot move it back before the press lands.
func _fading(m: OverworldMenu) -> void:
	m.modulate.a = 0.5
	assert_lt(m.modulate.a, 1.0, "PRECONDITION: the menu is mid-fade, the window that swallowed Back")


func _action(name: String) -> InputEventAction:
	var e := InputEventAction.new()
	e.action = name
	e.pressed = true
	return e


func _key(kc: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = kc
	e.pressed = true
	return e


func after_each() -> void:
	Input.action_release("ui_cancel")
	Input.action_release("ui_accept")


func test_back_closes_the_menu_while_it_is_still_fading_in() -> void:
	var m := await _menu(_party())
	_fading(m)
	var closed := [false]
	m.closed.connect(func(): closed[0] = true)
	m._input(_action("ui_cancel"))
	assert_true(closed[0], "Back was swallowed by the fade — the press a player makes to leave at once")
	if is_instance_valid(m):
		m.queue_free()


func test_the_toggle_key_also_closes_while_fading() -> void:
	var m := await _menu(_party())
	_fading(m)
	var closed := [false]
	m.closed.connect(func(): closed[0] = true)
	m._input(_key(OverworldScript.TOGGLE_KEY))
	assert_true(closed[0], "the key that opens the menu must close it during the fade too, as it does after")
	if is_instance_valid(m):
		m.queue_free()


## ⛔ THE CONTROL THE TOGGLE ARM NEEDS. The toggle now closes DURING the fade, so the very press that
## opened the menu must not reach it and shut it again — a menu that cannot be opened at all would
## otherwise pass every arm above. Driven through a real GameLoop with a real press.
func test_control_the_press_that_opens_the_menu_does_not_close_it() -> void:
	var gl = load("res://src/GameLoop.gd").new()
	add_child_autofree(gl)
	var explore := Node.new()
	add_child_autofree(explore)
	gl._exploration_scene = explore
	gl._current_map_id = "overworld"
	gl.current_state = gl.LoopState.EXPLORATION
	for i in 3:
		await get_tree().process_frame
	Input.parse_input_event(_key(OverworldScript.TOGGLE_KEY))
	for i in 3:
		await get_tree().process_frame
	var up = gl._overworld_menu
	assert_true(up != null and is_instance_valid(up) and not up.is_queued_for_deletion(),
		"the opening press closed the menu it had just opened")
	# …and it survives the rest of the fade rather than closing a frame later.
	await get_tree().create_timer(0.25).timeout
	assert_true(gl._overworld_menu != null and is_instance_valid(gl._overworld_menu),
		"the menu closed itself once the fade finished")


## CONTROL: the guard still does its job. A confirm during the fade must NOT pick the highlighted
## row — that is the hazard the early return was written for, and it has to survive the exemption.
func test_control_confirm_during_the_fade_still_picks_nothing() -> void:
	var m := await _menu(_party())
	_fading(m)
	var acted := [false]
	m.menu_action.connect(func(_id, _t): acted[0] = true)
	var closed := [false]
	m.closed.connect(func(): closed[0] = true)
	m._input(_action("ui_accept"))
	assert_false(acted[0], "a confirm in the fade window must still select nothing")
	assert_false(closed[0], "and must not close the menu either")
	assert_false(m._submenu_open, "and must open no submenu")
	if is_instance_valid(m):
		m.queue_free()


## CONTROL: the ordinary path is untouched — Back after the fade still closes.
func test_control_back_still_closes_after_the_fade() -> void:
	var m := OverworldScript.new()
	add_child(m)
	m.setup(_party())
	var waited := 0
	while m.modulate.a < 1.0 and waited < 180:
		await get_tree().process_frame
		waited += 1
	assert_eq(m.modulate.a, 1.0, "PRECONDITION: faded in")
	var closed := [false]
	m.closed.connect(func(): closed[0] = true)
	m._input(_action("ui_cancel"))
	assert_true(closed[0], "CONTROL: Back closes a fully faded menu")
	if is_instance_valid(m):
		m.queue_free()
