extends GutTest

## A `stop_grinding` rule did not stop the grind.
##
## The rule fired, apply_autogrind_actions called stop_autogrind, the system printed
## "=== AUTOGRIND STOPPED ===" and set is_grinding = false — and the controller launched the next
## battle anyway. Two independent reasons:
##
##   1. grind_stopped had ZERO listeners. Declared, emitted, connected nowhere. The controller
##      learned about a system-side stop only through pre_battle_check's interrupts.
##   2. _process advanced with `_state = State.PRE_BATTLE` UNCONDITIONALLY after evaluating
##      rules, overwriting the IDLE a stop had just set. So even wiring the signal changed
##      nothing until the advance was made conditional.
##
## This is the player's SAFETY rule — "if the party drops below 20%, stop" — and it was inert
## whenever no built-in interrupt happened to coincide.
##
## ⚠️ THE FIXTURE MUST CARRY POTIONS, and that is not incidental. My first probe used an unstocked
## party and reported the stop working: pre_battle_check returned "Healing items depleted" and
## interrupted the grind on its own. A control run with NO RULES AT ALL stopped identically, which
## is the only reason I caught it. Every test here asserts pre_battle_check() is EMPTY first, so
## nothing but the rule can be doing the work.

var _ags: Node = null


func before_each() -> void:
	_ags = get_node_or_null("/root/AutogrindSystem")
	if _ags:
		_ags._test_disable_persistence = true


func after_each() -> void:
	if _ags:
		_ags.is_grinding = false
		_ags.set_autogrind_rules([])


func _controller_with_party(tag: String) -> Node:
	var ctrl = preload("res://src/autogrind/AutogrindController.gd").new()
	add_child_autofree(ctrl)
	var party: Array[Combatant] = []
	for n in ["%s A" % tag, "%s B" % tag]:
		var c := Combatant.new()
		c.initialize({"name": n, "max_hp": 1000, "max_mp": 100,
			"attack": 20, "defense": 20, "magic": 20, "speed": 20})
		add_child_autofree(c)
		## Full HP and stocked, so NO built-in interrupt is available to stop the grind for us.
		c.add_item("potion", 10)
		party.append(c)
	## Through start_grind, NOT by wiring the signal here. A fixture that connects the handler
	## itself would pass even if production never connected it — the half of the fix that makes a
	## system-side stop visible would then be untested while looking covered.
	ctrl.start_grind(party, {"headless": true, "auto_advance": false}, "plains")
	_ags.grind_party = party
	return ctrl


func _tick_between_battles(ctrl: Node) -> void:
	ctrl._state = ctrl.State.BETWEEN_BATTLES
	ctrl._between_battle_timer = 0.0
	ctrl._process(0.1)


func test_a_stop_rule_stops_the_controller_not_only_the_bookkeeping() -> void:
	var ctrl := _controller_with_party("Stopper")
	_ags.set_autogrind_rules([{
		"conditions": [{"type": "alive_count", "op": ">=", "value": 1}],
		"actions": [{"type": "stop_grinding"}], "enabled": true,
	}])
	assert_eq(_ags.pre_battle_check(), "",
		"precondition: NO built-in interrupt may be pending, or the grind stops for a reason that is not the rule")
	assert_false(_ags.evaluate_autogrind_rules(ctrl._party).is_empty(),
		"precondition: the rule must actually match this party")

	_tick_between_battles(ctrl)

	assert_false(ctrl.is_grinding(),
		"a stop_grinding rule must stop the CONTROLLER — the system's is_grinding flag going false while the loop requests the next battle is exactly the bug")
	assert_eq(ctrl._state, ctrl.State.IDLE,
		"the controller must land in IDLE, not BATTLE_RUNNING")


func test_the_control_keeps_grinding_so_the_test_above_means_something() -> void:
	## Identical fixture, no rules. If this also stopped, the test above would prove nothing —
	## which is precisely what happened with an unstocked party.
	var ctrl := _controller_with_party("Keeper")
	_ags.set_autogrind_rules([])
	assert_eq(_ags.pre_battle_check(), "",
		"precondition: no interrupt pending for the control either")

	_tick_between_battles(ctrl)

	assert_true(ctrl.is_grinding(),
		"with no rules and nothing wrong, the grind must continue — a fixture that stops on its own cannot demonstrate that a rule stopped it")
	assert_ne(ctrl._state, ctrl.State.IDLE, "the control must not be idle")


func test_a_system_side_stop_at_any_time_reaches_the_controller() -> void:
	## The signal half, on its own. Permadeath and other system-initiated stops happen outside the
	## rule-evaluation window, where the _process guard cannot see them.
	var ctrl := _controller_with_party("Signalled")
	ctrl._state = ctrl.State.BETWEEN_BATTLES
	assert_true(ctrl.is_grinding(), "precondition: grinding before the system stops itself")

	_ags.stop_autogrind("probe: system decided to stop")

	assert_false(ctrl.is_grinding(),
		"a system-side stop must bring the controller down with it — grind_stopped had no listeners at all")


func test_stopping_does_not_recurse_between_controller_and_system() -> void:
	## The controller's stop calls the system's stop, which emits the signal the controller now
	## listens to. Both sides guard on their own already-stopped state; this pins that they do.
	var ctrl := _controller_with_party("Recursion")
	ctrl._state = ctrl.State.BETWEEN_BATTLES
	ctrl.stop_grind("probe: controller stop")
	assert_false(ctrl.is_grinding(), "controller stopped")
	assert_false(_ags.is_grinding, "system stopped with it")


func test_the_controller_wires_itself_to_the_system_stop_in_production() -> void:
	## The wiring, driven through start_grind rather than asserted about the source. Without this
	## the behaviour tests above prove only that the handler works when something connects it.
	var ctrl = preload("res://src/autogrind/AutogrindController.gd").new()
	add_child_autofree(ctrl)
	var party: Array[Combatant] = []
	var c := Combatant.new()
	c.initialize({"name": "Wiring One", "max_hp": 1000, "max_mp": 100,
		"attack": 20, "defense": 20, "magic": 20, "speed": 20})
	add_child_autofree(c)
	c.add_item("potion", 10)
	party.append(c)

	assert_false(AutogrindSystem.grind_stopped.is_connected(ctrl._on_system_stopped),
		"control: a fresh controller is not connected, so the assertion below measures start_grind")
	ctrl.start_grind(party, {"headless": true, "auto_advance": false}, "plains")
	assert_true(AutogrindSystem.grind_stopped.is_connected(ctrl._on_system_stopped),
		"start_grind must subscribe the controller to the system's stop — the signal had zero listeners")
	ctrl.stop_grind("test teardown")
	assert_false(AutogrindSystem.grind_stopped.is_connected(ctrl._on_system_stopped),
		"and stop_grind must unsubscribe, or a stopped controller reacts to the next session's stop")
