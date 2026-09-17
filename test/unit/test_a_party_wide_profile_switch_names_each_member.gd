extends GutTest

## `switch_profile` names ONE member, and `validate_rule` checks only that the KEY is
## present — so any string passes it.
##
## MEASURED on live llama3 2026-09-17, 20 samples, intent "when the party drops below half
## HP, switch everyone over to their defensive autobattle script":
##
##     ""          7    passes validation, then apply_autogrind_actions skips on `!= ""`
##     everyone    4    the model reaching for something the grammar cannot say
##     *           4
##     all         3
##     defensive   1    the profile NAME in the id field
##     None        1
##                 --
##                 20 of 20 named nobody in the party
##
## ⛔ The middle eleven are not no-ops. `set_active_profile` calls
## `_ensure_character_profiles` FIRST, so an invented id CREATES a profile block and
## `_save_character_profiles` persists it — probed: `character_profiles["everyone"]` with
## 3 profiles and active=1, bound for user://autobattle/profiles.json in real play.
##
## Two halves. The prompt now names each member's slots and says there is no "everyone";
## the composer expands a party word into one action per member and drops an id that
## names nobody, because the alternative is letting it reach the save.

const RC := preload("res://src/llm/RuleComposer.gd")
const DP := preload("res://src/llm/DialoguePrompts.gd")

const STUB_GAMELOOP := """
extends Node
var party: Array = []
"""

var _stub: Node = null
var _orig_persistence: bool = false


func before_each() -> void:
	assert_null(get_tree().root.get_node_or_null("GameLoop"),
		"CONTROL: no real GameLoop may be in the tree when this file runs")
	_orig_persistence = AutobattleSystem._test_disable_persistence
	AutobattleSystem._test_disable_persistence = true


func after_each() -> void:
	AutobattleSystem.character_profiles.erase("captain_nobody")
	AutobattleSystem.character_profiles.erase("everyone")
	AutobattleSystem._test_disable_persistence = _orig_persistence
	if _stub != null and is_instance_valid(_stub):
		get_tree().root.remove_child(_stub)
		_stub.free()
	_stub = null


func _rc():
	var c = RC.new()
	if c is Node:
		add_child_autofree(c)
	return c


func _ctx(members: Array) -> Dictionary:
	var party: Array = []
	for m in members:
		party.append({"member": str(m), "job_id": str(m), "kit": [], "costs": {},
			"profiles": ["Default", "Defensive", "Aggressive"]})
	return {"resolved": true, "party": party}


func _rule(cid: Variant, idx: int = 1, extra_actions: Array = []) -> Dictionary:
	var actions: Array = [{"type": "switch_profile", "character_id": cid, "profile_index": idx}]
	for a in extra_actions:
		actions.append(a)
	return {"conditions": [{"type": "party_hp_avg", "op": "<", "value": 50}],
		"actions": actions, "enabled": true}


func _switch_ids(rules: Array) -> Array:
	var out: Array = []
	for r in rules:
		for a in r.get("actions", []):
			if str(a.get("type", "")) == "switch_profile":
				out.append(str(a.get("character_id", "")))
	return out


# ── the defect ────────────────────────────────────────────────────────────────

func test_a_party_word_becomes_one_action_per_member() -> void:
	## THE ARM. "everyone" is what the model writes 11 times in 20 and what the player
	## actually asked for; the grammar has no way to say it.
	var rules: Array = [_rule("everyone")]
	var notes: Array = _rc()._normalise_switch_profile(rules, _ctx(["fighter", "cleric", "mage"]))
	assert_eq(_switch_ids(rules), ["fighter", "cleric", "mage"], "one action per member, in order")
	assert_gt(notes.size(), 0, "and the player is told what the composer read it as")


func test_every_party_word_the_model_actually_wrote_is_covered() -> void:
	## `everyone`, `*` and `all` were 11 of the 20. A repair covering only the first
	## would look right and leave two thirds of the measured shapes reaching the save.
	for word in ["everyone", "all", "*", "party", "everybody"]:
		var rules: Array = [_rule(word)]
		_rc()._normalise_switch_profile(rules, _ctx(["fighter", "cleric"]))
		assert_eq(_switch_ids(rules), ["fighter", "cleric"], "'%s' means the party" % word)


func test_the_members_come_from_the_party_not_from_a_list_here() -> void:
	## A hardcoded starter roster passes both arms above and fails this one.
	var rules: Array = [_rule("everyone")]
	_rc()._normalise_switch_profile(rules, _ctx(["mira", "bram"]))
	assert_eq(_switch_ids(rules), ["mira", "bram"], "the live party's own names")


func test_the_profile_index_rides_along_unchanged() -> void:
	## The model picked slot 1 in 18 of 20. A clone that lost it would switch every
	## member to Default — the opposite of the defensive stance the player asked for.
	var rules: Array = [_rule("everyone", 2)]
	_rc()._normalise_switch_profile(rules, _ctx(["fighter", "cleric"]))
	for r in rules:
		for a in r["actions"]:
			assert_eq(int(a.get("profile_index", -1)), 2, "each clone keeps the slot asked for")


# ── the id that reaches the save ──────────────────────────────────────────────

func test_an_id_naming_nobody_is_dropped() -> void:
	var rules: Array = [_rule("captain_nobody")]
	var notes: Array = _rc()._normalise_switch_profile(rules, _ctx(["fighter"]))
	assert_eq(_switch_ids(rules), [], "the action must not survive to reach set_active_profile")
	assert_gt(notes.size(), 0, "and the player is told it was dropped")


func test_an_empty_character_id_is_dropped_too() -> void:
	## 7 of the 20, and the one that passes validate_rule most quietly: the key IS
	## present, so the grammar check is satisfied, and the engine skips it in silence.
	var rules: Array = [_rule("")]
	_rc()._normalise_switch_profile(rules, _ctx(["fighter"]))
	assert_eq(_switch_ids(rules), [], "an empty id names nobody")


func test_what_the_drop_prevents() -> void:
	## THE CONSEQUENCE ARM, and the reason dropping beats leaving it to the engine:
	## set_active_profile does not reject an unknown character, it CREATES one.
	assert_false(AutobattleSystem.character_profiles.has("captain_nobody"),
		"CONTROL: the phantom must not exist before this runs")
	AutogrindSystem.apply_autogrind_actions([
		{"type": "switch_profile", "character_id": "captain_nobody", "profile_index": 1}])
	assert_true(AutobattleSystem.character_profiles.has("captain_nobody"),
		"an invented id creates a profile block — this is what the repair keeps out of the save")


# ── it must not invent, and must not act blind ────────────────────────────────

func test_a_real_member_is_left_exactly_alone() -> void:
	var rules: Array = [_rule("cleric")]
	var notes: Array = _rc()._normalise_switch_profile(rules, _ctx(["fighter", "cleric"]))
	assert_eq(_switch_ids(rules), ["cleric"], "a named member must not be rewritten")
	assert_eq(notes, [], "and must produce no note")


func test_with_no_live_party_nothing_is_touched() -> void:
	## Headless, tests, and the console opened outside a run. Unable to verify is not the
	## same as verified absent — dropping here would delete rules on the strength of an
	## empty context.
	var rules: Array = [_rule("everyone"), _rule("captain_nobody")]
	var notes: Array = _rc()._normalise_switch_profile(rules, {})
	assert_eq(_switch_ids(rules), ["everyone", "captain_nobody"], "both must survive untouched")
	assert_eq(notes, [], "and nothing may be claimed")


func test_a_context_that_says_it_failed_is_not_trusted() -> void:
	## `{}` is caught by the empty-party check as well, so the arm above cannot tell you
	## whether the `resolved` flag is load-bearing — removing it leaves that arm green.
	## A context carrying members while reporting failure is the case only this flag
	## answers, and trusting it would drop rules on the strength of a lookup that failed.
	var ctx: Dictionary = _ctx(["fighter", "cleric"])
	ctx["resolved"] = false
	var rules: Array = [_rule("everyone"), _rule("captain_nobody")]
	var notes: Array = _rc()._normalise_switch_profile(rules, ctx)
	assert_eq(_switch_ids(rules), ["everyone", "captain_nobody"],
		"an unresolved context must be treated as no information, not as a party list")
	assert_eq(notes, [], "and nothing may be claimed from it")


func test_the_rules_other_actions_survive() -> void:
	## CONTROL on the scan: it edits an actions array in place, so a neighbour must not
	## be shifted out by an insert or removed by a drop.
	var stop := {"type": "stop_grinding"}
	var rules: Array = [_rule("captain_nobody", 1, [stop]), _rule("everyone", 1, [stop])]
	_rc()._normalise_switch_profile(rules, _ctx(["fighter", "cleric"]))
	assert_true(rules[0]["actions"].has(stop), "the drop must not take its neighbour: %s" % str(rules[0]))
	assert_true(rules[1]["actions"].has(stop), "nor must the expansion lose it: %s" % str(rules[1]))
	assert_eq(_switch_ids(rules), ["fighter", "cleric"], "CONTROL: one dropped, one expanded")


# ── the prompt half ───────────────────────────────────────────────────────────

func test_the_prompt_names_each_members_slots() -> void:
	var p: String = DP.build_rule_composition("autogrind", "switch when hurt", [],
		_ctx(["fighter", "cleric"]))
	assert_true(p.find("switch_profile slots: 0 Default, 1 Defensive, 2 Aggressive") != -1,
		"the model must be told which slot numbers exist and what they are")


func test_the_prompt_says_there_is_no_everyone() -> void:
	## The grammar previously said only "character_id (PC id string)", which is what the
	## model answered with a party word. Naming the absence is the half that stops it.
	var p: String = DP.build_rule_composition("autogrind", "switch when hurt", [], _ctx(["fighter"]))
	assert_true(p.find("there is no \"everyone\"") != -1, "the absence must be stated")
	## Anchored inside ONE rendered line: the block wraps, and a phrase spanning the wrap
	## cannot match however correct the prompt is.
	assert_true(p.find("switch_profile action per member") != -1,
		"and the grammar's own way to say it must be given")


# ── the shapes that survived the prompt fix, measured at 4 of 36 ──────────────

func test_a_list_of_members_becomes_one_action_each() -> void:
	## 3 of 36 after the prompt named the members: the model listed all five in the id
	## slot. Same shape member_status showed — "each of them", spelled as an array.
	var rules: Array = [_rule(["fighter", "cleric", "mage"])]
	var notes: Array = _rc()._normalise_switch_profile(rules, _ctx(["fighter", "cleric", "mage"]))
	assert_eq(_switch_ids(rules), ["fighter", "cleric", "mage"], "one action per listed member")
	assert_gt(notes.size(), 0, "and the player is told it was split")


func test_a_list_keeps_only_the_members_who_exist() -> void:
	## The expansion is still a lookup: a name in the list that is in no party must not
	## be carried through just because its neighbours were valid.
	var rules: Array = [_rule(["fighter", "captain_nobody"])]
	_rc()._normalise_switch_profile(rules, _ctx(["fighter", "cleric"]))
	assert_eq(_switch_ids(rules), ["fighter"], "the real member survives, the invented one does not")


func test_a_list_of_nobodies_is_dropped_whole() -> void:
	var rules: Array = [_rule(["captain_nobody", "nobody_else"])]
	_rc()._normalise_switch_profile(rules, _ctx(["fighter"]))
	assert_eq(_switch_ids(rules), [], "nothing in it names anyone, so nothing may reach the save")


func test_a_one_item_profile_index_list_is_unwrapped() -> void:
	var rules: Array = [{"conditions": [], "enabled": true, "actions": [
		{"type": "switch_profile", "character_id": "cleric", "profile_index": [1]}]}]
	_rc()._normalise_switch_profile(rules, _ctx(["fighter", "cleric"]))
	assert_eq(int(rules[0]["actions"][0]["profile_index"]), 1, "the slot is the number it holds")


func test_an_incomplete_switch_profile_is_dropped_rather_than_losing_everything() -> void:
	## validate_rule REQUIRES both keys, and compose_async turns any grammar error into
	## the canned draft. 2 of 36 arrived missing one — dropping that action costs the
	## player one row instead of their whole ruleset.
	var rules: Array = [
		{"conditions": [], "enabled": true, "actions": [{"type": "switch_profile", "profile_index": 1}]},
		{"conditions": [], "enabled": true, "actions": [{"type": "switch_profile", "character_id": "cleric"}]},
	]
	var notes: Array = _rc()._normalise_switch_profile(rules, _ctx(["fighter", "cleric"]))
	assert_eq(_switch_ids(rules), [], "both incomplete actions must go")
	assert_eq(notes.size(), 2, "and each is reported: %s" % str(notes))


# ── the repair must be WIRED, which no arm above can tell you ─────────────────

var _svc = null
var _backend = null
var _orig_backends: Array = []
var _orig_active = null
var _orig_enabled: bool = true


func _replay(reply: String) -> void:
	_svc = get_tree().root.get_node_or_null("LLMService")
	assert_not_null(_svc, "CONTROL: LLMService autoload must exist")
	_orig_enabled = _svc.llm_enabled
	_orig_backends = _svc._backends.duplicate()
	_orig_active = _svc._active_backend
	_svc.llm_enabled = true
	_backend = preload("res://tools/replay_backend.gd").new()
	_backend.name = "ReplayBE"
	_backend.next_text = reply
	_svc.add_child(_backend)
	_svc._backends.clear()
	_svc._backends.append(_backend)
	_backend.request_finished.connect(_svc._on_backend_finished)
	_svc._active_backend = _backend


func _restore_backend() -> void:
	if _backend == null or not is_instance_valid(_backend):
		return
	_backend.request_finished.disconnect(_svc._on_backend_finished)
	_svc.remove_child(_backend)
	_backend.free()
	_backend = null
	_svc._backends.clear()
	for b in _orig_backends:
		_svc._backends.append(b)
	_svc._active_backend = _orig_active
	_svc.llm_enabled = _orig_enabled


func _live_party(jobs: Array) -> void:
	var script := GDScript.new()
	script.source_code = STUB_GAMELOOP
	script.reload()
	_stub = Node.new()
	_stub.set_script(script)
	_stub.name = "GameLoop"
	var members: Array = []
	for j in jobs:
		var c: Combatant = Combatant.new()
		add_child_autofree(c)
		c.combatant_name = str(j).capitalize()
		c.job = JobSystem.get_job(str(j))
		c.job_level = 1
		members.append(c)
	_stub.party = members
	get_tree().root.add_child(_stub)


func test_a_real_composition_reaches_the_repair() -> void:
	## Every arm above calls the helper by hand, so all seventeen stay green if
	## compose_async stops calling it — which is the defect, in the half that produced it.
	var rc = get_tree().root.get_node_or_null("RuleComposer")
	assert_not_null(rc, "CONTROL: RuleComposer autoload must exist")
	_live_party(["fighter", "cleric"])
	_replay(JSON.stringify({"name": "n", "description": "d",
		"rules_json": JSON.stringify([_rule("everyone")])}))
	var res: Dictionary = await rc.compose_async("autogrind", "switch everyone to defensive", "", [])
	_restore_backend()
	assert_eq(str(res.get("source", "")), "llm",
		"the composition must survive: %s" % str(res.get("errors", [])))
	assert_eq(_switch_ids(res.get("rules", [])), ["fighter", "cleric"],
		"and the party word must have been expanded on the real path")
	assert_false(AutobattleSystem.character_profiles.has("everyone"),
		"and no phantom may have been created on the way")
