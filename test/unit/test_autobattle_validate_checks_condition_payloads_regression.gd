extends GutTest

## The autobattle validator checked a condition's TYPE and, for weather alone, its VALUE. Six other
## conditions carry a payload field naming the SUBJECT of the test, and none of them was checked:
##
##   has_status / ally_has_status / enemy_has_status   "status"
##   item_count                                        "item_id"
##   has_buff / not_has_buff                           "stat"
##
## Absence never fails loudly. The evaluator defaults each to "" and compares against it, so the
## rule validates clean and then behaves as a constant:
##
##   has_status with no status     -> "" is in no status list        PERMANENTLY FALSE
##   item_count with no item_id    -> _get_item_count(c, "") == 0    PERMANENTLY FALSE
##   has_buff with no stat         -> no buff has stat ""            PERMANENTLY FALSE
##   not_has_buff with no stat     -> no buff has stat ""            PERMANENTLY TRUE
##
## The last is the dangerous one and it is not merely a dead rule: rules are FIRST-MATCH-WINS, so an
## always-true condition makes every rule below it unreachable. One missing word silently disables
## the rest of the script, and nothing anywhere reports it.
##
## Sibling of the autogrind payload validator (same gap, the grammar players use most).

const AB := "res://src/autobattle/AutobattleSystem.gd"


func _rule(cond: Dictionary) -> Dictionary:
	return {"conditions": [cond], "actions": [{"type": "attack", "target": "lowest_hp_enemy"}], "enabled": true}


func test_every_condition_is_classified_for_payload_checking() -> void:
	var classified: Array = []
	classified.append_array(AutobattleSystem.CONDITION_REQUIRED_FIELD.keys())
	classified.append_array(AutobattleSystem.CONDITION_NO_PAYLOAD)
	var registry: Array = AutobattleSystem.CONDITION_TYPES.keys()
	assert_gt(registry.size(), 0, "control: the grammar must be non-empty")

	var unclassified: Array = []
	for t in registry:
		if not classified.has(str(t)):
			unclassified.append(str(t))
	assert_eq(unclassified.size(), 0,
		"these conditions are validated for TYPE but their payload is never examined: %s" % str(unclassified))

	var stale: Array = []
	for t in classified:
		if not registry.has(str(t)):
			stale.append(str(t))
	assert_eq(stale.size(), 0,
		"these are classified for payload checking but are not conditions any more: %s" % str(stale))


func test_a_status_condition_without_a_status_is_rejected() -> void:
	for t in ["has_status", "ally_has_status", "enemy_has_status"]:
		var errors: Array = AutobattleSystem.validate_rule(_rule({"type": t}))
		assert_gt(errors.size(), 0, "'%s' with no status can never match and must not validate" % t)
		assert_true("\n".join(PackedStringArray(errors)).contains("status"),
			"the error must name the missing field: %s" % str(errors))


func test_an_item_condition_without_an_item_id_is_rejected() -> void:
	var errors: Array = AutobattleSystem.validate_rule(
		_rule({"type": "item_count", "op": ">", "value": 0}))
	assert_gt(errors.size(), 0,
		"item_count with no item_id counts the empty-string item — always 0, never fires")


func test_not_has_buff_without_a_stat_is_rejected_because_it_matches_ALWAYS() -> void:
	## The severe case. This one does not go quiet — it goes permanently TRUE and, under
	## first-match-wins, every rule below it becomes unreachable.
	var errors: Array = AutobattleSystem.validate_rule(_rule({"type": "not_has_buff"}))
	assert_gt(errors.size(), 0,
		"not_has_buff with no stat is ALWAYS true and hides every rule beneath it")


func test_the_correct_shapes_still_validate() -> void:
	## ARM+ against over-rejecting. Each of the seven, properly filled in.
	var good: Array = [
		{"type": "has_status", "status": "poison"},
		{"type": "ally_has_status", "status": "poison"},
		{"type": "enemy_has_status", "status": "blind"},
		{"type": "item_count", "item_id": "potion", "op": ">", "value": 0},
		{"type": "has_buff", "stat": "defense"},
		{"type": "not_has_buff", "stat": "defense"},
	]
	for c in good:
		var errors: Array = AutobattleSystem.validate_rule(_rule(c))
		assert_eq(errors.size(), 0,
			"a properly formed '%s' must validate: %s" % [str(c.get("type")), str(errors)])


func test_payload_free_conditions_are_not_asked_for_one() -> void:
	for t in ["hp_percent", "turn", "ally_count", "always", "is_night", "setup_complete"]:
		var errors: Array = AutobattleSystem.validate_rule(_rule({"type": t, "op": "<", "value": 30}))
		assert_eq(errors.size(), 0, "'%s' carries no payload and must validate bare: %s" % [t, str(errors)])


func test_every_shipped_template_rule_still_validates() -> void:
	## Tightening a validator is how authoring breaks for everyone at once. The catalog players
	## actually load must pass unchanged, and the count proves the sweep ran.
	var f := FileAccess.open("res://data/autobattle_rule_templates.json", FileAccess.READ)
	assert_true(f != null, "control: the shipped catalog must be readable")
	var data: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()
	var checked := 0
	for tmpl in data.get("templates", []):
		for r in (tmpl as Dictionary).get("rules", []):
			checked += 1
			var errors: Array = AutobattleSystem.validate_rule(r)
			assert_eq(errors.size(), 0,
				"shipped template '%s' rule must still validate: %s" % [str(tmpl.get("id")), str(errors)])
	assert_gt(checked, 0, "the sweep must have validated rules — zero checked is not a clean bill of health")
