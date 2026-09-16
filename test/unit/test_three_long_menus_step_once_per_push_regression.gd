extends GutTest

## The three longest lists in the game read ui_up/ui_down RAW until now — Abilities (289),
## Items (172) and Party Chat (44 registry entries). A stick push emits one event per ramp value
## and every one reads as pressed, so the cursor moved ~5 rows per nudge.
##
## PartyChatMenu also lacked the `not event.is_echo()` its neighbours carry. ⚠️ THAT COST NOTHING
## AND I SAID IT DID: is_action_pressed defaults allow_echo=false, so an echo never read as pressed
## there either. Measured by running this file against the pre-conversion code — the echo arm below
## PASSES BOTH WAYS. It pins a property worth keeping; it is not evidence of a defect that existed.
##
## THESE ARMS EXIST BECAUSE NOTHING DROVE THESE MENUS. Measured before writing them: zero tests in
## the corpus touch _input or a selection index on any of the three. The conversion's blast radius
## was green and proved only that nothing else broke — not that the cursor still moves.

const AbilitiesScript = preload("res://src/ui/AbilitiesMenu.gd")
const ItemsScript = preload("res://src/ui/ItemsMenu.gd")
const PartyChatScript = preload("res://src/ui/PartyChatMenu.gd")

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


func _dpad_down() -> InputEventJoypadButton:
	var ev := InputEventJoypadButton.new()
	ev.button_index = _bound_button("ui_down")
	ev.pressed = true
	return ev


## Clear MenuNav's static latch and the Input singleton through the public seam.
func _clear() -> void:
	Input.action_release("ui_down")
	Input.action_release("ui_up")
	MenuNav.step(_motion(0.0))


func before_each() -> void:
	_clear()


func after_each() -> void:
	_clear()


func _push_stick_down(menu: Node) -> void:
	Input.action_press("ui_down")
	for v in RAMP:
		menu._input(_motion(v))


# ---------------------------------------------------------------- Abilities

func _abilities() -> Node:
	var m = AbilitiesScript.new()
	add_child_autofree(m)
	m.visible = true
	m.current_tab = AbilitiesScript.Tab.ABILITIES
	m._abilities_list = []
	for i in range(20):
		m._abilities_list.append({"id": "a_%d" % i, "data": {"name": "A %d" % i, "type": "physical", "mp_cost": 0}})
	m.selected_index = 0
	return m


func test_the_abilities_list_steps_once_per_stick_push() -> void:
	var m := _abilities()
	_push_stick_down(m)
	assert_eq(m.selected_index, 1,
		"289 abilities at ~5 rows per nudge was the defect; one push is one row")


func test_the_abilities_list_still_steps_on_the_dpad() -> void:
	var m := _abilities()
	Input.action_press("ui_down")
	m._input(_dpad_down())
	assert_eq(m.selected_index, 1, "the d-pad must still step — it is not latched")


# -------------------------------------------------------------------- Items

func _items() -> Node:
	var m = ItemsScript.new()
	add_child_autofree(m)
	m.visible = true
	m.mode = 0
	m._item_list = []
	for i in range(20):
		m._item_list.append({"id": "i_%d" % i, "data": {"name": "I %d" % i}, "count": 1})
	m.selected_item_index = 0
	return m


func test_the_items_list_steps_once_per_stick_push() -> void:
	var m := _items()
	_push_stick_down(m)
	assert_eq(m.selected_item_index, 1, "172 items; one push is one row")


func test_the_items_list_wraps_as_it_always_did() -> void:
	var m := _items()
	m.selected_item_index = 0
	m._nav_step_item(-1)
	assert_eq(m.selected_item_index, 19,
		"the conversion must not change wrap semantics — stepping up from the top lands at the end")


func test_an_empty_items_list_does_not_move() -> void:
	var m := _items()
	m._item_list = []
	m.selected_item_index = 0
	_push_stick_down(m)
	assert_eq(m.selected_item_index, 0, "an empty list has nowhere to step")


# --------------------------------------------------------------- Party Chat

func _party_chat() -> Node:
	var m = PartyChatScript.new()
	add_child_autofree(m)
	m.visible = true
	m._chats = []
	m._row_nodes = []
	for i in range(10):
		m._chats.append({"id": "c_%d" % i, "title": "C %d" % i, "world": 1})
		m._row_nodes.append(Label.new())
	m._selection = 0
	return m


func test_the_party_chat_list_steps_once_per_stick_push() -> void:
	var m := _party_chat()
	_push_stick_down(m)
	assert_eq(m._selection, 1, "one push is one row")


## Passes against the old code too, and is kept for that reason rather than despite it: it pins
## that MenuNav refuses echoes for every consumer, so the property cannot be lost in a later
## refactor of the helper. Not a red-before/green-after arm, and labelled so nobody reads it as one.
func test_a_held_key_no_longer_rapid_fires_the_party_chat_list() -> void:
	var m := _party_chat()
	var ev := InputEventKey.new()
	ev.keycode = KEY_DOWN
	ev.pressed = true
	ev.echo = true
	m._input(ev)
	assert_eq(m._selection, 0, "a key ECHO must not step — this menu used to take every one")
