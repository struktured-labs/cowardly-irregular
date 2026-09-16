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
func test_every_resolver_member_this_file_reaches_still_exists() -> void:
	var missing: Array = []
	if _res.get("_enemy_party") == null: missing.append("_enemy_party")
	if _res.get("_player_party") == null: missing.append("_player_party")
	if not _res.has_method("_resolve_ability"): missing.append("_resolve_ability()")
	assert_eq(missing, [],
		"the resolver no longer has these, so the arms above would ABORT into a silent pass: %s" % str(missing))
