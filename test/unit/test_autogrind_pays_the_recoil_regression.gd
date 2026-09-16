extends GutTest

## `damage_to_self_pct` costs the caster a share of the damage it dealt (BattleManager:5171). The
## resolver read it nowhere — and this is the FIRST gap in this file that made the grind HARDER than
## the game it simulates, rather than easier.
##
##   stack_overflow   magic, 3.0x, all_enemies, 20% recoil   cast by recursive_loop (POOLED)
##
## So in the grind that monster paid nothing for its biggest attack and survived fights the real game
## kills it in. Live's own comment records the same field being unread on ITS side once: "stack_overflow
## dealt 3.0x to all enemies for free, defeating the catastrophic-damage / 20%-recoil tradeoff design."
##
## ⚠️ THE DIRECTION IS THE POINT. Every previous gap I closed made the grind softer, and I built a
## habit of asking "does this make the grind weaker than live". That question would have MISSED this
## one. The property is parity, not difficulty — a simulation that is harsher than the game is wrong
## in exactly the same way, and the safety limits are calibrated against whatever it reports.

const ResolverScript = preload("res://src/autogrind/HeadlessBattleResolver.gd")
const GdSource := preload("res://test/unit/helpers/gd_source.gd")
const SRC := "res://src/autogrind/HeadlessBattleResolver.gd"
const LIVE := "res://src/battle/BattleManager.gd"

var _res


func before_each() -> void:
	_res = ResolverScript.new()


func _authored(ability_id: String) -> Dictionary:
	var js: Node = get_node_or_null("/root/JobSystem")
	if js == null or not js.has_method("get_ability"):
		return {}
	return js.get_ability(ability_id)


## HP/MP after add_child — entering the tree restores both.
func _combatant(name: String, hp: int = 99999) -> Combatant:
	var c := Combatant.new()
	c.initialize({"name": name, "max_hp": hp, "max_mp": 999,
		"attack": 20, "defense": 15, "magic": 30, "speed": 10})
	add_child_autofree(c)
	c.current_hp = hp
	c.current_mp = c.max_mp
	return c


func test_a_recoiling_cast_costs_its_caster() -> void:
	var ab: Dictionary = _authored("stack_overflow")
	if ab.is_empty():
		pass_test("JobSystem autoload unavailable")
		return
	var pct: float = float(ab.get("damage_to_self_pct", 0.0))
	assert_gt(pct, 0.0, "CONTROL: stack_overflow must still author a recoil")
	var loop := _combatant("Recursive Loop")
	var party: Array = [_combatant("A"), _combatant("B"), _combatant("C")]
	_res._player_party = party
	_res._enemy_party = [loop]
	var hp_before: int = loop.current_hp
	var party_before: int = 0
	for c in party:
		party_before += c.current_hp
	_res._resolve_ability(loop, "stack_overflow", party)
	var total_dealt: int = 0
	for c in party:
		total_dealt += c.max_hp - c.current_hp
	var self_damage: int = hp_before - loop.current_hp
	gut.p("    stack_overflow on %d targets: dealt %d total, recoil %d (%.0f%%)" % [party.size(), total_dealt, self_damage, pct * 100.0])
	assert_gt(total_dealt, 0, "CONTROL: the cast must land damage, or there is nothing to recoil from")
	assert_gt(self_damage, 0, "the caster paid nothing for a 3.0x all-enemies cast — the tradeoff the ability is built around")


func test_the_recoil_is_proportional_to_the_WHOLE_volley() -> void:
	## Live accumulates across the target loop and pays once. A per-target implementation passes the
	## arm above and charges N times; a first-target-only one undercharges. Both are caught here,
	## because the expected value is computed from the total the party actually lost.
	var ab: Dictionary = _authored("stack_overflow")
	if ab.is_empty():
		pass_test("JobSystem autoload unavailable")
		return
	var pct: float = float(ab.get("damage_to_self_pct", 0.0))
	var loop := _combatant("Recursive Loop")
	var party: Array = [_combatant("A"), _combatant("B"), _combatant("C")]
	_res._player_party = party
	_res._enemy_party = [loop]
	var hp_before: int = loop.current_hp
	_res._resolve_ability(loop, "stack_overflow", party)
	var total_dealt: int = 0
	for c in party:
		total_dealt += c.max_hp - c.current_hp
	## ⚠️ DELTAS ON BOTH SIDES. `round(total * pct)` is the amount REQUESTED; live and the grind both
	## pass it to take_damage, which applies the defense formula again — so the caster's HP falls by
	## LESS than the requested figure. Comparing the request against the delta fails a correct fix.
	## Third time this trap has cost me a cycle today (the hits loop, the drain, and now this), so the
	## probe takes the same route the subject does instead of my arithmetic predicting it.
	var requested: int = max(1, int(round(total_dealt * pct)))
	var probe := _combatant("Probe")
	var pb: int = probe.current_hp
	probe.take_damage(requested, true)
	var expected: int = pb - probe.current_hp
	assert_gt(expected, 0, "CONTROL: the requested recoil must land something on an identical body")
	assert_eq(hp_before - loop.current_hp, expected,
		"the party lost %d, so the recoil REQUESTED is %d, which lands %d on this caster — it paid %d" % [
			total_dealt, requested, expected, hp_before - loop.current_hp])


func test_an_ability_with_no_recoil_costs_its_caster_nothing() -> void:
	## A recoil applied unconditionally would damage the caster on every magic cast in the game.
	var ab: Dictionary = _authored("fire")
	if ab.is_empty():
		pass_test("JobSystem autoload unavailable")
		return
	assert_false(ab.has("damage_to_self_pct"), "CONTROL: fire must author no recoil")
	var caster := _combatant("Mage")
	var hero := _combatant("Hero")
	_res._player_party = [hero]
	_res._enemy_party = [caster]
	var before: int = caster.current_hp
	_res._resolve_ability(caster, "fire", [hero])
	assert_eq(caster.current_hp, before, "an ability authoring no recoil must cost its caster no HP")


func test_a_cast_that_lands_nothing_costs_no_recoil() -> void:
	## Live gates on total_dealt > 0. All targets dead means nothing landed, so the caster must not
	## hurt itself for an attack that did not happen.
	var ab: Dictionary = _authored("stack_overflow")
	if ab.is_empty():
		pass_test("JobSystem autoload unavailable")
		return
	var loop := _combatant("Recursive Loop")
	var corpse := _combatant("Corpse", 10)
	_res._player_party = [corpse]
	_res._enemy_party = [loop]
	corpse.take_damage(99999)
	assert_false(corpse.is_alive, "CONTROL: the target must actually be dead")
	var before: int = loop.current_hp
	_res._resolve_ability(loop, "stack_overflow", [corpse])
	assert_eq(loop.current_hp, before,
		"the caster took recoil for a cast that landed on nobody")


func test_live_still_pays_it_after_the_loop_on_the_magic_path() -> void:
	## Axis 2 plus placement: per-target recoil and whole-volley recoil differ by a factor of N, and
	## only the source says which live does.
	var live: String = GdSource.code_of(LIVE)
	assert_gt(live.length(), 50000, "CONTROL: BattleManager was actually read")
	var at: int = live.find('ability.get("damage_to_self_pct"')
	assert_gt(at, 0, "CONTROL: live must still read the key")
	var owner: int = live.substr(0, at).rfind("func _execute_")
	assert_true(live.substr(owner, 44).begins_with("func _execute_magic_ability"),
		"live reads damage_to_self_pct outside the magic executor now — the grind pays it only there")
	assert_true(live.substr(at, 400).contains("total_dealt_for_recoil"),
		"live no longer charges the recoil against an accumulated total — the grind pays on the whole volley and must follow")
	var code: String = GdSource.code_of(SRC)
	assert_gt(code.length(), 5000, "CONTROL: the resolver was actually read")
	assert_true(code.contains("_recoil_to(caster, ability, total_for_recoil"),
		"the resolver must charge the recoil against the accumulated volley total")
