extends GutTest

const GdSource := preload("res://test/unit/helpers/gd_source.gd")
const ResolverScript = preload("res://src/autogrind/HeadlessBattleResolver.gd")
const GRIND := "res://src/autogrind/HeadlessBattleResolver.gd"

## @cowir-battle fixed live's pooled strikes (6b89ecf4b): all three paths summed power from LIVING
## participants and then scaled on the UNFILTERED roster, so a KO'd member inflated the multiplier.
## This resolver carried all three of live's pre-fix sites, so the two engines had started computing
## differently — and in OPPOSITE directions:
##
##   live, pre-fix   the dead inflated the scale            -> the strike got STRONGER
##   grind, pre-fix  blade_storm picks an attacker from the rostered list and `continue`s past a
##                   dead one, CONSUMING the hit             -> the storm got WEAKER
##
## Two engines disagreeing about the SIGN of an error from one authored formation is precisely what
## this resolver exists to prevent, so the grind now uses live's living-roster form at all three.
##
## ⚠️ DEAD CODE IN PRODUCTION TODAY, stated rather than implied. Both callers pass `alive` — filtered
## one line above, same frame — and the blade_storm loop damages ENEMIES, so nothing can kill a
## participant mid-execution. Live's gap is real because its roster is fixed at SELECTION and
## execution is speed-sorted; this file has no such gap. These arms therefore CONSTRUCT the condition
## by calling the executors directly, which is the only way to reach it here.

var _res


func before_each() -> void:
	_res = ResolverScript.new()


func _member(name: String, job: String = "fighter") -> Combatant:
	var c := Combatant.new()
	c.initialize({"name": name, "max_hp": 500, "max_mp": 100,
		"attack": 50, "defense": 10, "magic": 30, "speed": 10})
	c.job = {"id": job}
	add_child_autofree(c)
	c.current_hp = c.max_hp
	c.current_ap = 4
	return c


func _enemy(name: String) -> Combatant:
	var c := Combatant.new()
	c.initialize({"name": name, "max_hp": 999999, "max_mp": 0,
		"attack": 10, "defense": 5, "magic": 5, "speed": 5})
	add_child_autofree(c)
	c.current_hp = c.max_hp
	return c


func _total_damage_dealt(enemies: Array) -> int:
	var total: int = 0
	for e in enemies:
		total += e.max_hp - e.current_hp
	return total


func test_a_dead_participant_does_not_inflate_an_all_out_attack() -> void:
	## Four rostered with one dead must strike as three do — live's post-fix behaviour. Pre-fix this
	## file raised FOUR to the 1.5 power while summing power from three.
	var enemies := [_enemy("E1"), _enemy("E2")]
	_res._enemy_party = enemies
	var three := [_member("A"), _member("B"), _member("C")]
	_res._player_party = three
	_res._execute_group_physical(three, "all_out_attack")
	var with_three: int = _total_damage_dealt(enemies)

	var enemies2 := [_enemy("F1"), _enemy("F2")]
	_res._enemy_party = enemies2
	var four := [_member("A"), _member("B"), _member("C"), _member("D")]
	four[3].current_hp = 0
	four[3].is_alive = false
	_res._player_party = four
	_res._execute_group_physical(four, "all_out_attack")
	var with_dead: int = _total_damage_dealt(enemies2)

	gut.p("    all-out: three living %d · four rostered with one dead %d" % [with_three, with_dead])
	assert_gt(with_three, 0, "CONTROL: the strike must land, or the comparison is empty")
	assert_almost_eq(float(with_dead), float(with_three), float(with_three) * 0.02,
		"a KO'd member still changed an all-out attack's output — the scale is reading the rostered list, not the living one")


func test_a_dead_participant_does_not_cost_blade_storm_its_hits() -> void:
	## ⛔ THE OPPOSITE-DIRECTION HALF, and the reason aligning mattered rather than being tidy.
	## blade_storm budgeted hits from the roster and `continue`d past a dead attacker, so a rostered
	## corpse ATE hits — live pre-fix gained damage from a death, this file lost it.
	##
	## ⚠️ COUNTS LANDED HITS, NOT DAMAGE, and that is a fixture repair rather than a style choice.
	## The first version summed damage: each hit rolls its own value, so three-living measured 180-248
	## across five runs and the arm FAILED one run in five while the code was correct. The defect was
	## always about how many hits are THROWN, and the log line is that quantity exactly — deterministic
	## where the sum is not. A noisy observable hid the signal it was measuring.
	var landed := func(res, party: Array) -> int:
		var n: int = 0
		for line in res._battle_log:
			if str(line).contains("Blade Storm hits"):
				n += 1
		return n

	var spec := {"id": "blade_storm", "required_jobs": ["fighter", "rogue", "ninja"], "min_members": 2, "ap_cost": 2}
	var res_three := ResolverScript.new()
	res_three._enemy_party = [_enemy("E1"), _enemy("E2")]
	var three := [_member("A", "fighter"), _member("B", "rogue"), _member("C", "ninja")]
	res_three._player_party = three
	res_three._execute_group_formation(three, spec)
	var hits_three: int = landed.call(res_three, three)

	_res._enemy_party = [_enemy("F1"), _enemy("F2")]
	var four := [_member("A", "fighter"), _member("B", "rogue"), _member("C", "ninja"), _member("D", "cleric")]
	four[3].current_hp = 0
	four[3].is_alive = false
	_res._player_party = four
	_res._execute_group_formation(four, spec)
	var hits_dead: int = landed.call(_res, four)

	gut.p("    blade_storm LANDED HITS: three living %d · four rostered with one dead %d" % [hits_three, hits_dead])
	assert_gt(hits_three, 0, "CONTROL: the storm must land hits, or the comparison is empty")
	assert_eq(hits_dead, hits_three,
		"a rostered corpse cost blade_storm its hits — the budget or the attacker SELECTION is reading the rostered list, and a dead pick consumes the swing")


func test_the_living_filter_is_used_at_every_pooled_site() -> void:
	## Structural, because the behavioural arms above cannot reach production: both callers pass a
	## pre-filtered list, so an unaligned site is invisible in an ordinary grind and only reappears if
	## someone ever lets a participant die mid-execution.
	var code: String = GdSource.code_of(GRIND)
	assert_gt(code.length(), 10000, "CONTROL: the resolver was actually read")
	assert_eq(code.count("pow(participants.size(), 1.5)"), 0,
		"a pooled strike still scales on the ROSTERED list — live scales on the living one since 6b89ecf4b")
	assert_eq(code.count("participants.size() * 2"), 0,
		"blade_storm still budgets hits from the ROSTERED list")
	assert_gt(code.count("_living(participants)"), 2,
		"the living filter is no longer reached from all three pooled sites")


func test_the_production_path_still_cannot_produce_a_dead_participant() -> void:
	## ⚠️ THE ARM THAT KEEPS THIS HONEST. The fix above is dead code today; if that ever stops being
	## true the behavioural arms become live and this note should go. It reds when a caller starts
	## passing something other than the filtered list.
	var code: String = GdSource.code_of(GRIND)
	assert_true(code.contains("_execute_group_physical(alive, \"all_out_attack\")"),
		"the all-out caller no longer passes the pre-filtered `alive` list — a dead participant may now be reachable in production, so re-read the arms above")
	assert_true(code.contains("_execute_group_formation(alive, formation)"),
		"the formation caller no longer passes the pre-filtered `alive` list — same")
