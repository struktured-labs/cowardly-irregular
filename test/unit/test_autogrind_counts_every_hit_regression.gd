extends GutTest

## `hits` is authored by 5 abilities and read by the live engine (BattleManager:4854, which runs the
## damage step `hits` times). HeadlessBattleResolver's `physical` and `magic` arms each applied ONE
## take_damage per target, so the grind dealt a THIRD of the authored damage from a 3-hit ability.
##
## ⛔ IT IS THE MONSTERS' SIDE, WHICH IS WHY IT MATTERS. No job teaches any of the five; all five are
## monster abilities, and four of their five owners sit in data/enemy_pools.json — the same pools
## AutogrindController:309 draws the grind's enemies from. So the grind UNDERSTATED incoming damage:
##
##   treasure_mimic gold_scatter 3 · assembly_line_automaton repetitive_strike 3
##   rogue_process thread_slash 3  · recursive_loop recursive_strike 3 · time_phantom temporal_strike 2
##
## A grind is meant to be a faithful simulation of the build the player is testing, and the HP-threshold
## interrupt is calibrated against what it reports. Easier-than-live is the wrong direction for both.
##
## 🔑 THIRD INSTANCE OF THIS FILE'S OWN CLASS. Its comments already record `heal_amount` (cure healed 20
## instead of 1300) and `mp_amount` — an authored field the live engine reads and an arm here did not.
## This is the same shape on the damage arms, and it is the gap
## test_ability_effect_keys_reach_the_engine_regression named and handed to this lane; @cowir-battle
## took effect_chance in 5b8ff38e, `hits` was the one still open.

const ResolverScript = preload("res://src/autogrind/HeadlessBattleResolver.gd")
const GdSource := preload("res://test/unit/helpers/gd_source.gd")
const SRC := "res://src/autogrind/HeadlessBattleResolver.gd"

## Read from the data, never typed — a literal here would be a second copy of abilities.json.
const MULTI := "thread_slash"

var _res


func before_each() -> void:
	_res = ResolverScript.new()


func _authored(ability_id: String) -> Dictionary:
	var js: Node = get_node_or_null("/root/JobSystem")
	if js == null or not js.has_method("get_ability"):
		return {}
	return js.get_ability(ability_id)


## MP matters: _resolve_ability spends mp_cost and RETURNS if the caster cannot pay. At max_mp 0 every
## cast was a silent no-op and three arms measured 0 damage against a fix that was working.
func _fighter(name: String, hp: int) -> Combatant:
	var c := Combatant.new()
	c.initialize({"name": name, "max_hp": hp, "max_mp": 999,
		"attack": 30, "defense": 10, "magic": 30, "speed": 10})
	c.current_mp = c.max_mp
	add_child_autofree(c)
	return c


## ⚠️ MEASURE HP DELTAS ON BOTH SIDES. _resolve_attack_with_power RETURNS its computed figure and then
## Combatant.take_damage applies the defense formula AGAIN, so the return is pre-reduction: comparing a
## returned 36 against a delta of 28 fails a fix that is working. The probe is read the same way the
## subject is.
func _one_hit_delta(caster: Combatant, ab: Dictionary) -> int:
	var probe := _fighter("Probe", 9999)
	var power: float = float(ab.get("power", ab.get("damage_multiplier", 1.0)))
	var base_dmg: int = int(caster.get_buffed_stat("attack", caster.attack) * power)
	var before: int = probe.current_hp
	_res._resolve_attack_with_power(caster, probe, base_dmg)
	return before - probe.current_hp


func test_a_three_hit_ability_lands_three_times() -> void:
	var ab: Dictionary = _authored(MULTI)
	if ab.is_empty():
		pass_test("JobSystem autoload unavailable")
		return
	var hits: int = int(ab.get("hits", 1))
	assert_gt(hits, 1, "CONTROL: %s must still author more than one hit, or this arm proves nothing" % MULTI)

	## The per-hit figure comes from the resolver's OWN single-hit path, so the expectation tracks any
	## change to the damage formula instead of pinning today's number.
	var caster := _fighter("Rogue Process", 9999)
	var per_hit: int = _one_hit_delta(caster, ab)
	assert_gt(per_hit, 0, "CONTROL: one hit must do something measurable")

	var target := _fighter("Victim", 9999)
	var before: int = target.current_hp
	_res._resolve_ability(caster, MULTI, [target])
	var lost: int = before - target.current_hp
	gut.p("    %s: hits=%d per_hit=%d lost=%d" % [MULTI, hits, per_hit, lost])
	assert_eq(lost, per_hit * hits,
		"%s authors %d hits and the grind dealt %d — one hit's worth of %d" % [MULTI, hits, lost, per_hit])


## ⛔ THIS ARM ASSERTED THE OPPOSITE AND IT WAS WRONG — it PINNED a divergence I introduced.
##
## Live reads `hits` only in `_execute_physical_ability`, so `temporal_strike` (magic, hits=2) strikes
## ONCE in the real game. I looped it in the magic arm too, wrote an arm asserting the loop, and
## broadcast it as a fix; the grind then hit harder than the game it simulates. @cowir-battle's
## 2d14d92d caught it, and their distinction is the one I had missed: "is this key read at all" is a
## different question from "is it read on the PATH this ability takes". My parity ledger only asked
## the first, and scored this CONSUMED.
##
## Nothing behavioural caught it because `time_phantom` — temporal_strike's only caster — is NOT in
## any enemy pool. Correct by occupancy, which is not correct.
##
## ⚠️ Whether LIVE should loop hits on the magic path is a balance question in @cowir-battle's ledger
## with struktured's name on it. Both inversions close by narrowing the GRIND, because live is the
## anchor — not by widening live to match what I had already shipped.
func test_the_magic_arm_strikes_once_because_live_does() -> void:
	var ab: Dictionary = _authored("temporal_strike")
	if ab.is_empty():
		pass_test("JobSystem autoload unavailable")
		return
	assert_gt(int(ab.get("hits", 1)), 1,
		"CONTROL: temporal_strike must still AUTHOR more than one hit — that is what makes this a parity question and not a no-op")
	assert_eq(str(ab.get("type", "")), "magic", "CONTROL: and must still take the magic arm")
	var caster := _fighter("Time Phantom", 9999)
	var target := _fighter("Victim", 99999)
	var power: float = float(ab.get("power", ab.get("damage_multiplier", 1.0)))
	var element: String = str(ab.get("element", ""))
	var actual: int = int(caster.get_buffed_stat("magic", caster.magic) * power)
	var elem_mod: float = target.calculate_elemental_modifier(element) if element != "" else 1.0
	actual = max(1, int(actual * elem_mod))
	var probe := _fighter("Probe", 99999)
	var pb: int = probe.current_hp
	probe.take_damage(actual, true)
	var one_hit: int = pb - probe.current_hp
	var before: int = target.current_hp
	_res._resolve_ability(caster, "temporal_strike", [target])
	var lost: int = before - target.current_hp
	gut.p("    temporal_strike: authored hits=%d  one hit=%d  dealt=%d" % [int(ab.get("hits", 1)), one_hit, lost])
	assert_eq(lost, one_hit,
		"the magic arm dealt %d, which is %d hits — live strikes once here, so the grind hits harder than the game" % [lost, lost / max(one_hit, 1)])


## The parity claim is about LIVE's structure, so it is asserted against live rather than remembered.
func test_live_still_reads_hits_on_the_physical_path_only() -> void:
	var live: String = GdSource.code_of("res://src/battle/BattleManager.gd")
	assert_gt(live.length(), 50000, "CONTROL: BattleManager was actually read")
	var at: int = live.find('ability.get("hits"')
	assert_gt(at, 0, "CONTROL: live must still read the key at all")
	var owner: int = live.substr(0, at).rfind("func _execute_")
	var owner_line: String = live.substr(owner, 42)
	assert_true(owner_line.begins_with("func _execute_physical_ability"),
		"live now reads hits inside %s — the grind loops only the physical arm and must be taught to follow" % owner_line)


func test_a_single_hit_ability_is_unchanged() -> void:
	## The other direction: a loop that runs when nothing authored `hits` would double every ability
	## in the game. `attack`-shaped abilities author no hits key and must land exactly once.
	var single := "power_strike"
	var ab: Dictionary = _authored(single)
	if ab.is_empty():
		pass_test("JobSystem autoload unavailable")
		return
	assert_false(ab.has("hits"), "CONTROL: %s must author no hits key, or it cannot police the default" % single)
	var caster := _fighter("Fighter", 9999)
	var per_hit: int = _one_hit_delta(caster, ab)
	var target := _fighter("Victim", 9999)
	var before: int = target.current_hp
	_res._resolve_ability(caster, single, [target])
	assert_eq(before - target.current_hp, per_hit,
		"an ability authoring no hits key must land exactly once")


func test_the_volley_stops_at_a_corpse() -> void:
	## Mirrors the live loop's `if not target.is_alive: break`. Without it the grind keeps swinging at
	## a dead combatant, and every extra swing is damage the live game never deals.
	var ab: Dictionary = _authored(MULTI)
	if ab.is_empty():
		pass_test("JobSystem autoload unavailable")
		return
	var caster := _fighter("Rogue Process", 9999)
	var frail := _fighter("Frail", 1)
	_res._resolve_ability(caster, MULTI, [frail])
	assert_false(frail.is_alive, "CONTROL: one hit must be enough to kill a 1 HP target")
	assert_eq(frail.current_hp, 0, "HP must floor at 0, not go further negative with each extra swing")


func test_every_authored_multi_hit_ability_is_reachable_in_a_grind() -> void:
	## The reachability half, derived rather than asserted from memory. If these abilities ever stop
	## being drawable by a grind this arm says so, and the fix above becomes dead weight worth removing.
	var js: Node = get_node_or_null("/root/JobSystem")
	var es: Node = get_node_or_null("/root/EncounterSystem")
	if js == null or es == null or not ("enemy_pools" in es):
		pass_test("autoloads unavailable")
		return
	var monsters: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/monsters.json"))
	var abilities: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/abilities.json"))
	var multi: Array = []
	for aid in abilities.keys():
		if int((abilities[aid] as Dictionary).get("hits", 1)) > 1:
			multi.append(aid)
	assert_gt(multi.size(), 0, "CONTROL: abilities.json must still author a multi-hit ability")

	var pooled: Dictionary = {}
	for region in es.enemy_pools.keys():
		for entry in es.enemy_pools[region]:
			pooled[str(entry.get("id", entry) if entry is Dictionary else entry)] = true
	var reachable: Array = []
	for mid in monsters.keys():
		var owned: Array = (monsters[mid] as Dictionary).get("abilities", [])
		for aid in owned:
			if multi.has(aid) and pooled.has(mid):
				reachable.append("%s/%s" % [mid, aid])
	gut.p("    grind-reachable multi-hit casters: %s" % str(reachable))
	assert_gt(reachable.size(), 0,
		"no pooled monster casts a multi-hit ability any more — the hits loop in the resolver is now unreachable and should be re-justified, not kept on faith")


func test_the_resolver_reads_the_key_the_live_engine_reads() -> void:
	## Structural. The arms above pass on a resolver that happens to hit three times for another
	## reason; this pins that it is the AUTHORED field driving it.
	var code: String = GdSource.code_of(SRC)
	assert_gt(code.length(), 5000, "CONTROL: the resolver was actually read")
	assert_true(code.contains('ability.get("hits", 1)'),
		"the resolver must read the same authored key BattleManager:4854 reads")
