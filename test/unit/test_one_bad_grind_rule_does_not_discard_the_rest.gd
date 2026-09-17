extends GutTest

## `_drop_unusable_rules` — drop the offending rule, keep the rest, and TELL the player —
## shipped for AUTOBATTLE only. The grind domain was left out, and the asymmetry cost
## exactly what the policy was written to prevent.
##
## MEASURED on 50 captured live replies across five deliberately messy intents (vague,
## compound, negatively-phrased — unlike the bench's short idiomatic asks), replayed
## through the real compose_async with a control reply per case that MUST be refused:
##
##     before   46 of 50      after   50 of 50      controls refused, both runs
##
## The four losses were one bad rule each, with the rest of the set valid:
##
##     {"op": null}                      a null operator
##     reached_level with a null value   no number to recover
##     {"type":"rest"}                   an action the grammar does not have
##     a rule missing conditions/actions entirely
##
## ⛔ NONE of those is repairable by lookup — that is the point. Every other repair on this
## branch reads the engine's own vocabulary; here there is nothing to read, so dropping the
## rule is the only honest move, and it is the move this project already chose next door.
##
## The SUBSTANTIVE FLOOR comes with it and is the half that matters: a rescue only happens
## when a rule carrying a REAL condition survives. Without it a composition can be "rescued"
## down to a bare {always} line and handed to the player as the strategy they asked for,
## which is worse than the canned fallback — that at least admits what it is.

const RC := preload("res://src/llm/RuleComposer.gd")

const STUB_GAMELOOP := """
extends Node
var party: Array = []
"""

var _stub: Node = null
var _svc = null
var _backend = null
var _orig_backends: Array = []
var _orig_active = null
var _orig_enabled: bool = true


func before_each() -> void:
	assert_null(get_tree().root.get_node_or_null("GameLoop"),
		"CONTROL: no real GameLoop may be in the tree when this file runs")
	AutobattleSystem._test_disable_persistence = true


func after_each() -> void:
	if _backend != null and is_instance_valid(_backend):
		_backend.request_finished.disconnect(_svc._on_backend_finished)
		_svc.remove_child(_backend)
		_backend.free()
		_backend = null
		_svc._backends.clear()
		for b in _orig_backends:
			_svc._backends.append(b)
		_svc._active_backend = _orig_active
		_svc.llm_enabled = _orig_enabled
	if _stub != null and is_instance_valid(_stub):
		get_tree().root.remove_child(_stub)
		_stub.free()
	_stub = null


func _party() -> void:
	var sc := GDScript.new()
	sc.source_code = STUB_GAMELOOP
	sc.reload()
	_stub = Node.new()
	_stub.set_script(sc)
	_stub.name = "GameLoop"
	var ms: Array = []
	for j in ["fighter", "cleric", "mage", "rogue", "bard"]:
		var c: Combatant = Combatant.new()
		add_child_autofree(c)
		c.combatant_name = str(j).capitalize()
		c.job = JobSystem.get_job(str(j))
		c.job_level = 1
		ms.append(c)
	_stub.party = ms
	get_tree().root.add_child(_stub)


func _compose(rules: Array) -> Dictionary:
	var rc = get_tree().root.get_node_or_null("RuleComposer")
	assert_not_null(rc, "CONTROL: RuleComposer autoload must exist")
	_svc = get_tree().root.get_node_or_null("LLMService")
	assert_not_null(_svc, "CONTROL: LLMService autoload must exist")
	_orig_enabled = _svc.llm_enabled
	_orig_backends = _svc._backends.duplicate()
	_orig_active = _svc._active_backend
	_svc.llm_enabled = true
	_backend = preload("res://tools/replay_backend.gd").new()
	_backend.name = "ReplayBE"
	_backend.next_text = JSON.stringify({"name": "n", "description": "d",
		"rules_json": JSON.stringify(rules)})
	_svc.add_child(_backend)
	_svc._backends.clear()
	_svc._backends.append(_backend)
	_backend.request_finished.connect(_svc._on_backend_finished)
	_svc._active_backend = _backend
	return await rc.compose_async("autogrind", "grind safely", "", [])


func _good(status: String = "poison") -> Dictionary:
	return {"conditions": [{"type": "member_status", "value": status}],
		"actions": [{"type": "stop_grinding"}], "enabled": true}


func _unrepairable() -> Dictionary:
	## `rest` is not in AUTOGRIND_ACTION_TYPES and no lookup can say what it meant.
	return {"conditions": [{"type": "party_hp_min", "op": "<", "value": 30}],
		"actions": [{"type": "rest"}], "enabled": true}


# ── the defect ────────────────────────────────────────────────────────────────

func test_one_unusable_rule_does_not_take_the_others_with_it() -> void:
	## THE ARM. Before this, the player got the canned draft.
	_party()
	var res: Dictionary = await _compose([_good("poison"), _unrepairable(), _good("burn")])
	assert_eq(str(res.get("source", "")), "llm",
		"the composition must survive: %s" % str(res.get("errors", [])))
	assert_eq((res.get("rules", []) as Array).size(), 2, "the two good rules are delivered")
	assert_gt((res.get("notes", []) as Array).size(), 0, "and the drop is reported to the player")


func test_the_note_names_why_the_rule_went() -> void:
	## The notes panel is what stops this being a silent edit of the player's strategy.
	_party()
	var res: Dictionary = await _compose([_good(), _unrepairable()])
	var joined: String = " ".join(PackedStringArray(res.get("notes", [])))
	assert_true(joined.to_lower().contains("rest") or joined.to_lower().contains("action"),
		"the note must say what was wrong: %s" % joined)


# ── the substantive floor, which is the half that can make this worse ─────────

func test_a_rescue_down_to_nothing_but_always_is_refused() -> void:
	## A composition "rescued" to a bare {always} line reads as a success and hands the
	## player a one-liner labelled as the strategy they asked for. The canned fallback is
	## at least honest about being one.
	_party()
	var bare := {"conditions": [{"type": "always"}],
		"actions": [{"type": "stop_grinding"}], "enabled": true}
	var res: Dictionary = await _compose([bare, _unrepairable()])
	assert_ne(str(res.get("source", "")), "llm",
		"no substantive rule survives, so the rescue must not be made")


func test_a_composition_where_every_rule_is_bad_is_still_refused() -> void:
	_party()
	var res: Dictionary = await _compose([_unrepairable(), _unrepairable()])
	assert_ne(str(res.get("source", "")), "llm", "there is nothing to keep")


# ── it must not fire on a healthy composition ─────────────────────────────────

func test_a_valid_ruleset_keeps_every_rule_and_says_nothing_about_drops() -> void:
	_party()
	var res: Dictionary = await _compose([_good("poison"), _good("burn"), _good("blind")])
	assert_eq(str(res.get("source", "")), "llm", "CONTROL: it must survive")
	assert_eq((res.get("rules", []) as Array).size(), 3, "every rule delivered")
	var joined: String = " ".join(PackedStringArray(res.get("notes", [])))
	assert_false(joined.to_lower().contains("dropped"),
		"nothing was dropped, so nothing may say so: %s" % joined)
