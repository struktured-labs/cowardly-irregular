extends GutTest

const GdSource := preload("res://test/unit/helpers/gd_source.gd")

## AP debt is free in the grind and expensive in live. Found by @cowir-battle, verified here against
## the real `_selection_phase` rather than their hand-driven probe — they stated that limit themselves
## and asked for the check, and the main loop (:159) calls _selection_phase with no debt filtering, so
## their finding holds through the path a grind actually takes.
##
## LIVE, BattleManager._process_next_selection:1604 —
##     if current_combatant.current_ap < 0:
##         current_combatant.gain_ap(1)     # pay the debt
##         selection_index += 1
##         continue                         # <- skips the NATURAL gain at :1635 AND the turn
##
## So indebted: +1 per round, turn FORFEITED. Solvent: +1 natural gain, acts.
##
## THE GRIND paid debt at round start AND granted the natural +1 unconditionally in selection, then
## let the combatant act. Indebted: +2 per round, turn kept. A -2 hole cost two turns in the game and
## nothing at all in the engine that grades your script.
##
## 🔑 WHY IT IS THIS LANE'S BUG AND NOT A CURIOSITY: Advance's entire cost model is "queue up to 4
## actions, each costs 1 AP, can go into debt". The debt IS the price. An Advance-heavy autobattle
## script therefore grades better in the grind than it plays — the same direction as the `billed_ap`
## gap this file already records, one layer up: the CHARGE was fixed and the REPAYMENT stayed free.

const ResolverScript = preload("res://src/autogrind/HeadlessBattleResolver.gd")

var _res


func before_each() -> void:
	_res = ResolverScript.new()


func _fighter(name: String, ap: int) -> Combatant:
	var c := Combatant.new()
	c.initialize({"name": name, "max_hp": 9999, "max_mp": 999,
		"attack": 40, "defense": 10, "magic": 40, "speed": 15})
	add_child_autofree(c)
	c.current_hp = c.max_hp
	c.current_mp = c.max_mp
	c.current_ap = ap
	return c


## The real selection path, with a live enemy so the phase has something to target.
func _run_selection(hero: Combatant) -> Array:
	var foe := _fighter("Foe", 0)
	_res._player_party = [hero]
	_res._enemy_party = [foe]
	return _res._selection_phase()


func _acted(actions: Array, who: Combatant) -> bool:
	for a in actions:
		if a.get("combatant") == who:
			return true
	return false


func test_an_indebted_combatant_recovers_one_ap_not_two() -> void:
	var hero := _fighter("Debtor", -2)
	_res._player_party = [hero]
	_res._enemy_party = [_fighter("Foe", 0)]
	_res._tick_round_start()
	var after_tick: int = hero.current_ap
	_res._selection_phase()
	gut.p("    AP: -2 -> %d after round start -> %d after selection" % [after_tick, hero.current_ap])
	assert_eq(hero.current_ap, -1,
		"live pays AP debt ONCE per round (BattleManager:1604) — the grind paid at round start AND granted the natural +1")


func test_an_indebted_combatant_forfeits_its_turn() -> void:
	## The half that costs nothing to get wrong and everything to leave wrong: live's `continue`
	## means no action is queued at all.
	var hero := _fighter("Debtor", -2)
	var actions: Array = _run_selection(hero)
	assert_false(_acted(actions, hero),
		"a combatant in AP debt must not act — live forfeits the turn, and the debt is Advance's entire price")


func test_a_solvent_combatant_still_gains_and_still_acts() -> void:
	## CONTROL. Without it the fix could be "nobody ever gains AP" and every arm above would pass.
	var hero := _fighter("Solvent", 0)
	var actions: Array = _run_selection(hero)
	gut.p("    solvent AP 0 -> %d, acted=%s" % [hero.current_ap, _acted(actions, hero)])
	assert_eq(hero.current_ap, 1, "the natural +1 must still land for anyone not in debt")
	assert_true(_acted(actions, hero), "and they must still take their turn")


func test_the_last_point_of_debt_still_costs_the_turn_it_is_paid_on() -> void:
	## Boundary: -1 pays to 0 and the turn is STILL gone. Off-by-one here would make the final point
	## of debt free, which is the cheapest possible version of the same bug.
	var hero := _fighter("Debtor", -1)
	var actions: Array = _run_selection(hero)
	assert_eq(hero.current_ap, 0, "the last debt point is paid")
	assert_false(_acted(actions, hero), "and the turn it was paid on is still forfeited")


func test_an_indebted_enemy_follows_the_same_rule() -> void:
	## Live's selection loop is per-combatant and does not care which side you are on. An enemy that
	## could Advance into debt for free would be the same defect aimed at the party.
	var hero := _fighter("Hero", 0)
	var foe := _fighter("Foe", -2)
	_res._player_party = [hero]
	_res._enemy_party = [foe]
	var actions: Array = _res._selection_phase()
	assert_eq(foe.current_ap, -1, "an indebted enemy recovers one point, as live does")
	assert_false(_acted(actions, foe), "and forfeits its turn too")


func test_debt_is_reachable_at_all_through_the_advance_path() -> void:
	## FLOOR for the whole file: if nothing in the grind can spend past zero, every arm above is
	## defending a state no session reaches. billed_ap is the charge that creates the debt.
	var code: String = FileAccess.get_file_as_string("res://src/autogrind/HeadlessBattleResolver.gd")
	assert_gt(code.length(), 2000, "CONTROL: the source must have loaded")
	assert_true(code.contains("billed_ap"),
		"FLOOR: the grind must still charge AP for Advance, or AP debt is unreachable and this file guards nothing")
	var hero := _fighter("Spender", 0)
	hero.spend_ap(3)
	assert_lt(hero.current_ap, 0, "FLOOR: a combatant can in fact be driven into debt")


## FLOOR FOR THE WHOLE FILE, added 2026-09-16. Every arm here reaches members of the resolver,
## and a member that is RENAMED does not fail — it aborts the arm at runtime, which GUT scores
## PASSING when the abort lands after the last assert. Measured on my own meta guard that day:
## Passing 10 -> 10, Failing 0, Risky 0, EC 0, and only Asserts moved (22 -> 17).
## @cowir-sfx's form, and it needs no judgement about WHY a member is reached: the silent-abort
## failure does not care, so a vehicle is as worth pinning as a subject. `get()` returns null for
## an absent property rather than raising; `assert_ne(x, null)` is NOT usable — it deep-compares.
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
const _PINNED_COUNT := 4

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
	gut.p("    reaches before this arm: %d | pinned: %d" % [reached.size(), _PINNED_COUNT])
	assert_gt(reached.size(), 0, "CONTROL: the scan found reaches, or this count proves nothing")
	assert_eq(reached.size(), _PINNED_COUNT,
		"this file now reaches %d distinct members and the floor pins %d — add the new one, the list is a snapshot: %s" % [reached.size(), _PINNED_COUNT, str(reached.keys())])

	var missing: Array = []
	if _res.get("_enemy_party") == null: missing.append("_enemy_party")
	if _res.get("_player_party") == null: missing.append("_player_party")
	if not _res.has_method("_selection_phase"): missing.append("_selection_phase()")
	if not _res.has_method("_tick_round_start"): missing.append("_tick_round_start()")
	assert_eq(missing, [],
		"the resolver no longer has these, so the arms above would ABORT into a silent pass: %s" % str(missing))
