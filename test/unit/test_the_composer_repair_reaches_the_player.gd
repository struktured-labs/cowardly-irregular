extends GutTest

## `.302` shipped "the composer no longer buries the player's rules". That claim
## was verified by source text.
##
## The repair itself was driven — every arm in
## test_the_composer_does_not_bury_the_players_intent calls
## _sink_unconditional_rules directly and it works. What was NOT observed is that
## compose_async REACHES it. That arm asserts:
##
##     src.contains("_sink_unconditional_rules(v[\"rules\"])")
##
## which is a fact about the source. It stays true if the call becomes
## unreachable — the call sits inside `if v.has("rules") and size() > 1`, and a
## guard clause or an early return above it would leave the arm green on a
## composer that never repairs anything. cowir-controller demonstrated exactly
## that shape on their own guard: branch present, early return above it, source
## arm GREEN and behaviour RED.
##
## So this drives the shipping path. ReplayBackend hands LLMService a captured
## reply, compose_async runs for real — validator, mp guards, unusable-rule drop,
## then the sink — and the assertions read what a player would get back.
##
## The reply below is the shape live llama3 produced: the fallback first, the
## rules the player asked for beneath it.

const ReplayBackend := preload("res://tools/replay_backend.gd")

var _svc = null
var _rc = null
var _backend = null
var _orig_backends: Array = []
var _orig_active = null
var _orig_enabled: bool = true


func before_each() -> void:
	_svc = get_tree().root.get_node_or_null("LLMService")
	_rc = get_tree().root.get_node_or_null("RuleComposer")
	assert_not_null(_svc, "CONTROL: LLMService autoload must exist")
	assert_not_null(_rc, "CONTROL: RuleComposer autoload must exist")
	if _svc == null or _rc == null:
		return
	_orig_enabled = _svc.llm_enabled
	_orig_backends = _svc._backends.duplicate()
	_orig_active = _svc._active_backend
	_svc.llm_enabled = true
	_backend = ReplayBackend.new()
	_backend.name = "ReplayBE"
	_svc.add_child(_backend)
	_svc._backends.clear()
	_svc._backends.append(_backend)
	_backend.request_finished.connect(_svc._on_backend_finished)
	_svc._active_backend = _backend


func after_each() -> void:
	if _svc == null:
		return
	if _backend and is_instance_valid(_backend):
		_backend.request_finished.disconnect(_svc._on_backend_finished)
		_svc.remove_child(_backend)
		_backend.free()
	_svc._backends.clear()
	for b in _orig_backends:
		_svc._backends.append(b)
	_svc._active_backend = _orig_active
	_svc.llm_enabled = _orig_enabled


func _reply(rules: Array) -> String:
	return JSON.stringify({
		"name": "Keep everyone alive",
		"description": "heal the moment anyone drops low",
		"rules_json": JSON.stringify(rules),
	})


func _catch_all() -> Dictionary:
	return {"conditions": [{"type": "always"}], "actions": [{"type": "attack"}], "enabled": true}


func _cure_at(pct: int) -> Dictionary:
	return {
		"conditions": [{"type": "ally_hp_percent", "op": "<", "value": pct}],
		"actions": [{"type": "ability", "id": "cure", "target": "lowest_hp_ally"}],
		"enabled": true,
	}


func _first_action_id(rule: Dictionary) -> String:
	var a: Dictionary = (rule.get("actions", [])[0] as Dictionary)
	return str(a.get("id", a.get("type", "")))


# ── the claim, observed through the shipping path ─────────────────────────────

func test_compose_async_returns_the_players_rules_above_the_fallback() -> void:
	## THE ARM. Source text proves the call is written; this proves it is reached.
	_backend.next_text = _reply([_catch_all(), _cure_at(40)])
	var res: Dictionary = await _rc.compose_async("autobattle", "heal when we are hurt", "cleric")
	var rules: Array = res.get("rules", []) as Array
	assert_eq(rules.size(), 2, "both rules must survive the pipeline: %s" % str(res.get("errors", [])))
	if rules.size() < 2:
		return
	assert_eq(_first_action_id(rules[0]), "cure",
		"the rule the player asked for must run first — it was buried under the fallback")
	assert_eq(_first_action_id(rules[1]), "attack",
		"and the catch-all must be last")


func test_the_composition_actually_reached_the_player() -> void:
	## CONTROL, and it is load-bearing: compose_async falls back to a canned rule
	## set when the reply is unusable. A fallback would also put a catch-all last,
	## so without this the arm above could pass on a composition the model never
	## produced.
	_backend.next_text = _reply([_catch_all(), _cure_at(40)])
	var res: Dictionary = await _rc.compose_async("autobattle", "heal when we are hurt", "cleric")
	assert_eq(str(res.get("source", "")), "llm",
		"the repair must have run on the MODEL's rules, not on a fallback")


func test_the_player_is_told_a_rule_was_unreachable() -> void:
	_backend.next_text = _reply([_catch_all(), _cure_at(40)])
	var res: Dictionary = await _rc.compose_async("autobattle", "heal when we are hurt", "cleric")
	var joined: String = " ".join(PackedStringArray(res.get("notes", []) as Array))
	assert_true(joined.find("could never run") != -1,
		"the repair must surface what it moved: %s" % joined)


# ── it must not fire on a well-formed composition ─────────────────────────────

func test_a_well_formed_composition_is_returned_unchanged_and_unremarked() -> void:
	## CORRECT-WORK through the real path: fallback already last, nothing to say.
	_backend.next_text = _reply([_cure_at(40), _catch_all()])
	var res: Dictionary = await _rc.compose_async("autobattle", "heal when we are hurt", "cleric")
	var rules: Array = res.get("rules", []) as Array
	assert_eq(rules.size(), 2, "both rules must survive")
	if rules.size() >= 2:
		assert_eq(_first_action_id(rules[0]), "cure", "order must be untouched")
	var joined: String = " ".join(PackedStringArray(res.get("notes", []) as Array))
	assert_eq(joined.find("could never run"), -1,
		"nothing was shadowed, so the player must not be told otherwise: %s" % joined)


# ── controls ──────────────────────────────────────────────────────────────────

func test_the_replay_backend_is_really_driving_this() -> void:
	## CONTROL: if the backend were not installed, every test here would measure
	## the fallback path and pass for the wrong reason.
	assert_eq(str(_backend.backend_id()), "replay", "the replay backend must be active")
	assert_true(_svc._active_backend == _backend, "LLMService must be routed to it")
	assert_true(_svc.llm_enabled, "and the service must be enabled, or compose_async short-circuits")
