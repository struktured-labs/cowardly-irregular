extends GutTest

## tick 132 regression: AbilitiesMenu._get_ability_data must consult
## JobSystem (data/abilities.json) before falling back to the
## synthesized stub. Pre-fix this menu rendered EVERY learned
## ability as generic "physical" type / "A combat ability" desc /
## prettified id — the type-color, the description label, and the
## displayed name were all silently wrong for every magic/support
## ability the player learned.
##
## The fix path: JobSystem.get_ability(id) → fall back to stub.
## Stub preserved for ids that don't resolve in abilities.json
## (Scriptweaver custom ids, save-format drift, debug paths).

const ABILITIES_MENU := "res://src/ui/AbilitiesMenu.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func _get_ability_data_body() -> String:
	var src := _read(ABILITIES_MENU)
	var idx: int = src.find("func _get_ability_data")
	assert_gt(idx, -1, "_get_ability_data must exist")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	return src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)


func test_consults_job_system_first() -> void:
	# Pin: lookup must happen via JobSystem.get_ability(id).
	var body := _get_ability_data_body()
	assert_true(body.contains("JobSystem.get_ability(ability_id)"),
		"_get_ability_data must call JobSystem.get_ability(ability_id) — without it, every ability shows as 'physical / A combat ability' regardless of its real type")
	assert_true(body.contains("JobSystem.has_method(\"get_ability\")"),
		"must guard on has_method — JobSystem could be missing in headless test contexts")


func test_returns_real_data_when_resolved() -> void:
	# Pin: when JobSystem returns non-empty data, that data is
	# returned verbatim — NOT merged with the stub. The stub's
	# defaults would shadow real fields.
	var body := _get_ability_data_body()
	assert_true(body.contains("if not data.is_empty():\n\t\t\treturn data"),
		"non-empty JobSystem result must be returned as-is; merging with the stub would shadow real fields")


func test_stub_fallback_preserved() -> void:
	# Pin: stub still present for unknown ids (Scriptweaver, drift).
	var body := _get_ability_data_body()
	for key in ["\"id\": ability_id,", "\"type\": \"physical\",", "\"description\": \"A combat ability\",", "\"mp_cost\": 0"]:
		assert_true(body.contains(key),
			"stub field '%s' must remain — unknown ids still need a graceful fallback" % key)
	assert_true(body.contains("ability_id.replace(\"_\", \" \").capitalize()"),
		"stub name fallback (prettifier) preserved for unknown ids")


func test_old_dead_comment_about_root_ability_system_removed() -> void:
	# Negative pin: the misleading comment that AbilitySystem "was
	# never registered" is gone — JobSystem IS the registered system
	# for abilities, so the old comment was actively wrong.
	var body := _get_ability_data_body()
	assert_false(body.contains("/root/AbilitySystem"),
		"old comment about /root/AbilitySystem must be gone — JobSystem is the registered ability source")


func test_runtime_resolves_known_ability_via_job_system() -> void:
	# Runtime check: a known ability id from data/abilities.json
	# should resolve to its canonical fields, not the stub.
	var script_class = load(ABILITIES_MENU)
	var inst: Node = script_class.new()
	add_child_autofree(inst)
	# power_strike exists in data/abilities.json (first entry).
	var data: Dictionary = inst._get_ability_data("power_strike")
	assert_eq(str(data.get("name", "")), "Power Strike",
		"power_strike must resolve to canonical 'Power Strike' name from abilities.json, not the prettified stub 'Power strike'")
	assert_eq(str(data.get("type", "")), "physical",
		"power_strike type must come from JSON — happens to match stub default, but should still be JSON-sourced")
	# mp_cost is the smoking gun: stub returns 0, JSON returns 8.
	assert_eq(int(data.get("mp_cost", -1)), 8,
		"power_strike mp_cost must be 8 from abilities.json, NOT 0 from the stub — stub would mask real MP requirements in the menu")


func test_runtime_falls_back_to_stub_for_unknown_id() -> void:
	var script_class = load(ABILITIES_MENU)
	var inst: Node = script_class.new()
	add_child_autofree(inst)
	var data: Dictionary = inst._get_ability_data("definitely_not_a_real_ability_xyz")
	assert_eq(str(data.get("description", "")), "A combat ability",
		"unknown id must fall back to stub description")
	assert_eq(int(data.get("mp_cost", -1)), 0,
		"unknown id must fall back to stub mp_cost = 0")
	# Prettifier should produce title-case ("Definitely Not A Real Ability Xyz").
	assert_true(str(data.get("name", "")).begins_with("Definitely Not"),
		"unknown id must prettify the raw id, not return empty")
