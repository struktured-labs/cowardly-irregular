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


## And the refusal must be RECOVERABLE. is_grinding lives on the autoload, has exactly one clearer
## (stop_autogrind), and start_autogrind refuses while it is set. An abort in start_grind after the
## system accepted strands it: the controller is IDLE, so stop_grind takes the .422 IDLE branch and
## returns without stopping the system — and every later session refuses for the rest of the process.
func test_a_stranded_system_flag_is_cleared_by_a_stop() -> void:
	var ctrl := _controller()
	## Exactly the desync an abort leaves: system grinding, controller never left IDLE.
	_ags.is_grinding = true
	assert_eq(ctrl._state, ctrl.State.IDLE, "CONTROL: the controller must be IDLE for this to be the desync")
	ctrl.stop_grind("aborted start")
	assert_false(_ags.is_grinding,
		"stop_grind left is_grinding set on the autoload — every later start_autogrind refuses for the session")
	var party: Array = [_member("After A", true), _member("After B", true)]
	var started: bool = ctrl.start_grind(party, {"headless": true, "auto_advance": false}, "plains")
	assert_true(started, "a later grind must be able to start once the stranded flag is cleared")
	ctrl.stop_grind("test cleanup")


## GameLoop's refusal teardown frees the controller WITHOUT calling stop_grind (correct — a refusal
## is not an end, and _stop_autogrind would show a summary for a grind that never ran). So the
## stop-side recovery never fires on that path: a stranded flag would refuse every later start
## forever, cleanly. start_grind must clear the desync itself.
func test_a_stranded_flag_does_not_refuse_the_next_start() -> void:
	var ctrl := _controller()
	_ags.is_grinding = true
	var party: Array = [_member("Recover A", true), _member("Recover B", true)]
	var started: bool = ctrl.start_grind(party, {"headless": true, "auto_advance": false}, "plains")
	assert_true(started,
		"a flag stranded by an aborted start refused a fresh session — and GameLoop's refusal path never calls stop_grind, so nothing clears it")
	ctrl.stop_grind("test cleanup")


## The abort that strands is_grinding also strands Engine.time_scale: start_grind raises it
## (BATTLE_SPEEDS or 2.0) a few lines before _state leaves IDLE, and the IDLE branch of stop_grind
## restored the autobattle conduit and the system flag but not the clock. GameLoop's own resets are
## all `= 1.0` and sit BELOW its gate flag, so they cannot rescue it either.
func test_a_stranded_time_scale_is_reset_by_a_stop() -> void:
	var ctrl := _controller()
	## Exactly what an aborted start leaves: the clock raised, the controller never out of IDLE.
	Engine.time_scale = 2.0
	assert_eq(ctrl._state, ctrl.State.IDLE, "CONTROL: the controller must be IDLE for this to be the abort shape")
	ctrl.stop_grind("aborted start")
	assert_almost_eq(Engine.time_scale, 1.0, 0.001,
		"stop_grind left Engine.time_scale raised — the whole game runs at grind speed until something else resets it")
