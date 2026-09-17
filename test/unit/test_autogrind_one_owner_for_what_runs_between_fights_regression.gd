extends GutTest

const GdSource := preload("res://test/unit/helpers/gd_source.gd")
const SYS := "res://src/autogrind/AutogrindSystem.gd"
const UI := "res://src/ui/autogrind/AutogrindUI.gd"

## Between battles the grind can only apply an authored heal_amount / mp_amount. Everything else is
## refused BY NAME at runtime with a printed skip line — so a consumer that OFFERS an ability has to
## know that before offering it, or the player writes a rule that can never fire.
##
## ⛔ THAT FACT LIVED IN THREE PLACES AND ONE WAS WRONG. AutogrindSystem's executor held the
## authority; AutogrindUI held a private `_can_apply_between_battles` (added 2026-09-09, after the
## editor seeded a Fighter's power_strike into a dead rule); and because the console's copy was
## PRIVATE, src/llm could not reach it — so the grind prompt re-derived the rule, listed each
## member's whole kit, and @cowir-ai measured 40 of 53 delivered actions as silent no-ops.
##
## 🔑 The repair is not a third filter. It is ONE PUBLIC OWNER — `between_battle_effect_of` — that
## returns the verdict AND the amounts, so the executor reads the keys once and every other consumer
## asks instead of deriving. This file pins that there is exactly one reader.

var _saved_persist: bool


func before_each() -> void:
	_saved_persist = AutogrindSystem._test_disable_persistence
	AutogrindSystem._test_disable_persistence = true


func after_each() -> void:
	AutogrindSystem._test_disable_persistence = _saved_persist


func _abilities() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/abilities.json"))


func test_the_predicate_agrees_with_the_authored_data_for_every_ability() -> void:
	## THE CORPUS ARM. The predicate is state-free, so it can be checked against every authored
	## ability rather than against a hand-picked pair.
	var ab: Dictionary = _abilities()
	assert_gt(ab.size(), 100, "CONTROL: abilities.json must parse, or every verdict below is vacuous")
	var wrong: Array = []
	var qualifying: Array = []
	for aid in ab:
		var a: Dictionary = ab[aid]
		var expected: bool = int(a.get("heal_amount", 0)) > 0 or int(a.get("mp_amount", 0)) > 0
		var got: bool = AutogrindSystem.ability_has_between_battle_effect(str(aid))
		if expected:
			qualifying.append(str(aid))
		if expected != got:
			wrong.append("%s: authored says %s, predicate says %s" % [str(aid), expected, got])
	gut.p("    abilities: %d · qualifying between battles: %d %s" % [ab.size(), qualifying.size(), str(qualifying)])
	assert_gt(qualifying.size(), 0,
		"CONTROL: at least one ability must qualify, or a predicate that always returned false would pass this file")
	assert_eq(wrong, [],
		"the public predicate disagrees with the authored data: %s" % str(wrong))


func test_it_returns_the_amounts_and_not_just_the_verdict() -> void:
	## The amounts are why the executor can stop reading the keys itself. A predicate that answered
	## only "can it" would leave its caller re-reading heal_amount — two expressions of one fact,
	## which is the shape this whole file exists to remove.
	var ab: Dictionary = _abilities()
	var probe: String = ""
	for aid in ab:
		if int((ab[aid] as Dictionary).get("heal_amount", 0)) > 0:
			probe = str(aid)
			break
	assert_ne(probe, "", "CONTROL: some ability must author heal_amount, or this arm is vacuous")
	var got: Dictionary = AutogrindSystem.between_battle_effect_of(probe)
	gut.p("    %s -> %s" % [probe, str(got)])
	assert_true(bool(got.get("ok", false)), "%s authors heal_amount and the predicate refused it" % probe)
	assert_eq(int(got.get("heal", 0)), int((ab[probe] as Dictionary).get("heal_amount", 0)),
		"the returned heal amount does not match what the ability authors")


func test_an_unknown_or_empty_id_is_refused_rather_than_assumed() -> void:
	assert_false(AutogrindSystem.ability_has_between_battle_effect(""), "an empty id must not qualify")
	assert_false(AutogrindSystem.ability_has_between_battle_effect("no_such_ability_at_all"),
		"an unknown id must not qualify — the executor refuses it and a consumer offering it writes a dead rule")


func test_the_executor_reads_the_keys_through_the_owner() -> void:
	## ⛔ ANTI-DRIFT, executor side. The refusal and the application must come from ONE read: if the
	## executor re-derives heal_amount locally, the console can filter on a rule the engine no longer
	## applies, and nothing fails.
	var src: String = GdSource.code_of(SYS)
	var at: int = src.find("func _member_ability_apply(")
	assert_gt(at, 0, "CONTROL: the executor must be locatable")
	var body: String = src.substr(at, src.find("\nfunc ", at + 1) - at)
	assert_true(body.contains("between_battle_effect_of("),
		"the executor no longer routes through the public predicate")
	assert_false(body.contains('get("heal_amount"'),
		"the executor is reading heal_amount itself again — that is the second copy this file removed")
	assert_false(body.contains('get("mp_amount"'),
		"the executor is reading mp_amount itself again")


func test_the_console_asks_rather_than_re_deriving() -> void:
	## ⛔ ANTI-DRIFT, consumer side. The console's private copy was correct and unreachable, which is
	## exactly how the third consumer got it wrong. A consumer may keep its own UNAVAILABLE policy —
	## the console must not block authoring when the autoload is missing — but not its own answer.
	var ui: String = GdSource.code_of(UI)
	assert_gt(ui.length(), 10000, "CONTROL: AutogrindUI was actually read")
	assert_true(ui.contains("ability_has_between_battle_effect("),
		"the console no longer asks AutogrindSystem — it has gone back to deriving the answer itself")
	assert_false(ui.contains('get("heal_amount"'),
		"AutogrindUI is reading heal_amount again: a second copy of the engine's refusal, which is what cost the LLM path 40 of 53 actions")


func test_the_owner_is_public_so_a_third_consumer_can_reach_it() -> void:
	## The whole repair rests on reachability: a correct private copy is what src/llm could not use.
	var src: String = GdSource.code_of(SYS)
	assert_true(src.contains("func between_battle_effect_of("),
		"the owner must exist")
	assert_false(src.contains("func _between_battle_effect_of("),
		"the owner has been made private — src/llm and the console cannot reach it, which is the exact condition that produced the regression")
