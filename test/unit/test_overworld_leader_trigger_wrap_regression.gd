extends GutTest

## The overworld menu cycles the party leader on battle_defer / battle_advance. Those actions
## bind the shoulder BUTTON and the analog TRIGGER. A trigger pull is a ramp of motion events,
## and an axis has no echo flag, so every step past the deadzone reads as a fresh press.
##
## Measured on a 5-person party (the starter roster) with a 5-step pull: the leader index
## walks 0,1,2,3,4 and wraps back to 0. The shoulder button, which emits one event, moves
## one place. The trigger the same action also binds appears to do nothing.
##
## EquipmentMenu already latches this pair for character cycling. This screen did not.

const RAMP := [0.55, 0.7, 0.85, 0.95, 1.0]
const PARTY_SIZE := 5

var _saved_party: Array = []
var _saved_leader: int = 0


func before_each() -> void:
	_saved_party = GameState.player_party.duplicate(true)
	_saved_leader = GameState.party_leader_index
	var party: Array[Dictionary] = []
	for _i in PARTY_SIZE:
		party.append({})
	GameState.player_party = party
	GameState.party_leader_index = 0


func after_each() -> void:
	var restore: Array[Dictionary] = []
	for entry in _saved_party:
		restore.append(entry)
	GameState.player_party = restore
	GameState.party_leader_index = _saved_leader
	Input.action_release("battle_advance")
	Input.action_release("battle_defer")


func _menu() -> OverworldMenu:
	var m := OverworldMenu.new()
	add_child_autofree(m)
	var c := Combatant.new()
	c.combatant_name = "Fighter"
	add_child_autofree(c)
	m.party = [c]
	m.visible = true
	# _ready fades in from 0; input is ignored until the fade finishes. Set it here so the
	# ramp is delivered in this same call, before the tween's next step.
	m.modulate.a = 1.0
	return m


func _motion(axis: int, value: float) -> InputEventJoypadMotion:
	var ev := InputEventJoypadMotion.new()
	ev.axis = axis
	ev.axis_value = value
	return ev


func _bound_button(action: String) -> int:
	for e in InputMap.action_get_events(action):
		if e is InputEventJoypadButton:
			return (e as InputEventJoypadButton).button_index
	return -1


func _pull(m: OverworldMenu, axis: int) -> int:
	var pressed := 0
	for v in RAMP:
		var ev := _motion(axis, v)
		if ev.is_action_pressed("battle_advance") or ev.is_action_pressed("battle_defer"):
			pressed += 1
		m._input(ev)
	return pressed


func test_one_trigger_pull_advances_the_leader_by_one() -> void:
	var m := _menu()
	var pressed := _pull(m, JOY_AXIS_TRIGGER_RIGHT)
	assert_gt(pressed, 1,
		"PRECONDITION: the ramp must read as a burst, or a single-step assert cannot see the bug")
	assert_eq(GameState.party_leader_index, 1,
		"one R2 pull on a %d-person party must move the leader one place; %d ramp steps wrapped it to %d"
		% [PARTY_SIZE, pressed, GameState.party_leader_index])


func test_one_trigger_pull_steps_the_leader_backward_by_one() -> void:
	var m := _menu()
	var pressed := _pull(m, JOY_AXIS_TRIGGER_LEFT)
	assert_gt(pressed, 1, "PRECONDITION: L2 must burst the same way R2 does")
	assert_eq(GameState.party_leader_index, PARTY_SIZE - 1,
		"one L2 pull must move the leader back one place, not lap the party")


func test_a_release_arms_the_next_pull() -> void:
	var m := _menu()
	_pull(m, JOY_AXIS_TRIGGER_RIGHT)
	var release := _motion(JOY_AXIS_TRIGGER_RIGHT, 0.0)
	assert_true(release.is_action_released("battle_advance"),
		"PRECONDITION: returning the trigger to center is a release of battle_advance")
	m._input(release)
	_pull(m, JOY_AXIS_TRIGGER_RIGHT)
	assert_eq(GameState.party_leader_index, 2,
		"letting go and pulling again must move one more place — the latch must not be a one-shot")


func test_the_shoulder_button_still_moves_the_leader_once() -> void:
	var btn := _bound_button("battle_advance")
	assert_gt(btn, -1, "PRECONDITION: battle_advance must be bound to a joypad button")
	var m := _menu()
	var ev := InputEventJoypadButton.new()
	ev.button_index = btn
	ev.pressed = true
	m._input(ev)
	assert_eq(GameState.party_leader_index, 1,
		"the shoulder button emits one event and must still move the leader one place")
