extends GutTest

## `absorb_amount` is read by live (BattleManager:5860) and by the grind NOWHERE — but unlike every
## other missing-read this lane has closed, THE MECHANISM WAS ALREADY LIVE IN THE GRIND AND UNCAPPED.
##
## The support arm's unmodelled-effect else DID add the status (`add_status("damage_absorb", 2)`),
## and Combatant.take_damage:349 honours it: `int(get_meta("_damage_absorb_budget", -1))`, where a
## MISSING meta means -1 means UNLIMITED. So the grind granted total immunity plus 1:1 self-healing
## for the full duration, on a caster the grind draws every session:
##
##   the_absence — POOLED (abstract_overworld), 8000 max HP, casts fill_the_void (absorb_amount 1000)
##
## Live had exactly this bug and fixed it on 2026-09-10, in the commit whose comment says a cast
## "made it immune AND self-healing against a whole party for two full rounds, which stalls the fight
## rather than complicating it." The grind never received that fix because it never read the key —
## a repair that lands on one engine and not the other is invisible to a key census, which sees the
## grind "handling" the effect.
##
## ⚠️ AND THE UNCAPPED DIRECTION IS THE EXPENSIVE ONE HERE. A grind is unattended: an enemy that
## cannot be damaged for two rounds at a time does not lose the fight, it runs the resolver to
## MAX_ROUNDS and terminates "stalemate", spending real session time and skewing the win rate the
## Dashboard reports.
##
## NOT fixed here, measured and declared: `guardian_wall` authors absorb_amount 800 with
## effect "barrier", and LIVE NEVER READS IT — live's barrier is "nullify one hit outright, then
## break" (3 consumer sites). So that 800 is decoration in live, and the grind models barrier not at
## all. Both are real and neither is this file's: the first is @cowir-battle's data question, the
## second needs the grind's damage paths, which is a wider change than one arm.

const ResolverScript = preload("res://src/autogrind/HeadlessBattleResolver.gd")

var _res


func before_each() -> void:
	_res = ResolverScript.new()


func _authored(ability_id: String) -> Dictionary:
	var js: Node = get_node_or_null("/root/JobSystem")
	if js == null or not js.has_method("get_ability"):
		return {}
	return js.get_ability(ability_id)


func _combatant(name: String, hp: int = 8000) -> Combatant:
	var c := Combatant.new()
	c.initialize({"name": name, "max_hp": hp, "max_mp": 999,
		"attack": 30, "defense": 0, "magic": 30, "speed": 10})
	add_child_autofree(c)
	c.current_mp = c.max_mp
	c.current_hp = hp
	return c


func test_the_ward_carries_the_authored_budget() -> void:
	var ab: Dictionary = _authored("fill_the_void")
	if ab.is_empty():
		pass_test("JobSystem autoload unavailable")
		return
	var budget: int = int(ab.get("absorb_amount", -1))
	assert_gt(budget, 0, "CONTROL: fill_the_void must still author an absorb_amount")

	var caster := _combatant("The Absence")
	_res._player_party = []
	_res._enemy_party = [caster]
	_res._resolve_ability(caster, "fill_the_void", [caster])
	assert_true(caster.has_status("damage_absorb"), "precondition: the ward is up")
	assert_eq(int(caster.get_meta("_damage_absorb_budget", -1)), budget,
		"the ward must carry the authored budget — absent meta is UNLIMITED and is what the grind had")


func test_damage_past_the_budget_lands_instead_of_being_erased() -> void:
	## The behavioural half. Without the budget the ward eats an arbitrarily large hit and HEALS off
	## it; with it, the overflow lands in the SAME hit. Asserted as an HP DELTA, never a returned
	## figure — take_damage applies its own reduction.
	var ab: Dictionary = _authored("fill_the_void")
	if ab.is_empty():
		pass_test("JobSystem autoload unavailable")
		return
	var budget: int = int(ab.get("absorb_amount", -1))

	var warded := _combatant("The Absence")
	## Hurt first, so absorbed damage has somewhere to heal INTO — at full HP the heal is invisible
	## and an uncapped ward would look identical to a capped one.
	warded.current_hp = warded.max_hp / 2
	_res._enemy_party = [warded]
	_res._resolve_ability(warded, "fill_the_void", [warded])
	assert_true(warded.has_status("damage_absorb"), "precondition: the ward is up")

	var hp_before: int = warded.current_hp
	var swing: int = budget * 3
	warded.take_damage(swing, true)
	gut.p("    budget=%d swing=%d hp %d -> %d" % [budget, swing, hp_before, warded.current_hp])
	assert_lt(warded.current_hp, hp_before,
		"a swing of %d against a %d budget must LOSE the target HP — uncapped, it healed instead" % [swing, budget])
	assert_false(warded.has_status("damage_absorb"),
		"and the ward breaks once its budget is spent")


func test_an_unbudgeted_ward_is_still_unlimited() -> void:
	## Live keeps the pre-budget rule for any ability authored WITHOUT the key, so this pins the
	## branch rather than the ability — and it is the arm that stops the fix being "always cap".
	var warded := _combatant("Ward")
	warded.current_hp = warded.max_hp / 2
	warded.add_status("damage_absorb", 3)
	assert_false(warded.has_meta("_damage_absorb_budget"), "precondition: no budget parked")
	var hp_before: int = warded.current_hp
	warded.take_damage(500, true)
	assert_gt(warded.current_hp, hp_before, "with no budget the ward absorbs and heals, as live does")


func test_the_pooled_caster_that_makes_this_reachable_is_still_pooled() -> void:
	## Crying-wolf arm. If the_absence leaves every pool, the severity argument in the header weakens
	## and should be re-read rather than assumed; if it stays, this fix keeps earning its place.
	var es: Node = get_node_or_null("/root/EncounterSystem")
	if es == null or es.monster_database.is_empty():
		pass_test("EncounterSystem unavailable")
		return
	var pooled: Array = []
	for pool_id in es.enemy_pools:
		var entry = es.enemy_pools[pool_id]
		var mons = entry.get("monsters", entry) if entry is Dictionary else entry
		if mons is Array:
			for m in mons:
				if (str(m.get("id", m)) if m is Dictionary else str(m)) == "the_absence":
					pooled.append(pool_id)
	gut.p("    the_absence pools: %s" % str(pooled))
	assert_gt(pooled.size(), 0,
		"the_absence is the reachable caster this fix is justified by — if it is pooled nowhere, re-read the header")
	assert_true("fill_the_void" in (es.monster_database["the_absence"] as Dictionary).get("abilities", []),
		"CONTROL: and it must still cast the ability")
