extends GutTest

## The restore_mp rule action carried a SECOND COPY of items.json: `[["hi_ether", 100], ["ether", 30]]`,
## applied with member.restore_mp(<literal>) and no ItemSystem call. The numbers agreed with the data,
## which is the only reason nothing was wrong — the identical copy on the HP side drifted to a TENTH of
## the authored heal (potion 50 vs 500, hi_potion 200 vs 2000) and a player's heal_party rule granted a
## tenth of what the potion in their bag promised. heal_party was routed through ItemSystem for that;
## restore_mp, six lines below it, was missed.
##
## NOTHING drove this action: no test in the suite authored a {"type": "restore_mp"} rule, so neither the
## amounts nor the consumption were ever observed. These arms are its first behavioural coverage.
##
## ⛔ The ITEM SET is deliberately unchanged. Elixir and megalixir restore MP (heal_mp_percent) and have
## never been eligible here, exactly as five HP restoratives have never been eligible for heal_party.
## Widening either is the BALANCE ruling already with struktured, not a bug fix.

const SystemScript = preload("res://src/autogrind/AutogrindSystem.gd")
const GdSource := preload("res://test/unit/helpers/gd_source.gd")
const SRC := "res://src/autogrind/AutogrindSystem.gd"

var _sys
var _member: Combatant


func before_each() -> void:
	_sys = SystemScript.new()
	add_child_autofree(_sys)
	_sys._test_disable_persistence = true
	_member = Combatant.new()
	_member.initialize({"name": "Drinker", "max_hp": 100, "max_mp": 100,
		"attack": 10, "defense": 10, "magic": 5, "speed": 10})
	add_child_autofree(_member)
	## TYPED, not [_member]: grind_party is Array[Combatant], and a plain Array assignment is a script
	## error that ABORTS before_each — the party stayed empty and three arms failed on an empty grind.
	var party: Array[Combatant] = [_member]
	_sys.grind_party = party


func _authored_mp(item_id: String) -> int:
	## The expected value comes from the DATA, never from a number typed here — a literal in the test
	## would be a third copy and would agree with a re-hardcoded arm.
	var item_system: Node = get_node_or_null("/root/ItemSystem")
	if item_system == null:
		return -1
	var rec: Dictionary = item_system.get_item(item_id)
	return int((rec.get("effects", {}) as Dictionary).get("heal_mp", -1))


func test_restore_mp_grants_what_the_item_authors() -> void:
	var expected: int = _authored_mp("ether")
	if expected < 0:
		pass_test("ItemSystem autoload unavailable")
		return
	assert_gt(expected, 0, "CONTROL: items.json must author a heal_mp for ether, or this arm proves nothing")
	_member.current_mp = 0
	_member.add_item("ether", 1)
	_sys.apply_autogrind_actions([{"type": "restore_mp"}])
	assert_eq(_member.current_mp, expected,
		"restore_mp must grant the AUTHORED amount (%d), not a number copied into the action" % expected)
	assert_eq(_member.get_item_count("ether"), 0, "the ether must be consumed exactly once")


func test_the_stronger_ether_is_used_first() -> void:
	var expected: int = _authored_mp("hi_ether")
	if expected < 0:
		pass_test("ItemSystem autoload unavailable")
		return
	_member.current_mp = 0
	_member.add_item("ether", 1)
	_member.add_item("hi_ether", 1)
	_sys.apply_autogrind_actions([{"type": "restore_mp"}])
	assert_eq(_member.get_item_count("hi_ether"), 0, "RESTORE_MP_ITEM_ORDER puts hi_ether first")
	assert_eq(_member.get_item_count("ether"), 1, "and it must stop after one — not drink the whole bag")
	assert_eq(_member.current_mp, expected, "the granted amount must be hi_ether's authored heal_mp")


func test_a_member_above_the_threshold_is_left_alone() -> void:
	## Control: without this the arms above would pass on an action that fires unconditionally and
	## burns an ether every time a rule ticks.
	_member.current_mp = _member.max_mp
	_member.add_item("ether", 1)
	_sys.apply_autogrind_actions([{"type": "restore_mp"}])
	assert_eq(_member.get_item_count("ether"), 1,
		"a member at full MP needs nothing — the ether must still be in the bag")


func test_the_consumption_is_tracked_for_the_summary() -> void:
	if _authored_mp("ether") < 0:
		pass_test("ItemSystem autoload unavailable")
		return
	_member.current_mp = 0
	_member.add_item("ether", 1)
	_sys.apply_autogrind_actions([{"type": "restore_mp"}])
	assert_eq(int(_sys.items_consumed.get("ether", 0)), 1,
		"the Summary's Items Used row reads items_consumed — an untracked ether vanishes from the session report")


func test_the_amounts_are_not_a_second_copy_of_the_data() -> void:
	## Structural half. The arms above compare against the authored value, so they agree with a
	## re-hardcoded arm for as long as the copy happens to match — which is exactly the state this
	## fix found. This one fails the moment the numbers come back.
	var code: String = GdSource.code_of(SRC)
	assert_true(code.contains("RESTORE_MP_ITEM_ORDER"),
		"CONTROL: the stripper kept the executor, or the arms below are vacuous")
	assert_true(code.contains('_apply_item_to(member, item_id, "restore_mp")'),
		"restore_mp must apply the item through ItemSystem, the one source of the amounts")
	assert_false(code.contains('["hi_ether", 100]'),
		"a literal amount beside the id is the second copy that drifted to a tenth on the HP side")
	assert_false(code.contains('["ether", 30]'),
		"same for ether — the number belongs in items.json only")
