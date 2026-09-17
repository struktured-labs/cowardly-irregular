extends GutTest

## `member_ability` runs BETWEEN fights, and AutogrindSystem refuses any ability without an
## authored heal_amount/mp_amount — with `print("[AUTOGRIND] member_ability skipped")`. A
## silent no-op, which this project rates worse than a crash.
##
## MEASURED on live llama3 2026-09-17, 20 samples, intent "between fights have the fighter
## use power strike to stay sharp, the bard play battle hymn for the party, and the cleric
## heal whoever is hurt":
##
##     emitted by the model        53 member_ability actions
##     of those the engine refuses 40   power_strike 20 · battle_hymn 19
##
## ⛔ AND THE PROMPT COULD NOT FIX IT. Naming each member's runnable set in the kit block —
## "fighter: NOTHING — no ability that works between fights" — moved it to 37 of 51. THE
## PLAYER ASKED FOR THOSE ABILITIES BY NAME, so the model is being faithful to an
## instruction the engine cannot honour. No amount of prompt closes that.
##
##     delivered to the player, after the repair   12 of 12 RUNNABLE, both arms
##     compositions lost                            0 of 20
##
## The 41 dropped actions each carry a note saying why, which turns "my rule does nothing"
## into "your fighter has no ability that works between fights".

const RC := preload("res://src/llm/RuleComposer.gd")
const DP := preload("res://src/llm/DialoguePrompts.gd")


func before_each() -> void:
	AutobattleSystem._test_disable_persistence = true


func _rc():
	var c = RC.new()
	if c is Node:
		add_child_autofree(c)
	return c


func _sys():
	var s = get_tree().root.get_node_or_null("AutogrindSystem")
	assert_not_null(s, "CONTROL: AutogrindSystem autoload must exist")
	return s


func _rule(actions: Array) -> Dictionary:
	return {"conditions": [{"type": "always"}], "actions": actions, "enabled": true}


func _ma(member: String, ability: String) -> Dictionary:
	return {"type": "member_ability", "member": member, "ability": ability}


func _abilities(rules: Array) -> Array:
	var out: Array = []
	for r in rules:
		for a in r.get("actions", []):
			if str(a.get("type", "")) == "member_ability":
				out.append(str(a.get("ability", "")))
	return out


# ── the defect ────────────────────────────────────────────────────────────────

func test_an_ability_that_only_works_in_battle_is_dropped() -> void:
	## THE ARM. power_strike was 20 of 53, and every one reached the player as a rule that
	## prints a skip line and does nothing.
	var rules: Array = [_rule([_ma("fighter", "power_strike"), _ma("cleric", "cure")])]
	var notes: Array = _rc()._drop_unrunnable_member_abilities(rules, _sys())
	assert_eq(_abilities(rules), ["cure"], "only the one the engine can run survives")
	assert_gt(notes.size(), 0, "and the player is told why the other went")


func test_the_note_names_the_ability_and_the_member() -> void:
	## "my rule does nothing" is the thing this replaces. The note has to be specific
	## enough that the player can act on it.
	var rules: Array = [_rule([_ma("bard", "battle_hymn"), _ma("cleric", "cure")])]
	var notes: Array = _rc()._drop_unrunnable_member_abilities(rules, _sys())
	var joined: String = " ".join(PackedStringArray(notes))
	assert_true(joined.contains("battle_hymn"), "the note names the ability: %s" % joined)
	assert_true(joined.contains("bard"), "and the member: %s" % joined)


func test_a_rule_left_with_no_actions_goes_too() -> void:
	## validate_rule ACCEPTS an empty `actions` array, so a rule stripped of its only
	## action validates clean and does nothing at all — a quieter failure than the one
	## being repaired.
	var rules: Array = [_rule([_ma("fighter", "power_strike")]),
		_rule([{"type": "heal_party"}])]
	_rc()._drop_unrunnable_member_abilities(rules, _sys())
	assert_eq(rules.size(), 1, "the emptied rule is gone")
	assert_eq(str((rules[0]["actions"][0] as Dictionary)["type"]), "heal_party", "the other stands")


func test_a_rule_keeps_its_surviving_siblings() -> void:
	var rules: Array = [_rule([_ma("fighter", "power_strike"), {"type": "stop_grinding"}])]
	_rc()._drop_unrunnable_member_abilities(rules, _sys())
	assert_eq(rules.size(), 1, "the rule survives")
	assert_eq(rules[0]["actions"], [{"type": "stop_grinding"}], "with its usable action")


# ── it must never deliver an empty ruleset ────────────────────────────────────

func test_when_nothing_would_survive_the_composition_is_left_alone() -> void:
	## An empty ruleset is the save-wiping shape, not a repair. Leaving it intact lets the
	## refusal path run, which is honest; delivering zero rules is not.
	var rules: Array = [_rule([_ma("fighter", "power_strike")]), _rule([_ma("bard", "lullaby")])]
	var notes: Array = _rc()._drop_unrunnable_member_abilities(rules, _sys())
	assert_eq(rules.size(), 2, "both rules stay rather than leaving nothing")
	assert_eq(notes, [], "and nothing is claimed")


# ── it must not touch what it does not own ────────────────────────────────────

func test_a_runnable_ability_is_kept_and_silent() -> void:
	var rules: Array = [_rule([_ma("cleric", "cure"), _ma("mage", "channel")])]
	var notes: Array = _rc()._drop_unrunnable_member_abilities(rules, _sys())
	assert_eq(_abilities(rules), ["cure", "channel"], "both run, so both stay")
	assert_eq(notes, [], "and the notes panel says nothing about them")


func test_other_action_types_are_untouched() -> void:
	var rules: Array = [_rule([{"type": "heal_party"}, {"type": "restore_mp"},
		{"type": "switch_profile", "character_id": "cleric", "profile_index": 1}])]
	var before: Array = rules.duplicate(true)
	var notes: Array = _rc()._drop_unrunnable_member_abilities(rules, _sys())
	assert_eq(rules, before, "this repair owns member_ability and nothing else")
	assert_eq(notes, [], "and claims nothing")


# ── one owner for the predicate ───────────────────────────────────────────────

func test_the_engine_refuses_exactly_what_the_predicate_rejects() -> void:
	## THE RATCHET. The rule had three copies — this function's caller enforced it inline,
	## AutogrindUI keeps a private one, and the composer needed a third. If
	## _member_ability_apply ever stops delegating, the composer would drop actions the
	## engine would have run, or keep ones it refuses.
	var sys = _sys()
	var caster: Combatant = Combatant.new()
	add_child_autofree(caster)
	caster.combatant_name = "Cleric"
	caster.job = JobSystem.get_job("cleric")
	caster.job_level = 1
	caster.current_mp = 99
	## grind_party is Array[Combatant]. Assigning an untyped Array is a SCRIPT ERROR that
	## aborts the enclosing function — and this arm asserts its CONTROL first, so it scored
	## PASSING while every subject assert below went unrun. The M4 mutation surviving is
	## the only thing that showed it.
	sys.grind_party.clear()
	sys.grind_party.append(caster)
	## `protect` is in the cleric's OWN kit and still cannot run between fights — which is
	## the only shape that reaches the delegation. An ability the caster does not know is
	## refused several checks earlier, so an arm using one passes whatever the delegation
	## does. The first version of this arm used power_strike and survived the mutation.
	for aid in ["protect", "cure"]:
		var predicted: bool = sys.ability_works_between_battles(aid)
		var actual: Dictionary = sys._member_ability_apply(caster, aid, "")
		var refused_for_this_reason: bool = str(actual.get("reason", "")).contains("no between-battle effect")
		assert_eq(refused_for_this_reason, not predicted,
			"'%s': predicate says runnable=%s, engine said '%s'" % [aid, predicted, actual.get("reason", "ok")])
	sys.grind_party.clear()


# ── the prompt half ───────────────────────────────────────────────────────────

func test_the_prompt_names_each_members_runnable_set() -> void:
	var ctx := {"resolved": true, "party": [
		{"member": "cleric", "job_id": "cleric", "kit": ["cure", "protect"],
		"costs": {"cure": 6}, "profiles": ["Default"], "between_battle": ["cure"]},
		{"member": "fighter", "job_id": "fighter", "kit": ["power_strike"],
		"costs": {"power_strike": 8}, "profiles": ["Default"], "between_battle": []}]}
	var p: String = DP.build_rule_composition("autogrind", "help the party", [], ctx)
	assert_true(p.find("member_ability: cure (6 MP)") != -1, "the runnable set is named")
	assert_true(p.find("member_ability: NOTHING") != -1,
		"and a member with none is said so rather than left to be inferred")
	assert_true(p.find("only works inside a battle") != -1,
		"and the reason an id can be real and still refused")


# ── the repair must be WIRED, which no arm above can tell you ─────────────────

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


func test_a_real_composition_delivers_only_what_the_engine_can_run() -> void:
	## THE CONSEQUENCE ARM. Every arm above calls the helper by hand and stays green if
	## compose_async stops calling it — which is the defect.
	var rc = get_tree().root.get_node_or_null("RuleComposer")
	assert_not_null(rc, "CONTROL: RuleComposer autoload must exist")
	var sc := GDScript.new()
	sc.source_code = STUB_GAMELOOP
	sc.reload()
	_stub = Node.new()
	_stub.set_script(sc)
	_stub.name = "GameLoop"
	var ms: Array = []
	for j in ["fighter", "cleric"]:
		var c: Combatant = Combatant.new()
		add_child_autofree(c)
		c.combatant_name = str(j).capitalize()
		c.job = JobSystem.get_job(str(j))
		c.job_level = 1
		ms.append(c)
	_stub.party = ms
	get_tree().root.add_child(_stub)
	_svc = get_tree().root.get_node_or_null("LLMService")
	_orig_enabled = _svc.llm_enabled
	_orig_backends = _svc._backends.duplicate()
	_orig_active = _svc._active_backend
	_svc.llm_enabled = true
	_backend = preload("res://tools/replay_backend.gd").new()
	_backend.name = "ReplayBE"
	_backend.next_text = JSON.stringify({"name": "n", "description": "d",
		"rules_json": JSON.stringify([
			_rule([_ma("fighter", "power_strike"), _ma("cleric", "cure")])])})
	_svc.add_child(_backend)
	_svc._backends.clear()
	_svc._backends.append(_backend)
	_backend.request_finished.connect(_svc._on_backend_finished)
	_svc._active_backend = _backend
	var res: Dictionary = await rc.compose_async("autogrind", "help between fights", "", [])
	assert_eq(str(res.get("source", "")), "llm",
		"the composition must survive: %s" % str(res.get("errors", [])))
	assert_eq(_abilities(res.get("rules", [])), ["cure"],
		"only the runnable ability reaches the player, on the real path")
	assert_gt((res.get("notes", []) as Array).size(), 0, "and the drop is explained")
