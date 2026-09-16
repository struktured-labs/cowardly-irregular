extends GutTest

## The overworld menu and the battle command menu — the two surfaces a player touches most — read
## ui_up/ui_down raw until now, so a left-stick nudge stepped the cursor ~5 rows. Win98Menu is the
## command menu: every turn of every battle.
##
## NEITHER HAS EVER BEEN DRIVEN BY A TEST. Measured before writing these: zero files in the corpus
## call _input on either. So the conversion's radius proves only that nothing else broke.
##
## Both already had a _nav_step owner, so the conversion is a read rather than a rewrite — which is
## exactly why a behavioural arm is worth more here than a source pin: the routing is the only
## thing that changed, and a source pin would confirm the text I just typed.

const OverworldScript = preload("res://src/ui/OverworldMenu.gd")
const Win98Script = preload("res://src/ui/Win98Menu.gd")

const RAMP := [0.55, 0.7, 0.85, 0.95, 1.0]


func _motion(v: float) -> InputEventJoypadMotion:
	var ev := InputEventJoypadMotion.new()
	ev.axis = JOY_AXIS_LEFT_Y
	ev.axis_value = v
	return ev


func _bound_button(action: String) -> int:
	for e in InputMap.action_get_events(action):
		if e is InputEventJoypadButton:
			return (e as InputEventJoypadButton).button_index
	return -1


func _dpad(action: String) -> InputEventJoypadButton:
	var ev := InputEventJoypadButton.new()
	ev.button_index = _bound_button(action)
	ev.pressed = true
	return ev


func _clear() -> void:
	Input.action_release("ui_down")
	Input.action_release("ui_up")
	MenuNav.step(_motion(0.0))


func before_each() -> void:
	_clear()


func after_each() -> void:
	_clear()


func _push_down(menu: Node) -> void:
	Input.action_press("ui_down")
	for v in RAMP:
		menu._input(_motion(v))


# ------------------------------------------------------------- Overworld menu

func _overworld() -> Node:
	var m = OverworldScript.new()
	add_child_autofree(m)
	m.visible = true
	m.modulate.a = 1.0
	m._submenu_open = false
	m.party = [{"name": "A"}, {"name": "B"}]
	m._menu_options = ["Items", "Abilities", "Equipment", "Status", "Save"]
	m.selected_index = 0
	return m


func test_the_overworld_menu_steps_once_per_stick_push() -> void:
	var m := _overworld()
	_push_down(m)
	assert_eq(m.selected_index, 1, "one push is one row, not five")


func test_the_overworld_menu_still_steps_on_the_dpad() -> void:
	var m := _overworld()
	Input.action_press("ui_down")
	m._input(_dpad("ui_down"))
	assert_eq(m.selected_index, 1, "the d-pad is not latched and must still step")


func test_the_overworld_menu_wraps_as_it_always_did() -> void:
	var m := _overworld()
	m.selected_index = 0
	m._nav_step("ui_up")
	assert_eq(m.selected_index, 4, "stepping up from the top wraps to the end, unchanged")


# --------------------------------------------------------- Battle command menu

func _win98() -> Node:
	var m = Win98Script.new()
	add_child_autofree(m)
	m.visible = true
	m._can_accept_input = true
	m._is_closing = false
	return m


## Driven through the real _input, which needed only the four gates _nav_is_blocked names — no
## battle. An earlier version of this arm called MenuNav directly and PASSED AGAINST THE OLD CODE,
## because it was testing the helper rather than the menu; it discriminated nothing.
func test_the_command_menu_steps_once_per_stick_push() -> void:
	var m := _win98()
	m.menu_items = [
		{"label": "Attack", "enabled": true},
		{"label": "Defend", "enabled": true},
		{"label": "Item", "enabled": true},
	]
	m.selected_index = 0
	_push_down(m)
	assert_eq(m.selected_index, 1,
		"one push is one row — the menu a player touches on every turn of every battle")


## The routing itself, pinned where the behaviour cannot be driven: the raw read is gone and the
## owner is reached from the latched read.
func test_the_command_menu_routes_its_step_through_menunav() -> void:
	var GdSource = load("res://test/unit/helpers/gd_source.gd")
	var code: String = GdSource.code_of("res://src/ui/Win98Menu.gd")
	assert_ne(code, "", "Win98Menu must be readable as source")
	assert_true(code.contains("MenuNav.step(event)"), "navigation must come from the latched reader")
	assert_eq(code.find('is_action_pressed("ui_up") and not event.is_echo()'), -1,
		"the raw read must be gone — an echo check cannot see an axis")
	assert_eq(code.count("func _nav_step("), 1, "exactly one owner for a step")
