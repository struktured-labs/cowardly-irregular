extends GutTest

## Measured on the engine path against struktured's own 7 requests (.812, llama3): 13 of 14 ordinary level-ups and area
## changes came back as a NUDGE. The request's JSON was written with sorted keys, so the schema reached the server as
## confidence, reason, verdict: the model wrote its reason first and then picked a verdict to fit it. In authored order
## (verdict first) the same prompts answer no_change 14 of 14, and three wipes in a row still nudge 10 of 10.
## A replay in Python missed this for a day: it sent verdict first. A replica in another language is another instrument.

const DAEMON := preload("res://src/llm/RebalanceDaemon.gd")

var _constants: Dictionary = {}


func before_each() -> void:
	_constants = GameState.game_constants.duplicate(true)


func after_each() -> void:
	GameState.game_constants = _constants.duplicate(true)


func _backend(format: String) -> HTTPBackend:
	var b := HTTPBackend.new()
	b.api_format = format
	b.model = "m"
	autofree(b)
	return b


func _body(format: String, schema: Dictionary) -> String:
	return _backend(format)._build_body("Judge the curve.", {"json_mode": true, "json_schema": schema})


func test_the_verdict_reaches_the_server_before_the_reason() -> void:
	for format in ["ollama", "openai"]:
		var body: String = _body(format, DAEMON.wire_schema())
		var at_verdict: int = body.find("\"verdict\"")
		assert_gt(at_verdict, -1, "CONTROL: the %s body carries the schema" % format)
		for later in ["\"confidence\"", "\"deltas\"", "\"reason\""]:
			assert_gt(body.find(later), at_verdict, "%s: %s must come after the verdict, or the model explains first and decides second" % [format, later])


func test_control_sorted_keys_put_the_reason_first() -> void:
	var sorted: String = JSON.stringify(JSON.parse_string(_body("ollama", DAEMON.wire_schema())))
	assert_lt(sorted.find("\"reason\""), sorted.find("\"verdict\""), "CONTROL: the default stringify is the shipped order, reason before verdict")


func test_every_features_keys_go_out_as_authored() -> void:
	var schema: Dictionary = LLMService.to_json_schema({"zeta": "String", "alpha": "String", "mid": ["b", "a"]})
	for format in ["ollama", "openai"]:
		var body: String = _body(format, schema)
		assert_lt(body.find("\"zeta\""), body.find("\"alpha\""), "%s: the first key authored is the first key sent" % format)
		assert_lt(body.find("\"alpha\""), body.find("\"mid\""), "%s: and the rest follow in order" % format)
		assert_eq(JSON.parse_string(body) is Dictionary, true, "%s: CONTROL: the body is still JSON" % format)


func _daemon_with(trigger: String) -> RebalanceDaemon:
	var d := RebalanceDaemon.new()
	d.pending.append({
		"trigger": trigger, "ts": 0, "context_summary": "x", "status": "proposed",
		"verdict": "nudge_easier", "confidence": 0.9, "reason": "r",
		"deltas": [{"constant": "exp_multiplier", "multiplier": 1.05, "reason": "r"}],
	})
	return d


func test_a_nudge_from_a_level_up_or_a_new_area_waits_for_the_player() -> void:
	var before: float = float(GameState.game_constants.get("exp_multiplier", 1.0))
	for trigger in DAEMON.NO_EVIDENCE_TRIGGERS:
		var d := _daemon_with(trigger)
		assert_eq(d.try_auto_apply(0), DAEMON.APPLY_NEEDS_REVIEW, "a confident, in-band nudge from '%s' is still not applied unasked" % trigger)
		assert_eq(str(d.pending[0].get("status", "")), "needs_review")
	assert_eq(float(GameState.game_constants.get("exp_multiplier", 1.0)), before, "and the XP rate has not moved")
	assert_eq(Array(DAEMON.NO_EVIDENCE_TRIGGERS).size(), 2, "CONTROL: both no-evidence triggers were judged")


func test_control_the_same_nudge_from_a_wipe_is_applied() -> void:
	var before: float = float(GameState.game_constants.get("exp_multiplier", 1.0))
	var d := _daemon_with(DAEMON.TRIGGER_PARTY_WIPE)
	assert_eq(d.try_auto_apply(0), DAEMON.APPLY_APPLIED, "CONTROL: a wipe is evidence, and its nudge applies as before")
	assert_gt(float(GameState.game_constants.get("exp_multiplier", 1.0)), before, "CONTROL: the XP rate moved")


func test_control_the_player_can_still_apply_a_waiting_nudge() -> void:
	var before: float = float(GameState.game_constants.get("exp_multiplier", 1.0))
	var d := _daemon_with(DAEMON.TRIGGER_LEVEL_UP)
	d.try_auto_apply(0)
	assert_eq(d.force_apply(0), DAEMON.APPLY_APPLIED, "CONTROL: review is a wait, not a refusal")
	assert_gt(float(GameState.game_constants.get("exp_multiplier", 1.0)), before)
