extends GutTest

## Regression coverage for the autogrind rule-templates catalog + installer.
## Two responsibilities pinned here:
##   1) Every catalog rule uses condition/action types the evaluator supports.
##      Drift here would let a template install a rule that silently never fires.
##   2) install_as_new_profile leaves the previously-active profile active, so
##      accepting a template can't accidentally hijack the player's current setup.

const AutogrindRuleTemplatesScript = preload("res://src/autogrind/AutogrindRuleTemplates.gd")


class FakeAutogrindSystem extends RefCounted:
	var profiles: Array = []
	var active_index: int = 0
	var rules_writes: Array = []
	var max_profiles: int = 8

	func create_new_autogrind_profile(name: String) -> int:
		if profiles.size() >= max_profiles:
			return -1
		profiles.append({"name": name, "rules": []})
		return profiles.size() - 1

	func get_active_autogrind_profile_index() -> int:
		return active_index

	func set_active_autogrind_profile(idx: int) -> void:
		active_index = idx

	func set_autogrind_rules(rules: Array) -> void:
		# Mirror the real AutogrindSystem contract — write into the active profile.
		rules_writes.append({"target_profile": active_index, "rules": rules.duplicate(true)})
		if active_index < profiles.size():
			profiles[active_index]["rules"] = rules.duplicate(true)


func before_each() -> void:
	AutogrindRuleTemplatesScript._reset_cache_for_test()


func test_catalog_loads_at_least_three_templates() -> void:
	var cat = AutogrindRuleTemplatesScript.catalog()
	assert_gte(cat.size(), 3,
		"Task ships Safe Grind + EXP Rush + Gold Farm — three at minimum")


func test_catalog_ids_are_unique() -> void:
	var seen := {}
	for t in AutogrindRuleTemplatesScript.catalog():
		var id: String = t.get("id", "")
		assert_false(seen.has(id), "Duplicate template id: %s" % id)
		seen[id] = true


func test_shipping_templates_present_by_id() -> void:
	# The three ids called out in the task should be findable by id.
	for id in ["template_safe_grind", "template_exp_rush", "template_gold_farm"]:
		assert_false(AutogrindRuleTemplatesScript.find(id).is_empty(),
			"Template '%s' should be in the catalog" % id)


func test_find_unknown_returns_empty() -> void:
	assert_eq(AutogrindRuleTemplatesScript.find("template_does_not_exist"), {})


func test_every_template_rule_uses_supported_condition_types() -> void:
	# Drift guard: any condition type here that isn't in _evaluate_party_condition's
	# match arms would silently no-op — the rule would look installed but never fire.
	var supported := [
		"party_hp_avg", "party_mp_avg", "party_hp_min", "alive_count",
		"battles_done", "corruption", "efficiency", "member_dead",
		"member_injured", "win_streak", "time_elapsed", "inventory_items",
		"ability_learned", "reached_level", "rare_item_found", "always"
	]
	for t in AutogrindRuleTemplatesScript.catalog():
		for rule in t.get("rules", []):
			for cond in rule.get("conditions", []):
				var ct: String = cond.get("type", "")
				assert_true(ct in supported,
					"Template '%s' references unsupported condition type '%s'" % [t["id"], ct])


func test_every_template_rule_uses_supported_action_types() -> void:
	var supported := ["switch_profile", "stop_grinding", "heal_party", "restore_mp", "flee_battle"]
	for t in AutogrindRuleTemplatesScript.catalog():
		for rule in t.get("rules", []):
			for action in rule.get("actions", []):
				var at: String = action.get("type", "")
				assert_true(at in supported,
					"Template '%s' references unsupported action type '%s'" % [t["id"], at])


func test_install_writes_rules_to_new_profile() -> void:
	var fake := FakeAutogrindSystem.new()
	var idx := AutogrindRuleTemplatesScript.install_as_new_profile("template_safe_grind", fake)
	assert_gte(idx, 0, "Install must return a non-negative profile index on success")
	assert_eq(fake.profiles[idx]["name"], "Safe Grind",
		"Installed profile must use the template's name")
	assert_gt((fake.profiles[idx]["rules"] as Array).size(), 0,
		"Installed profile must have the template's rules written into it")


func test_install_preserves_active_profile() -> void:
	# CRITICAL: accepting a template must NOT switch to it — the user's current
	# active profile stays the active one. The install temporarily flips active
	# to write, then flips back.
	var fake := FakeAutogrindSystem.new()
	fake.profiles = [{"name": "Existing", "rules": []}]
	fake.active_index = 0
	AutogrindRuleTemplatesScript.install_as_new_profile("template_exp_rush", fake)
	assert_eq(fake.active_index, 0,
		"install_as_new_profile must leave the previously-active profile active — otherwise picking a template would hijack the player's current setup")


func test_install_returns_negative_when_at_max_profiles() -> void:
	var fake := FakeAutogrindSystem.new()
	for i in range(fake.max_profiles):
		fake.profiles.append({"name": "P%d" % i, "rules": []})
	var idx := AutogrindRuleTemplatesScript.install_as_new_profile("template_gold_farm", fake)
	assert_eq(idx, -1,
		"When AutogrindSystem is at MAX_AUTOGRIND_PROFILES, install must fail with -1 — not overflow the profile array")


func test_install_returns_negative_for_unknown_template() -> void:
	var fake := FakeAutogrindSystem.new()
	var idx := AutogrindRuleTemplatesScript.install_as_new_profile("template_not_a_thing", fake)
	assert_eq(idx, -1)
	assert_eq(fake.profiles.size(), 0,
		"Unknown template id must not create any profile as a side effect")


func test_install_survives_null_autogrind_system() -> void:
	var idx := AutogrindRuleTemplatesScript.install_as_new_profile("template_safe_grind", null)
	assert_eq(idx, -1,
		"Passing null as the autogrind system must return -1, not crash")


func test_safe_grind_has_hp_stop_rule() -> void:
	# The task's exact-word promise for Safe Grind is "stop at 30% HP".
	# Pin the semantic contract — if someone raises the threshold to 40%, that's
	# a design decision worth surfacing here, not silently accepting.
	var t := AutogrindRuleTemplatesScript.find("template_safe_grind")
	var found_hp_stop := false
	for rule in t.get("rules", []):
		var conds: Array = rule.get("conditions", [])
		var acts: Array = rule.get("actions", [])
		for c in conds:
			if c.get("type", "") == "party_hp_min" and float(c.get("value", 0)) <= 30.0:
				for a in acts:
					if a.get("type", "") == "stop_grinding":
						found_hp_stop = true
	assert_true(found_hp_stop,
		"Safe Grind must have a party_hp_min<=30 → stop_grinding rule (task-#6 contract)")


func test_gold_farm_has_inventory_stop_rule() -> void:
	# Same as above — Gold Farm's "stop when inventory full" is task-guaranteed.
	var t := AutogrindRuleTemplatesScript.find("template_gold_farm")
	var found_inv_stop := false
	for rule in t.get("rules", []):
		var conds: Array = rule.get("conditions", [])
		var acts: Array = rule.get("actions", [])
		for c in conds:
			if c.get("type", "") == "inventory_items":
				for a in acts:
					if a.get("type", "") == "stop_grinding":
						found_inv_stop = true
	assert_true(found_inv_stop,
		"Gold Farm must have an inventory_items → stop_grinding rule (task-#6 contract)")
