extends GutTest

## An ability whose effect has no arm burns its MP and does nothing (2026-08-06).
##
## Third instance of one shape: tick 351 found Bard songs fizzling, tick 392 found the
## Summoner's four eidolons fizzling, and tick 406 implemented copy_last_ability — into
## _execute_meta_ability's `match meta_effect:`. But mimic_ability authors type=support
## and effect=copy_last_ability, and routing is BY TYPE, so it lands in
## _execute_support_ability and falls to the `_:` push_warning. The fix existed and the
## ability could not reach it. That default arm's own comment still listed
## copy_last_ability as unimplemented, which is how the gap stayed visible and unclosed.
##
## So this guard enumerates by CAPABILITY — every ability the type-dispatch routes to the
## support handler — rather than by a list of effect names someone maintains by hand.

const BM_PATH := "res://src/battle/BattleManager.gd"


func _src() -> String:
	return FileAccess.get_file_as_string(BM_PATH)


## The arm labels of `match <name>:` inside the given function, by indentation.
func _match_arms(src: String, func_name: String, match_on: String) -> Array[String]:
	var arms: Array[String] = []
	var fn_idx: int = src.find("func " + func_name)
	if fn_idx == -1:
		return arms
	var lines: PackedStringArray = src.substr(fn_idx).split("\n")
	var base: int = -1
	for i in range(lines.size()):
		var line: String = lines[i]
		if line.strip_edges() == "match %s:" % match_on:
			base = line.length() - line.lstrip("\t").length()
			continue
		if base == -1:
			continue
		if line.strip_edges() == "" or line.strip_edges().begins_with("#"):
			continue
		var indent: int = line.length() - line.lstrip("\t").length()
		if indent <= base:
			break
		if indent == base + 1 and line.strip_edges().ends_with(":"):
			for m in RegEx.create_from_string('"([^"]+)"').search_all(line):
				arms.append(m.get_string(1))
	return arms


## Ability types the dispatch routes to _execute_support_ability — read, not hardcoded.
func _support_routed_types(src: String) -> Array[String]:
	var types: Array[String] = []
	var call_idx: int = src.find("_execute_support_ability(caster, ability, retargeted)")
	if call_idx == -1:
		return types
	var head: PackedStringArray = src.substr(0, call_idx).split("\n")
	for i in range(head.size() - 1, -1, -1):
		var line: String = head[i]
		if line.strip_edges().ends_with(":") and line.contains("\""):
			for m in RegEx.create_from_string('"([^"]+)"').search_all(line):
				types.append(m.get_string(1))
			break
	return types


func _abilities() -> Dictionary:
	var f := FileAccess.open("res://data/abilities.json", FileAccess.READ)
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Dictionary else {}


# ── the parser must work, or every result below is vacuous ────────────

func test_the_parser_finds_real_arms_and_rejects_a_fabricated_one() -> void:
	var arms := _match_arms(_src(), "_execute_support_ability", "effect")
	assert_gt(arms.size(), 20,
		"the support match must yield many arms — a small number means the parse broke")
	assert_true(arms.has("copy_last_ability"),
		"a KNOWN-present arm must be found (this is the one the fix added)")
	assert_false(arms.has("zzz_not_a_real_effect"),
		"and a fabricated arm must NOT be found, or membership means nothing")


func test_the_routed_types_are_read_from_the_dispatch() -> void:
	var types := _support_routed_types(_src())
	assert_true(types.has("support"),
		"the type-dispatch arm calling _execute_support_ability must include 'support'")
	assert_false(types.has("magic"),
		"'magic' routes elsewhere — if it appears here the arm walk-back grabbed the wrong line")


# ── the class guard ───────────────────────────────────────────────────

func test_every_support_routed_ability_effect_has_an_arm() -> void:
	var src := _src()
	var arms := _match_arms(src, "_execute_support_ability", "effect")
	var routed := _support_routed_types(src)
	assert_gt(arms.size(), 0, "guard is vacuous without arms")
	assert_gt(routed.size(), 0, "guard is vacuous without routed types")

	var orphans: Array[String] = []
	for id in _abilities().keys():
		var a: Dictionary = _abilities()[id]
		var effect := str(a.get("effect", ""))
		if effect == "" or not routed.has(str(a.get("type", ""))):
			continue
		if not arms.has(effect):
			orphans.append("%s (effect=%s)" % [id, effect])
	assert_eq(orphans, [] as Array[String],
		"these route to _execute_support_ability but their effect has no arm — the cast " +
		"burns MP and hits the `_:` push_warning: %s" % [orphans])


# ── the behaviour the fix restored ────────────────────────────────────

func _bm() -> Node:
	var bm: Node = load(BM_PATH).new()
	add_child_autofree(bm)
	return bm


func _caster() -> Combatant:
	var c: Combatant = autofree(Combatant.new())
	c.combatant_name = "Adaptive Slime"
	c.is_alive = true
	return c


func test_mimic_announces_the_replay_when_something_was_cast() -> void:
	var bm := _bm()
	bm._last_ability_cast_id = "fire"
	var seen: Array[String] = []
	bm.battle_log_message.connect(func(m): seen.append(str(m)))
	bm._execute_support_ability(_caster(), {"id": "mimic_ability", "effect": "copy_last_ability"}, [])
	var announced := false
	for m in seen:
		if m.to_lower().contains("mimics"):
			announced = true
	assert_true(announced,
		"a support-typed mimic must announce the replay — pre-fix it reached the `_:` warning and did nothing")


func test_mimic_with_nothing_to_copy_says_so_rather_than_warning() -> void:
	var bm := _bm()
	bm._last_ability_cast_id = ""
	var seen: Array[String] = []
	bm.battle_log_message.connect(func(m): seen.append(str(m)))
	bm._execute_support_ability(_caster(), {"id": "mimic_ability", "effect": "copy_last_ability"}, [])
	var explained := false
	for m in seen:
		if m.to_lower().contains("nothing to mimic"):
			explained = true
	assert_true(explained,
		"the empty case must be its own in-voice message, not the unhandled-effect fallback")
