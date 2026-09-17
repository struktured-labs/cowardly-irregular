extends GutTest

## An autobattle `item` action's id is DEEP-CHECKED — `ItemSystem.get_item(iid).is_empty()`
## appends "unknown item", and one grammar error makes compose_async return the canned
## draft. So a singular/plural slip costs the player every rule they asked for.
##
## The grammar named exactly one item ("potion") and no statuses beyond one example.
##
## MEASURED on live llama3 2026-09-17, 20 samples per arm, 0 malformed in any:
##
##     intent "cure blindness with eye drops, use echo herbs the moment someone is
##      silenced, and bring back anyone who falls"
##         item action ids      19 of 20 unknown   echo_herb 14 · echo 5
##         status conditions     7 of 19 unmatchable   silenced 7
##     after the vocabularies
##         item action ids       0 of 24
##         status conditions     6 of 25, every one a spelling the repair maps
##
## ⚠️ AN EARLIER RUN OF THE SAME PROBE SCORED 0 OF 19 AND WAS WORTHLESS: its intent asked
## for `potion` and `poison`, which are the grammar's own examples. The measurement could
## not fail, and it read as evidence the prompt was fine. The corpus was the defect.

const RC := preload("res://src/llm/RuleComposer.gd")
const DP := preload("res://src/llm/DialoguePrompts.gd")


func _rc():
	var c = RC.new()
	if c is Node:
		add_child_autofree(c)
	return c


func _ctx(items: Array = []) -> Dictionary:
	return {"resolved": true, "job_id": "cleric", "kit": ["cure"], "full_kit": ["cure"],
		"max_mp": 70, "costs": {"cure": 6}, "items": items}


func _item_rule(iid: String) -> Dictionary:
	return {"conditions": [{"type": "always"}],
		"actions": [{"type": "item", "id": iid, "target": "lowest_hp_ally"}], "enabled": true}


func _status_rule(ctype: String, status: String) -> Dictionary:
	return {"conditions": [{"type": ctype, "status": status}],
		"actions": [{"type": "attack"}], "enabled": true}


func _item_ids(rules: Array) -> Array:
	var out: Array = []
	for r in rules:
		for a in r.get("actions", []):
			if str(a.get("type", "")) == "item":
				out.append(str(a.get("id", "")))
	return out


func _status_values(rules: Array) -> Array:
	var out: Array = []
	for r in rules:
		for c in r.get("conditions", []):
			if c.has("status"):
				out.append(str(c["status"]))
	return out


# ── the item defect ───────────────────────────────────────────────────────────

func test_a_singular_plural_slip_is_read_as_the_real_id() -> void:
	## THE ARM. `echo_herb` was 14 of 20, and each one discarded a whole composition.
	var rules: Array = [_item_rule("echo_herb")]
	var notes: Array = _rc()._normalise_item_ids(rules, ["echo_herbs", "eye_drops", "potion"])
	assert_eq(_item_ids(rules), ["echo_herbs"], "the real id, so the deep check passes")
	assert_gt(notes.size(), 0, "and the player is told what it was read as")


func test_the_fold_covers_separators_and_case_too() -> void:
	## One defined rewrite — lowercase, drop separators, optional trailing s — rather than
	## a list of observed misspellings, which would only ever cover what has been seen.
	for wrong in ["Eye_Drops", "eyedrops", "eye-drop", "EYEDROP"]:
		var rules: Array = [_item_rule(wrong)]
		_rc()._normalise_item_ids(rules, ["eye_drops", "potion"])
		assert_eq(_item_ids(rules), ["eye_drops"], "'%s' folds to the real id" % wrong)


func test_an_item_count_condition_is_repaired_the_same_way() -> void:
	## item_count's item_id is NOT deep-checked — the grammar says an absent one counts 0,
	## and a wrong one does the same silently. Different consequence, same repair.
	var rules: Array = [{"conditions": [{"type": "item_count", "item_id": "antidotes",
		"op": ">", "value": 0}], "actions": [{"type": "attack"}], "enabled": true}]
	_rc()._normalise_item_ids(rules, ["antidote", "potion"])
	assert_eq(rules[0]["conditions"][0]["item_id"], "antidote", "the count must reach a real item")


# ── it must not invent ────────────────────────────────────────────────────────

func test_a_word_that_folds_to_nothing_is_left_for_the_deep_check() -> void:
	## `echo` was 5 of 20 and folds to nothing — the repair must not reach for the nearest
	## id. Leaving it means the deep check refuses the rule, which is the honest outcome.
	var rules: Array = [_item_rule("echo")]
	var notes: Array = _rc()._normalise_item_ids(rules, ["echo_herbs", "eye_drops"])
	assert_eq(_item_ids(rules), ["echo"], "an id that folds to nothing is not guessed at")
	assert_eq(notes, [], "and no repair is claimed")


func test_an_ambiguous_fold_is_refused() -> void:
	## If two REAL ids collapse to one key, picking either is a guess. Synthetic here
	## because no such pair exists today — and that is exactly why it needs an arm.
	var rules: Array = [_item_rule("tonic")]
	var notes: Array = _rc()._normalise_item_ids(rules, ["tonic", "tonics"])
	assert_eq(_item_ids(rules), ["tonic"], "CONTROL: an exact id is never touched")
	var rules2: Array = [_item_rule("Tonics")]
	_rc()._normalise_item_ids(rules2, ["tonic", "tonics"])
	assert_eq(_item_ids(rules2), ["Tonics"], "an ambiguous fold must be left alone")
	assert_eq(notes, [], "and nothing claimed for the exact one either")


func test_a_correct_id_produces_no_note() -> void:
	var rules: Array = [_item_rule("potion")]
	var notes: Array = _rc()._normalise_item_ids(rules, ["potion", "echo_herbs"])
	assert_eq(_item_ids(rules), ["potion"], "untouched")
	assert_eq(notes, [], "the notes panel says what CHANGED; a note here would be a lie")


func test_with_no_item_list_nothing_is_touched() -> void:
	## Unable to verify is not verified absent — the same rule as the party repairs.
	var rules: Array = [_item_rule("echo_herb")]
	var notes: Array = _rc()._normalise_item_ids(rules, [])
	assert_eq(_item_ids(rules), ["echo_herb"], "no vocabulary means no authority to rewrite")
	assert_eq(notes, [], "and nothing claimed")


# ── the status half, same table as the grind's ────────────────────────────────

func test_an_english_participle_in_a_status_condition_is_mapped() -> void:
	var rules: Array = [_status_rule("ally_has_status", "silenced")]
	var notes: Array = _rc()._normalise_autobattle_statuses(rules)
	assert_eq(_status_values(rules), ["silence"], "silenced is silence")
	assert_gt(notes.size(), 0, "and it is reported")


func test_every_status_condition_type_is_covered() -> void:
	## Five condition types carry a status and the model uses whichever fits its sentence.
	## Repairing only `has_status` would look right and leave four types broken.
	for ctype in ["has_status", "not_has_status", "ally_has_status", "enemy_has_status",
			"not_enemy_has_status"]:
		var rules: Array = [_status_rule(ctype, "blinded")]
		_rc()._normalise_autobattle_statuses(rules)
		assert_eq(_status_values(rules), ["blind"], "%s must be repaired too" % ctype)


func test_a_correct_status_and_an_unknown_one_are_both_left_alone() -> void:
	var rules: Array = [_status_rule("has_status", "poison"), _status_rule("has_status", "bamboozled")]
	var notes: Array = _rc()._normalise_autobattle_statuses(rules)
	assert_eq(_status_values(rules), ["poison", "bamboozled"], "neither is rewritten")
	assert_eq(notes, [], "and nothing is claimed for either")


# ── the prompt half ───────────────────────────────────────────────────────────

func test_the_autobattle_prompt_names_the_item_ids() -> void:
	var p: String = DP.build_rule_composition("autobattle", "use items", [],
		_ctx(["antidote", "echo_herbs", "potion"]))
	var at: int = p.find("ITEM IDS")
	assert_gt(at, -1, "the model must be told which item ids exist")
	for iid in ["antidote", "echo_herbs", "potion"]:
		assert_true(p.substr(at).find(iid) != -1, "it must name %s" % iid)


func test_the_item_list_comes_from_the_context_not_from_a_list_here() -> void:
	var p: String = DP.build_rule_composition("autobattle", "use items", [], _ctx(["repel"]))
	var at: int = p.find("ITEM IDS")
	assert_gt(at, -1, "CONTROL: the block must render")
	assert_true(p.substr(at).find("repel") != -1, "the context's own ids")
	assert_true(p.substr(at).find("echo_herbs") == -1, "and only those")


func test_no_item_list_renders_no_item_block() -> void:
	## Headless and any caller that cannot resolve ItemSystem. A heading with nothing
	## under it is a promise of a list, which is the defect this branch exists to remove.
	var p: String = DP.build_rule_composition("autobattle", "use items", [], _ctx([]))
	assert_true(p.find("ITEM IDS") == -1, "an empty list must render no heading")


func test_the_autobattle_prompt_names_the_status_ids() -> void:
	var p: String = DP.build_rule_composition("autobattle", "cure things", [], _ctx(["potion"]))
	var at: int = p.find("STATUS IDS")
	assert_gt(at, -1, "the status vocabulary must reach the per-character prompt too")
	for sid in DP.STATUS_VOCABULARY.keys():
		assert_true(p.substr(at).find("%s   for " % str(sid)) != -1, "it must name %s" % sid)


func test_the_grind_prompt_does_not_get_the_item_block() -> void:
	## CONTROL: no autogrind action names an item — heal_party spends potions by itself.
	## A vocabulary offered where the grammar has no slot for it is noise.
	var p: String = DP.build_rule_composition("autogrind", "grind safely", [],
		{"resolved": true, "party": [{"member": "cleric", "job_id": "cleric",
		"kit": ["cure"], "costs": {"cure": 6}, "profiles": ["Default"]}]})
	assert_true(p.find("ITEM IDS") == -1, "the grind grammar has no item slot")


# ── the repairs must be WIRED, which no arm above can tell you ────────────────

var _svc = null
var _backend = null
var _orig_backends: Array = []
var _orig_active = null
var _orig_enabled: bool = true


func after_each() -> void:
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


func test_a_near_miss_no_longer_discards_the_composition() -> void:
	## THE CONSEQUENCE ARM. Every arm above calls a helper by hand, so all fifteen stay
	## green if compose_async stops calling them — which is the defect. This drives the
	## real path and asks whether the player's ruleset survived.
	var rc = get_tree().root.get_node_or_null("RuleComposer")
	assert_not_null(rc, "CONTROL: RuleComposer autoload must exist")
	var rules: Array = [
		{"conditions": [{"type": "ally_has_status", "status": "silenced"}],
		"actions": [{"type": "item", "id": "echo_herb", "target": "lowest_hp_ally"}],
		"enabled": true}]
	_replay(JSON.stringify({"name": "n", "description": "d", "rules_json": JSON.stringify(rules)}))
	var res: Dictionary = await rc.compose_async("autobattle", "echo herbs when silenced", "cleric", [])
	assert_eq(str(res.get("source", "")), "llm",
		"the composition must survive the deep check: %s" % str(res.get("errors", [])))
	assert_eq(_item_ids(res.get("rules", [])), ["echo_herbs"], "the item id repaired on the real path")
	assert_eq(_status_values(res.get("rules", [])), ["silence"], "and the status with it")


func test_the_composer_gathers_battle_items_and_not_key_items() -> void:
	## The vocabulary is derived from ItemSystem, and META is 146 of the 172 — key items
	## and equipment, which an `item` action cannot use. Offering them would be a list the
	## deep check accepts and the battle cannot run.
	var ids: Array = _rc()._battle_item_ids()
	assert_gt(ids.size(), 10, "CONTROL: the battle categories must resolve")
	assert_true(ids.has("potion"), "a consumable must be offered")
	assert_true(ids.has("echo_herbs"), "and a curative")
	for iid in ids:
		assert_ne(int(ItemSystem.get_item(str(iid)).get("category", -1)), 4,
			"%s is a META item and must not be offered" % iid)
