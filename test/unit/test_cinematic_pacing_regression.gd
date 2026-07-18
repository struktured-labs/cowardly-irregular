extends GutTest

## struktured 2026-07-17: "not seeing anything I would call spotlighting in
## the battle. instead it seems like everyone swarms the monsters at the same
## time in like 2-3 seconds."
##
## Root: per-action performances existed but BattleManager never WAITED for
## them — inter-action delays were 0.025-0.075s engine, so all queued actions
## overlapped into a swarm. Fix: BattleScene requests a presentation_hold
## during the action_executing dispatch (synchronous emit) and every
## inter-action timer in BM routes through _consume_presentation_hold, so at
## showcase speed the queue serializes one-actor-at-a-time. Fast modes and
## headless paths never set the hold, so the 2026-07-12 stall fix stands.

const BM := "res://src/battle/BattleManager.gd"
const BS := "res://src/battle/BattleScene.gd"


func test_consume_returns_max_and_resets() -> void:
	var prior: float = BattleManager.presentation_hold
	BattleManager.presentation_hold = 0.95
	assert_almost_eq(BattleManager._consume_presentation_hold(0.025), 0.95, 0.001,
		"a requested hold outranks the base inter-action delay")
	assert_almost_eq(BattleManager.presentation_hold, 0.0, 0.001,
		"hold is single-shot — consumed once, next action reverts to base pacing")
	assert_almost_eq(BattleManager._consume_presentation_hold(0.075), 0.075, 0.001,
		"with no request the base delay passes through untouched (the stall-fix pacing)")
	BattleManager.presentation_hold = prior


func test_every_inter_action_timer_routes_through_consumer() -> void:
	var src: String = FileAccess.get_file_as_string(BM)
	assert_eq(src.count("create_timer(0.025)") + src.count("create_timer(0.075)"), 0,
		"no bare inter-action timers may remain — a bypassing site would let the swarm through on that path")
	assert_gt(src.count("create_timer(_consume_presentation_hold("), 4,
		"all 5 inter-action await sites route through the consumer")


func test_scene_requests_holds_only_at_showcase_speed() -> void:
	var src: String = FileAccess.get_file_as_string(BS)
	var i: int = src.find("func _on_action_executing")
	var body: String = src.substr(i, src.find("\nfunc ", i + 1) - i)
	assert_true("not turbo_mode and not autogrind_console_mode and Engine.time_scale <= 0.3" in body,
		"holds gate on showcase speed — 2x+/turbo/console keep the fast pacing he praised")
	assert_true("presentation_hold = 0.95 if showcase_this else 0.62" in body,
		"a full spell showcase holds the stage longer than a quick cast")
	assert_true("presentation_hold = 0.62" in body,
		"melee lunges hold long enough to read before the next actor moves")


func test_hold_request_happens_during_executing_dispatch() -> void:
	# The emit is synchronous, so setting the hold inside the handler lands
	# BEFORE BM's post-action await consumes it. If the request ever moves to
	# a deferred/async path this ordering breaks silently — pin the shape.
	var src: String = FileAccess.get_file_as_string(BS)
	var i: int = src.find("func _on_action_executing")
	var body: String = src.substr(i, src.find("\nfunc ", i + 1) - i)
	var gate_at: int = body.find("Engine.time_scale <= 0.3")
	var match_at: int = body.find("match action_type:", gate_at)
	assert_gt(gate_at, -1)
	assert_gt(match_at, gate_at,
		"hold requests live in the synchronous handler body, before the animation match")
