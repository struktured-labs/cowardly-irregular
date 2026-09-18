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
##
## ⛔ AND IT NEARLY BECAME A FOURTH COPY. @cowir-ai extracted the same owner from the LLM side within
## the hour — `ability_works_between_battles`, a bool — while this lane extracted it from the engine
## side. Two lanes fixing a duplication BY DUPLICATING, neither able to see the other's uncommitted
## work. The collapse keeps THEIR name for the verdict-only call (RuleComposer already uses it in
## four places, and resolving a collision should not also move another lane's call sites) and THIS
## lane's dictionary for the owner, because a bool leaves the caller re-reading the amounts.

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
		var got: bool = AutogrindSystem.ability_works_between_battles(str(aid))
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
	assert_false(AutogrindSystem.ability_works_between_battles(""), "an empty id must not qualify")
	assert_false(AutogrindSystem.ability_works_between_battles("no_such_ability_at_all"),
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
	assert_true(ui.contains(".ability_works_between_battles("),
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


func test_only_the_owner_answers_the_between_battle_question() -> void:
	## ⛔ THE ARM THAT WOULD HAVE CAUGHT THE COLLISION — and my first version counted over the FILE
	## and red at 4, which is the corpus error this lane has been naming all day, committed inside
	## the arm written to prevent a duplication. The engine has a THIRD reader and it is legitimate:
	## `_find_restorative_caster` asks a DIFFERENT question — a caster holding an HP-healing ability
	## for the heal path — and excludes mp_amount ON PURPOSE, which is why `channel` qualifies here
	## and not there. Counting readers by file calls that a duplicate; counting by QUESTION does not.
	var src: String = GdSource.code_of(SYS)
	assert_gt(src.length(), 10000, "CONTROL: AutogrindSystem was actually read")
	var owner_at: int = src.find("func between_battle_effect_of(")
	assert_gt(owner_at, 0, "CONTROL: the owner must be locatable")
	var owner: String = src.substr(owner_at, src.find("\nfunc ", owner_at + 1) - owner_at)
	assert_true(owner.contains('get("heal_amount"') and owner.contains('get("mp_amount"'),
		"the owner no longer reads both keys — it cannot be the owner of a fact it does not read")

	## Every OTHER reader in the engine, by enclosing function, derived rather than listed.
	var lines: PackedStringArray = src.split("\n")
	var here: String = ""
	var others: Array = []
	for line in lines:
		if line.begins_with("func "):
			here = line.split("(")[0].substr(5)
		var t: String = line.strip_edges()
		if t.begins_with("#"):
			continue
		if not (t.contains('get("heal_amount"') or t.contains('get("mp_amount"')):
			continue
		if here == "between_battle_effect_of":
			continue
		if not others.has(here):
			others.append(here)
	gut.p("    readers outside the owner: %s" % str(others))
	## _find_restorative_caster is DECLARED: different question, HP-only, heal-path.
	assert_eq(others, ["_find_restorative_caster"],
		"a function other than the owner reads the between-battle keys: %s. _find_restorative_caster is declared (different question, HP-only); anything else is a second owner, which is how the collision with @cowir-ai's extraction happened." % str(others))

	## And the executor must not have gone back to reading them directly.
	var exec_at: int = src.find("func _member_ability_apply(")
	var executor: String = src.substr(exec_at, src.find("\nfunc ", exec_at + 1) - exec_at)
	assert_false(executor.contains('get("heal_amount"'),
		"the executor reads heal_amount again — the duplication the owner was extracted to remove")
