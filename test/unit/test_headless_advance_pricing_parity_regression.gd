extends GutTest

## The autogrind resolver charged one AP LESS for an Advance than the game it simulates.
##
##   live      BattleManager.billed_ap(ap, n)  ->  n, except n>=5 at a full bank, which is n-1
##   headless  raw.size() - 1                  ->  n-1, at EVERY size
##
## So a 3-action Advance cost 2 AP under automation and 3 in manual play. Automation cheaper than
## playing it yourself is the yield tax inverted, and it makes a grind an unfaithful simulation of
## the build the player is actually testing. @cowir-battle found the divergence; the pricing
## predates Full Bank entirely (resolver's first commit), so nothing regressed — it was never right.
##
## ⚠️ WHY THE EXISTING GUARD MISSED IT, WHICH IS THE PART WORTH KEEPING. The five-action chain test
## had an arm for exactly this seam, and it asserted the resolver "still charge size-1, which makes
## the fifth free there by construction" — labelled CONTROL, the one line nobody re-reads. That
## sentence is true for five-at-a-full-bank and false for two, three and four, and the source
## comment above the code said the same wrong thing. Each corroborated the other because one was
## written from the other. Both were TEXT asserts, and text cannot compare headless to live: it
## compares headless to a remembered string. This file measures AP instead.
##
## The fix is structural rather than arithmetic: billed_ap is a static func whose own comment
## declares it the single authority, written after two UI surfaces each rolled their own
## subtraction and both misreported a full-bank turn. The resolver was a third. It now asks.

var _abs: Node = null


func before_each() -> void:
	_abs = get_node_or_null("/root/AutobattleSystem")
	if _abs:
		_abs._test_disable_persistence = true


func after_each() -> void:
	if _abs:
		_abs.character_profiles.erase("pricing_hero")


func _hero() -> Combatant:
	var c := Combatant.new()
	c.initialize({"name": "Pricing Hero", "max_hp": 600, "max_mp": 60,
		"attack": 15, "defense": 40, "magic": 15, "speed": 12})
	add_child_autofree(c)
	return c


## One round, so the arithmetic is closed: AP is charged at SELECTION, before execution, so a foe
## that dies to the first action still pays for all queued actions. A durable foe instead runs the
## full 50 rounds, and `can_brave` refusals make the final AP oscillate rather than track price.
func _one_shot_foe() -> Combatant:
	var e := Combatant.new()
	e.initialize({"name": "Bag", "max_hp": 1, "max_mp": 0,
		"attack": 0, "defense": 0, "magic": 0, "speed": 1})
	add_child_autofree(e)
	return e


func _run_with_queue_of(n: int) -> Dictionary:
	var hero := _hero()
	var acts: Array = []
	for i in n:
		acts.append({"type": "attack", "target": "lowest_hp_enemy"})
	_abs.set_character_script("pricing_hero", {"rules": [
		{"conditions": [{"type": "always"}], "actions": acts, "enabled": true}]})
	var resolver := HeadlessBattleResolver.new()
	var res: Dictionary = resolver.resolve_battle([hero], [_one_shot_foe()])
	return {"ap": hero.current_ap, "rounds": int(res.get("rounds", -1))}


func test_headless_charges_what_the_live_rule_charges() -> void:
	if _abs == null:
		pass_test("AutobattleSystem autoload unavailable")
		return
	# Per-row, never a verdict: a queue is a conjunction of prices and aggregating loses the one
	# that moved. Under the old size-1 pricing rows 2, 3 and 4 are each wrong by exactly 1 AP.
	var rows: Array = []
	# n=1 is NOT an Advance -- the resolver takes a separate branch and billed_ap does not govern
	# it. See the single-action arm below, which records an open question rather than pinning one.
	for n in [2, 3, 4]:
		var got: Dictionary = _run_with_queue_of(n)
		assert_eq(got["rounds"], 1,
			"precondition: queue of %d must resolve in ONE round or the AP below is not one decision" % n)
		# Start 0, +1 at round start, then the Advance is billed against that 1.
		var expected: int = 1 - BattleManager.billed_ap(1, n)
		rows.append("n=%d ap=%d expected=%d" % [n, got["ap"], expected])
		assert_eq(got["ap"], expected,
			"queue of %d: headless must charge billed_ap(1,%d)=%d, leaving %d AP" % [
				n, n, BattleManager.billed_ap(1, n), expected])
	gut.p("    " + " | ".join(rows))


func test_a_single_action_is_not_billed_as_an_advance() -> void:
	## Scoping this change honestly. A queue of one takes the non-Advance branch, so the Advance
	## price does not apply and this arm asserts only what was measured.
	if _abs == null:
		pass_test("AutobattleSystem autoload unavailable")
		return
	var got: Dictionary = _run_with_queue_of(1)
	assert_eq(got["rounds"], 1, "precondition: one round")
	assert_eq(got["ap"], 1, "a lone action is not an Advance: the round's +1 stands, nothing is billed")

	## ⚠️ OPEN, AND NOT MINE TO SETTLE. Live `_execute_attack` spends 1 AP (BattleManager:4243)
	## against the same natural +1, netting zero, while headless bills a lone action nothing and
	## therefore RISES. Over 50 rounds a headless single-action script parks at +4 (measured); the
	## live side is reasoned, not measured, and AP LEVEL gates Advance affordability, group attacks
	## and every `ap >=` rule condition. Raised with @cowir-battle, who owns BattleManager. Do not
	## "fix" this by charging a lone action here until the live number is measured, or autogrind
	## will diverge in the other direction.


func test_the_fifth_action_is_free_only_at_a_full_bank() -> void:
	## The one case the old comment described correctly, kept so the fix cannot over-correct into
	## charging five at a full bank. This is a property of billed_ap, asserted against the authority.
	assert_eq(BattleManager.billed_ap(4, 5), 4, "five at +4 AP bills four — the fifth is the free one")
	assert_eq(BattleManager.billed_ap(3, 5), 5, "below a full bank there is no discount at all")
	assert_eq(BattleManager.billed_ap(4, 4), 4, "and four at +4 is not a full bank queue, so no discount")
	assert_eq(BattleManager.billed_ap(4, 2), 2,
		"CONTROL: the discount is not a blanket size-1 — this is the value the resolver used to return 1 for")


func test_the_resolver_asks_the_authority_instead_of_restating_it() -> void:
	## Structural half. The arithmetic above would still pass if someone reimplemented billed_ap's
	## body inline and it happened to agree today; billed_ap exists precisely because two surfaces
	## did that and drifted.
	var src := FileAccess.get_file_as_string("res://src/autogrind/HeadlessBattleResolver.gd")
	assert_gt(src.length(), 1000, "CONTROL: the resolver was actually read")
	assert_string_contains(src, "BattleManager.billed_ap(",
		"the resolver must ASK the live pricing rule")
	assert_false(src.contains("raw.size() - 1"),
		"a local subtraction is a second authority, which is the defect billed_ap was created to end")
