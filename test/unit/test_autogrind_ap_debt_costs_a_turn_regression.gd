extends GutTest

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
