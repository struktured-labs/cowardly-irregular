extends GutTest

## A `battle` step hides the Director while the spotlight duel plays, but _process kept counting
## a held B (ui_cancel — the duel menu's back button) toward the 1.5s skip. Holding B in the duel
## for 1.5s therefore set _skipping with no indicator on screen: every post-duel line was dropped
## and cutscene_skipped fired mid-battle. The skip tracker is now inert while a battle owns the
## screen, and a hold carried into the battle resets at that boundary.

const DirectorScript = preload("res://src/cutscene/CutsceneDirector.gd")

var _d: Node
var _stub: Node = null


## Stands in for GameLoop.start_solo_battle: a few frames of "battle", then victory.
class StubLoop extends Node:
	var director: Node = null
	var flag_seen_in_flight: bool = false
	var calls: int = 0

	func start_solo_battle(_who: String, _enemy: String, _opts: Dictionary) -> String:
		calls += 1
		for i in 3:
			await get_tree().process_frame
		flag_seen_in_flight = director._battle_in_flight
		Input.action_press("ui_cancel")
		director._process(1.0)
		director._process(1.0)  # 2.0s of held B, past SKIP_THRESHOLD
		for i in 2:
			await get_tree().process_frame
		Input.action_release("ui_cancel")
		return "victory"


func before_each() -> void:
	Input.action_release("ui_cancel")
	_d = DirectorScript.new()
	add_child_autofree(_d)
	_d._skipping = false
	_d._battle_in_flight = false
	_d._skip_hold_time = 0.0


func after_each() -> void:
	Input.action_release("ui_cancel")
	if _d and is_instance_valid(_d):
		_d._active = false
	if _stub and is_instance_valid(_stub):
		_stub.get_parent().remove_child(_stub)
		_stub.free()
	_stub = null


func _install_stub() -> StubLoop:
	assert_null(get_tree().root.get_node_or_null("GameLoop"), "control: no real GameLoop in the test tree")
	var stub := StubLoop.new()
	stub.name = "GameLoop"
	stub.director = _d
	get_tree().root.add_child(stub)
	_stub = stub
	return stub


func test_held_cancel_does_not_count_toward_a_skip_while_a_battle_owns_the_screen() -> void:
	_d._active = true
	_d._battle_in_flight = true
	Input.action_press("ui_cancel")
	_d._process(1.0)
	_d._process(1.0)
	assert_false(_d._skipping, "2.0s of held B during a duel must not skip the scene")
	assert_eq(_d._skip_hold_time, 0.0, "the hold does not accumulate while the duel plays")
	assert_false(_d._skip_indicator.visible, "no skip bar creeps while the Director is off-screen")


func test_the_same_hold_skips_when_no_battle_is_in_flight() -> void:
	# ARM+: a tracker that never fired would pass the test above.
	_d._active = true
	_d._battle_in_flight = false
	Input.action_press("ui_cancel")
	_d._process(1.0)
	assert_false(_d._skipping, "control: 1.0s is under the 1.5s threshold")
	_d._process(1.0)
	assert_true(_d._skipping, "control: 2.0s of held B outside a duel skips")


func test_a_hold_carried_into_the_battle_resets_at_the_boundary() -> void:
	_d._active = true
	Input.action_press("ui_cancel")
	_d._process(1.0)
	assert_eq(_d._skip_hold_time, 1.0, "control: the hold was accumulating before the duel")
	_d._battle_in_flight = true
	_d._process(0.1)
	assert_eq(_d._skip_hold_time, 0.0, "entering the duel discards the partial hold — it cannot ambush the post-duel line")
	assert_false(_d._skipping)


func test_the_battle_step_owns_the_flag_and_a_mid_duel_hold_leaves_the_scene_unskipped() -> void:
	var stub := _install_stub()
	_d._active = true
	var done := [false]
	var runner := func() -> void:
		await _d._execute_step({"type": "battle", "combatants": ["fighter"], "enemies": ["slime"]})
		done[0] = true
	runner.call()
	var frames := 0
	while not done[0] and frames < 60:
		await get_tree().process_frame
		frames += 1
	assert_true(done[0], "control: the stubbed duel resolves")
	assert_eq(stub.calls, 1, "control: the step ran the duel once (victory, no retry)")
	assert_true(stub.flag_seen_in_flight, "_battle_in_flight is raised while start_solo_battle is awaited")
	assert_false(_d._battle_in_flight, "and lowered once the duel returns")
	assert_false(_d._skipping, "2.0s of held B inside the duel left the scene unskipped — the post-duel lines still play")
	assert_true(_d.visible, "the Director is back on screen after the duel")
