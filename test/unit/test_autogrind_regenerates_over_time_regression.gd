extends GutTest

## `regenerate` is a healing-typed ability that heals OVER TIME: `effect: regen`, `regen_per_turn: 40`,
## `duration: 3`, and NO `heal_amount`. Both engines delivered nothing — live's healing executor reads
## only `heal_amount`, and the resolver's healing arm fell back to `magic x power` once and ticked
## nothing. I measured that at 15:00, declared it a LIVE defect, and handed it to cowir-battle.
##
## They fixed live (`dcfb2158`), which turned it into a REAL PARITY GAP that did not exist this
## morning: live delivers 40/turn for 3 turns, the grind healed 30 once. This closes the grind side.
##
## ⚠️ ROUTED, NOT COPIED. The resolver re-points `category` to "support" for a healing ability that
## carries an effect and authors no heal_amount, so the existing support arm — which already owns what
## an `effect` means — handles it. Duplicating that here is how two definitions of "regen" start to
## drift, which is the class this file's own lane has fixed four times (heal_amount, mp_amount, the
## restore_mp amounts, the bust crop in two files).
##
## ⛔ AND THE META MATTERS AS MUCH AS THE STATUS. Combatant.end_turn ticks "regen" and reads an
## authored override off `_regen_per_turn`, falling back to 5% of max HP when absent. On a 500 HP
## caster that is 25 against an authored 40 — so adding the status alone looks like a working fix and
## heals the wrong number. The arms below check the AMOUNT, not just the presence.

const ResolverScript = preload("res://src/autogrind/HeadlessBattleResolver.gd")
const GdSource := preload("res://test/unit/helpers/gd_source.gd")
const SRC := "res://src/autogrind/HeadlessBattleResolver.gd"

var _res


func before_each() -> void:
	_res = ResolverScript.new()


func _authored(ability_id: String) -> Dictionary:
	var js: Node = get_node_or_null("/root/JobSystem")
	if js == null or not js.has_method("get_ability"):
		return {}
	return js.get_ability(ability_id)


func _cleric(hp: int = 500, cur: int = 100) -> Combatant:
	var c := Combatant.new()
	c.initialize({"name": "Cleric", "max_hp": hp, "max_mp": 9999,
		"attack": 10, "defense": 10, "magic": 30, "speed": 10})
	add_child_autofree(c)
	c.current_mp = c.max_mp
	c.current_hp = cur
	return c


func test_the_cast_grants_regen_rather_than_a_one_off_heal() -> void:
	var ab: Dictionary = _authored("regenerate")
	if ab.is_empty():
		pass_test("JobSystem autoload unavailable")
		return
	assert_eq(str(ab.get("effect", "")), "regen", "CONTROL: regenerate must still author the regen effect")
	assert_false(ab.has("heal_amount"), "CONTROL: and still author no heal_amount — that is what makes the routing load-bearing")
	var c := _cleric()
	_res._player_party = [c]
	_res._enemy_party = []
	var before: int = c.current_hp
	_res._resolve_ability(c, "regenerate", [c])
	assert_true(c.has_status("regen"),
		"the cast granted no regen status — the healing arm healed once and the over-time promise is still dropped")
	assert_eq(c.current_hp, before,
		"the cast healed %d immediately; regenerate heals over TIME and its instant heal is the fallback this fix removes" % (c.current_hp - before))


func test_it_ticks_the_AUTHORED_amount_not_the_engine_default() -> void:
	## The half a status-only fix gets wrong. Combatant falls back to 5% of max HP with no override —
	## 25 on this caster against an authored 40 — and a "regen is applied" arm cannot tell them apart.
	var ab: Dictionary = _authored("regenerate")
	if ab.is_empty():
		pass_test("JobSystem autoload unavailable")
		return
	var authored: int = int(ab.get("regen_per_turn", 0))
	assert_gt(authored, 0, "CONTROL: regenerate must still author a per-turn amount")
	var c := _cleric()
	var fallback: int = int(c.max_hp * 0.05)
	assert_ne(authored, fallback,
		"CONTROL: the authored amount and the 5%% default must DIFFER on this fixture (%d vs %d), or this arm cannot tell them apart" % [authored, fallback])
	_res._player_party = [c]
	_res._enemy_party = []
	_res._resolve_ability(c, "regenerate", [c])
	var before: int = c.current_hp
	c.end_turn()
	gut.p("    one tick: +%d   authored %d   5%% default would be %d" % [c.current_hp - before, authored, fallback])
	assert_eq(c.current_hp - before, authored,
		"the tick healed %d; the authored value is %d and the engine default is %d — the override was not carried" % [c.current_hp - before, authored, fallback])


func test_an_ordinary_heal_is_untouched() -> void:
	## The routing must catch ONLY the over-time shape. `cure` authors a heal_amount and no effect, so
	## it must still heal instantly through the healing arm.
	var ab: Dictionary = _authored("cure")
	if ab.is_empty():
		pass_test("JobSystem autoload unavailable")
		return
	assert_true(ab.has("heal_amount"), "CONTROL: cure must still author a heal_amount")
	var c := _cleric()
	_res._player_party = [c]
	_res._enemy_party = []
	var before: int = c.current_hp
	_res._resolve_ability(c, "cure", [c])
	assert_gt(c.current_hp, before, "cure no longer heals — the routing caught an ordinary heal it should not have")
	assert_false(c.has_status("regen"), "cure granted a regen status; the routing is matching on the wrong shape")


func test_the_routing_re_points_rather_than_duplicating() -> void:
	## Structural, and it is the point of the fix rather than a detail: a copy of the regen logic in
	## the healing arm would pass every behavioural arm above and give this file two definitions of
	## what regen means. That is the exact class this lane has fixed four times.
	var code: String = GdSource.code_of(SRC)
	assert_gt(code.length(), 5000, "CONTROL: the resolver was actually read")
	assert_true(code.contains('category = "support"'),
		"the over-time heal must be re-pointed at the support arm, which already owns what an effect means")
	assert_eq(code.count('elif effect == "regen":'), 1,
		"there must be exactly ONE regen arm in this file — found %d" % code.count('elif effect == "regen":'))
	assert_eq(code.count('set_meta("_regen_per_turn"'), 1,
		"and exactly one place that carries the authored per-turn amount")


## FLOOR. Measured 2026-09-16: renaming a member this file reaches leaves it SILENT —
## e.g. pierces_what_it_pierces went Asserts 17 -> 15 at EC=0, Passing unchanged, no Risky.
## That is rung 3, which `.366`'s exit 4 cannot reach: the arms assert and THEN abort, so GUT
## scores them Passing. `get()` and `has_method()` ANSWER rather than raise — an existence arm
## written with a direct read aborts alongside the arms it exists to catch.
## ⚠️ THIS LIST IS A SNAPSHOT, NOT A DERIVATION, and that is the live limit. It was derived once by
## a script from this file's own `_res.` / AutogrindSystem reaches and then written as literals — so
## a member reached by a NEW arm added later is not covered, and the list goes quietly incomplete
## rather than loudly wrong. @cowir-cutscenes' rule puts it on the wrong side of the line: a figure
## the guard's claim DEPENDS on should be derived, and this is one.
## Deliberately not converted to a runtime derivation, per @cowir-sfx's reasoning: doing that needs
## @cowir-ai's bare-Object exclusion, because a runtime scan of this file would collect the `get` and
## `has_method` calls THIS ARM ITSELF makes and pin the mechanism it is written in. That is a real
## defence against a real hazard, and writing it tonight would be shipping it untested. Correct as of
## 2026-09-16; if you add an arm that reaches a new member, add it here or derive the set properly.
const _FLOOR_ARM_NAME := "test_every_resolver_member_this_file_reaches_still_exists"
const _PINNED_MEMBERS := ["_enemy_party", "_player_party", "_resolve_ability"]

func test_every_resolver_member_this_file_reaches_still_exists() -> void:
	## @cowir-ai's counter to the snapshot limit above, and it converts the failure mode rather than
	## documenting it: a static list fails toward INCOMPLETENESS — add a reach tomorrow and the floor
	## silently covers all-but-one. This counts the distinct members reached in the text BEFORE this
	## function, so the arm cannot count its own `get`/`has_method` calls — @cowir-ai's bare-Object
	## exclusion replaced by SCOPING, which they named as the alternative. A new reach reds here.
	## ⛔ THE SHARED STRIPPER, not a tenth private one. My first version split each line on "#" —
	## adding another inline comment-strip on the day this fleet counted EIGHTEEN redundant
	## private ones (@cowir-music, who used gd_source rather than writing a sixth). It is
	## quote-aware and escape-aware, which a split on "#" is not: a `#` inside a string
	## literal truncates the line and can hide a real reach.
	var own_src: String = GdSource.code_of(get_script().resource_path)
	var cut: int = own_src.find("func %s(" % _FLOOR_ARM_NAME)
	assert_gt(cut, 0, "CONTROL: located this arm, so the scoped slice is real")
	var before: String = own_src.substr(0, cut)
	var reached: Dictionary = {}
	## ⛔ SKIP PATH LITERALS. `AutogrindSystem.gd` inside a res:// string matched as a member named
	## "gd" — the same false positive I fixed in the generator two hours earlier and reintroduced
	## here. A regex reading source cannot tell a member reach from a filename by shape.
	for raw_line in before.split("\n"):
		if raw_line.contains("res://"):
			continue
		## ⛔ TRAILING COMMENTS TOO, per @cowir-sprites: a floor exists to catch a RENAME, and the commit
		## that renames a member is the one whose prose explains the rename BY NAME. `_res.foo()  #
		## renamed from _res.bar` would inflate this count and red a CORRECT file. Leading-## lines were
		## already skipped; this drops the trailing half. Measured 2026-09-16: strict and lenient
		## extraction agree on all ten floored files, so this is latent rather than a live repair.
		## NOT stripped: a member named inside a triple-quoted block. Measured absent in these files,
		## and recorded rather than handled — a quote-aware stripper here would be its own hazard.
		for m in RegEx.create_from_string("(?:_res|AutogrindSystem)\\.([A-Za-z_][A-Za-z_0-9]*)").search_all(raw_line):
			reached[m.get_string(1)] = true
	reached.erase("_test_disable_persistence")
	reached.erase("PER_BATTLE_METAS")   ## read from SOURCE on purpose — see the arm above
	## ⛔ SETS, NOT SIZES. This compared COUNTS until 2026-09-16, and @cowir-cutscenes' completeness
	## finding is why that is not enough: pin {A,B,X} where X exists but is never reached, while the
	## file reaches {A,B,C}, and the existence arm passes (all three exist) AND the count passes
	## (3 == 3) — with C unpinned and X spurious. Equal cardinality is not equal membership, and an
	## over-count is the same defect as an under-count in a louder coat.
	var pinned: Dictionary = {}
	for x in _PINNED_MEMBERS:
		pinned[x] = true
	assert_gt(reached.size(), 0, "CONTROL: the scan found reaches, or this comparison proves nothing")
	var unpinned: Array = []
	for k in reached:
		if not pinned.has(k):
			unpinned.append(k)
	var spurious: Array = []
	for k in pinned:
		if not reached.has(k):
			spurious.append(k)
	gut.p("    reaches: %d | pinned: %d | unpinned: %s | spurious: %s" % [reached.size(), pinned.size(), str(unpinned), str(spurious)])
	assert_eq(unpinned, [], "this file reaches members the floor does not pin — the list is a snapshot: %s" % str(unpinned))
	assert_eq(spurious, [], "the floor pins members this file no longer reaches — stale entries: %s" % str(spurious))

	var missing: Array = []
	if _res.get("_enemy_party") == null: missing.append("_enemy_party")
	if _res.get("_player_party") == null: missing.append("_player_party")
	if not _res.has_method("_resolve_ability"): missing.append("_resolve_ability()")
	assert_eq(missing, [],
		"the resolver no longer has these, so the arms above would ABORT into a silent pass: %s" % str(missing))
