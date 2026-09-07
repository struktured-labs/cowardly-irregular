extends GutTest

## tick 136 regression: PartyStatusScreen's abilities + passives
## lists must consult JobSystem / PassiveSystem for canonical
## names instead of just prettifying the raw id. Pre-fix every
## ability/passive in the party menu rendered through
## `replace+capitalize` — "Power strike" instead of "Power Strike"
## from data/abilities.json, and identical issue for passives.
##
## High-visibility surface: party status menu opens multiple
## times per session (gear check, stat check, formation pick).

const PARTY_STATUS := "res://src/ui/PartyStatusScreen.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func _resolver_body(name: String) -> String:
	var src := _read(PARTY_STATUS)
	var idx: int = src.find("func " + name)
	assert_gt(idx, -1, "%s must exist" % name)
	var next_fn: int = src.find("\nfunc ", idx + 1)
	return src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)


func test_abilities_loop_uses_resolver() -> void:
	var src := _read(PARTY_STATUS)
	# The abilities loop must use _resolve_ability_name, not raw
	# _format_id which only prettifies.
	assert_true(src.contains("_resolve_ability_name(str(ability_id))"),
		"abilities loop must call _resolve_ability_name (canonical from JobSystem)")
	# Negative pin: the old `_format_id(str(ability_id))` must be gone
	# from the abilities iteration (the helper still exists as the
	# fallback inside resolvers, but its direct use on ability_id
	# was the bug).
	assert_false(src.contains("\"• \" + _format_id(str(ability_id))"),
		"old direct prettifier path for abilities must be gone")


func test_passives_loop_uses_resolver() -> void:
	var src := _read(PARTY_STATUS)
	assert_true(src.contains("_resolve_passive_name(str(passive_id))"),
		"passives loop must call _resolve_passive_name (canonical from PassiveSystem)")
	assert_false(src.contains("\"◦ \" + _format_id(str(passive_id))"),
		"old direct prettifier path for passives must be gone")


func test_ability_resolver_prefers_job_system() -> void:
	var body := _resolver_body("_resolve_ability_name")
	assert_true(body.contains("get_node_or_null(\"/root/JobSystem\")"),
		"ability resolver must look up JobSystem")
	assert_true(body.contains("js.has_method(\"get_ability\")"),
		"ability resolver must guard has_method")
	assert_true(body.contains("js.get_ability(ability_id)"),
		"ability resolver must call get_ability")
	assert_true(body.contains("data.has(\"name\")"),
		"ability resolver must guard has('name')")


func test_passive_resolver_prefers_passive_system() -> void:
	var body := _resolver_body("_resolve_passive_name")
	assert_true(body.contains("get_node_or_null(\"/root/PassiveSystem\")"),
		"passive resolver must look up PassiveSystem")
	assert_true(body.contains("ps.has_method(\"get_passive\")"),
		"passive resolver must guard has_method")
	assert_true(body.contains("ps.get_passive(passive_id)"),
		"passive resolver must call get_passive")


func test_both_resolvers_fall_back_to_format_id() -> void:
	# Pin: prettifier remains as the fallback. _format_id is the
	# helper from before — both new resolvers call it on miss.
	var ability_body := _resolver_body("_resolve_ability_name")
	var passive_body := _resolver_body("_resolve_passive_name")
	assert_true(ability_body.contains("return _format_id(ability_id)"),
		"ability resolver fallback must call _format_id")
	assert_true(passive_body.contains("return _format_id(passive_id)"),
		"passive resolver fallback must call _format_id")


func test_resolvers_short_circuit_on_empty_id() -> void:
	var ability_body := _resolver_body("_resolve_ability_name")
	var passive_body := _resolver_body("_resolve_passive_name")
	assert_true(ability_body.contains("if ability_id == \"\":\n\t\treturn \"\""),
		"empty ability_id must short-circuit")
	assert_true(passive_body.contains("if passive_id == \"\":\n\t\treturn \"\""),
		"empty passive_id must short-circuit")


func test_format_id_helper_preserved_for_fallback_paths() -> void:
	# Negative pin: don't accidentally delete _format_id — both
	# resolvers depend on it, and _resolve_equipment_fallback
	# in this file also calls it.
	var src := _read(PARTY_STATUS)
	assert_true(src.contains("func _format_id(id: String) -> String:"),
		"_format_id helper must remain — resolvers and equipment fallback rely on it")
