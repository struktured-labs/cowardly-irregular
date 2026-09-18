extends GutTest

const AutogrindState := preload("res://test/unit/helpers/autogrind_state.gd")

## start_grind REFUSES on an empty or all-dead party — and returned `void`, so no caller could
## learn it. GameLoop._start_autogrind sets LoopState.AUTOGRIND and _is_autogrinding BEFORE the
## call, and its only guard tests whether the session ENDED (struktured 2026-09-07 "cant exit
## autogrind again"). A start that never BEGAN leaves that guard false: the controller is alive,
## _is_autogrinding is true, so GameLoop plays the autogrind bed and shows the overlay for a grind
## with no battles, while AutogrindUI sits hidden with _is_grinding true.
##
## The mechanism already existed one layer down: AutogrindSystem.start_autogrind returns bool and
## refuses on the same two conditions. The controller discarded it and declared `-> void`.

var _ag_state: Dictionary
var _ags: Node = null


func before_each() -> void:
	_ag_state = AutogrindState.snapshot_and_isolate()
	_ags = get_node_or_null("/root/AutogrindSystem")


func after_each() -> void:
	if _ags:
		_ags.is_grinding = false
	AutogrindState.restore(_ag_state)


func _member(name: String, alive: bool) -> Combatant:
	var c := Combatant.new()
	c.initialize({"name": name, "max_hp": 100, "max_mp": 10,
		"attack": 10, "defense": 10, "magic": 10, "speed": 10})
	add_child_autofree(c)
	c.is_alive = alive
	if alive:
		c.add_item("potion", 5)
	return c


func _controller() -> Node:
	var ctrl = preload("res://src/autogrind/AutogrindController.gd").new()
	add_child_autofree(ctrl)
	return ctrl


func test_an_all_dead_party_refuses_and_says_so() -> void:
	var ctrl := _controller()
	var party: Array = [_member("Dead A", false), _member("Dead B", false)]
	var started: bool = ctrl.start_grind(party, {"headless": true, "auto_advance": false}, "plains")
	assert_false(started, "start_grind accepted an all-dead party, or gave the caller no way to know it refused")
	assert_eq(ctrl._state, ctrl.State.IDLE, "CONTROL: a refused start must leave the controller IDLE")


func test_an_empty_party_refuses_and_says_so() -> void:
	var ctrl := _controller()
	var started: bool = ctrl.start_grind([], {"headless": true, "auto_advance": false}, "plains")
	assert_false(started, "start_grind accepted an empty party")
	assert_eq(ctrl._state, ctrl.State.IDLE, "CONTROL: a refused start must leave the controller IDLE")


func test_a_live_party_still_starts_and_says_so() -> void:
	var ctrl := _controller()
	var party: Array = [_member("Live A", true), _member("Live B", true)]
	var started: bool = ctrl.start_grind(party, {"headless": true, "auto_advance": false}, "plains")
	assert_true(started, "CONTROL: a live party must still start — otherwise the refusal arms prove nothing")
	assert_ne(ctrl._state, ctrl.State.IDLE, "CONTROL: an accepted start must leave IDLE")
	ctrl.stop_grind("test cleanup")
