extends GutTest

## `drain_percentage` is authored by 5 abilities and read by the live engine (BattleManager:5121 heals
## the caster for that share of the damage actually dealt). HeadlessBattleResolver read it nowhere, so
## in the grind a drain dealt its damage and healed nobody. It breaks in BOTH directions and both are
## reachable, which is why this is not a curiosity:
##
##   PLAYER SIDE   drain_life is a Necromancer ability — one of the five meta jobs CLAUDE.md records
##                 as real. A sustain build is exactly what autogrind exists to evaluate, and in the
##                 grind it did not sustain: the HP-threshold interrupt stopped sessions that live
##                 play carries indefinitely. The grind reported the build as unviable when it is not.
##   MONSTER SIDE  four POOLED monsters drain and never healed — specter (4), pipe_phantom (6),
##                 shadow_knight (9, life_drain at a full 100%), bone_warden (9). Low level, so a
##                 player meets them early, and the grind understated every one of those fights.
##
## 🔑 FOURTH INSTANCE OF THIS FILE'S OWN CLASS. Its comments already record `heal_amount`, `mp_amount`
## and (one commit ago) `hits`: an authored field the live engine reads and an arm here did not. Found
## by censusing keys BattleManager reads against keys this file reads, then checking reachability
## BEFORE writing anything — the order that matters, because the same census offered several keys
## whose only casters no grind can draw.
##
## Stacked on `the-grind-counts-every-hit`: both touch these two arms, and the drain heals off the
## ACCUMULATED volley so a multi-hit drain behaves as live does.

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


## max_mp matters — _resolve_ability RETURNS if the caster cannot pay mp_cost, and a no-op cast
## measures 0 damage against a working fix.
func _combatant(name: String, hp: int, cur_hp: int = -1) -> Combatant:
	var c := Combatant.new()
	c.initialize({"name": name, "max_hp": hp, "max_mp": 999,
		"attack": 30, "defense": 10, "magic": 30, "speed": 10})
	add_child_autofree(c)
	## AFTER add_child, not before: entering the tree restores full HP, so a pre-add assignment was
	## silently discarded and every drain measured 0 healing against a caster already at maximum.
	c.current_mp = c.max_mp
	c.current_hp = cur_hp if cur_hp >= 0 else hp
	return c


## Deltas on BOTH sides, never a returned figure: take_damage applies its own reduction, so the
## drain must be measured against what the TARGET actually lost.
func _cast(ability_id: String, caster: Combatant, target: Combatant) -> Dictionary:
	var t0: int = target.current_hp
	var c0: int = caster.current_hp
	_res._resolve_ability(caster, ability_id, [target])
	return {"dealt": t0 - target.current_hp, "healed": caster.current_hp - c0}


func test_a_drain_heals_the_caster_for_its_authored_share() -> void:
	var ab: Dictionary = _authored("soul_drain")
	if ab.is_empty():
		pass_test("JobSystem autoload unavailable")
		return
	var pct: float = float(ab.get("drain_percentage", 0))
	assert_gt(pct, 0.0, "CONTROL: soul_drain must still author a drain_percentage")
	## Hurt, so heal() has room — a full-HP caster absorbs nothing and the arm would pass on no drain.
	var caster := _combatant("Specter", 500, 100)
	var target := _combatant("Victim", 99999)
	var got: Dictionary = _cast("soul_drain", caster, target)
	assert_gt(int(got["dealt"]), 0, "CONTROL: the cast must land damage or there is nothing to drain")
	var expected: int = int(int(got["dealt"]) * pct / 100.0)
	gut.p("    soul_drain: pct=%d dealt=%d healed=%d expected=%d" % [pct, got["dealt"], got["healed"], expected])
	assert_eq(int(got["healed"]), expected,
		"soul_drain drains %d%% of damage dealt — %d of %d — and the grind healed %d" % [pct, expected, got["dealt"], got["healed"]])


## ⛔ THIS ARM USED TO ASSERT THE OPPOSITE, AND IT WAS WRONG. I wired the drain into BOTH damage arms
## and pinned it here. Live reads `drain_percentage` ONLY in `_execute_magic_ability`, so `dark_slash`
## (physical, 30%) heals its caster in NEITHER engine — and draining it here made the grind heal
## `bone_warden` and `shadow_knight`, both POOLED, where the game does not. Caught by @cowir-battle's
## 2d14d92d, whose distinction is the one I had missed: "is this key read at all" is a different
## question from "is it read on the path this ability takes", and my ledger only asked the first.
##
## A grind that is HARSHER than the game it simulates is the same defect as one that is softer. I
## stated that rule twice today and then failed to apply it to my own two previous hours.
func test_the_physical_arm_does_NOT_drain_because_live_does_not() -> void:
	var ab: Dictionary = _authored("dark_slash")
	if ab.is_empty():
		pass_test("JobSystem autoload unavailable")
		return
	assert_eq(str(ab.get("type", "")), "physical", "CONTROL: dark_slash must still take the physical arm")
	assert_gt(float(ab.get("drain_percentage", 0)), 0.0,
		"CONTROL: it must still AUTHOR a drain — that is what makes this a parity question rather than a no-op")
	var caster := _combatant("Bone Warden", 500, 100)
	var target := _combatant("Victim", 99999)
	var got: Dictionary = _cast("dark_slash", caster, target)
	assert_gt(int(got["dealt"]), 0, "CONTROL: the strike must land, or 'healed nothing' is vacuous")
	assert_eq(int(got["healed"]), 0,
		"the physical arm drained %d HP — live's drain lives in _execute_magic_ability, so this heals a pooled monster the game never heals" % got["healed"])


## The parity claim above is about LIVE's structure, so it is asserted against live rather than
## remembered. If BattleManager ever reads drain_percentage on the physical path, the grind must
## follow and this reds.
func test_live_still_reads_the_drain_on_the_magic_path_only() -> void:
	var live: String = GdSource.code_of("res://src/battle/BattleManager.gd")
	assert_gt(live.length(), 50000, "CONTROL: BattleManager was actually read")
	var at: int = live.find('ability.get("drain_percentage"')
	assert_gt(at, 0, "CONTROL: live must still read the key at all")
	var before: String = live.substr(0, at)
	var owner: int = before.rfind("func _execute_")
	var owner_line: String = before.substr(owner, 40)
	assert_true(owner_line.begins_with("func _execute_magic_ability"),
		"live now reads drain_percentage inside %s — the grind drains only on the magic path and must be taught to follow" % owner_line)


func test_a_non_draining_ability_heals_nobody() -> void:
	## The other direction. A drain applied unconditionally would heal the caster on every cast in the
	## game, which is a far worse bug than the one being fixed.
	var ab: Dictionary = _authored("fire")
	if ab.is_empty():
		pass_test("JobSystem autoload unavailable")
		return
	assert_false(ab.has("drain_percentage"), "CONTROL: fire must author no drain, or it cannot police the default")
	var caster := _combatant("Mage", 500, 100)
	var target := _combatant("Victim", 99999)
	var got: Dictionary = _cast("fire", caster, target)
	assert_gt(int(got["dealt"]), 0, "CONTROL: fire must land damage")
	assert_eq(int(got["healed"]), 0, "an ability authoring no drain must heal its caster nothing")


func test_a_full_health_drainer_is_not_healed_past_its_maximum() -> void:
	## heal() clamps; the arm exists so the expectation above is not quietly read as "caster gains
	## exactly pct" in a case where it cannot.
	var caster := _combatant("Specter", 500)
	var target := _combatant("Victim", 99999)
	var got: Dictionary = _cast("soul_drain", caster, target)
	assert_eq(int(got["healed"]), 0, "a caster already at max HP gains nothing")
	assert_eq(caster.current_hp, caster.max_hp, "and is not pushed above its maximum")


func test_a_multi_hit_drain_would_drain_the_whole_volley() -> void:
	## Composition with the hits loop this stacks on: the drain reads the ACCUMULATED damage, so if a
	## multi-hit ability ever authors a drain it heals off the volley rather than the last swing.
	## No ability authors both today — this pins the wiring, and says so rather than implying coverage.
	var code: String = GdSource.code_of(SRC)
	assert_true(code.contains("_drain_to(caster, dealt, drain_pct"),
		"the magic arm must drain from the accumulated volley total")
	## And the physical arm must NOT, because live's drain is on the magic path. Asserted as an absence
	## so re-adding it reds, rather than being left as a fact about today's file.
	assert_false(code.contains("_drain_to(caster, dmg"),
		"the physical arm drains again — live reads drain_percentage only in _execute_magic_ability")


func test_every_authored_drainer_is_reachable_in_a_grind() -> void:
	## Reachability, derived. If no pooled monster and no job can cast a drain, this fix is dead weight
	## and the arm says so rather than leaving it on faith.
	var es: Node = get_node_or_null("/root/EncounterSystem")
	if es == null or not ("enemy_pools" in es):
		pass_test("EncounterSystem unavailable")
		return
	var abilities: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/abilities.json"))
	var monsters: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/monsters.json"))
	var jobs_txt: String = FileAccess.get_file_as_string("res://data/jobs.json")
	var drains: Array = []
	for aid in abilities.keys():
		if float((abilities[aid] as Dictionary).get("drain_percentage", 0)) > 0.0:
			drains.append(aid)
	assert_gt(drains.size(), 0, "CONTROL: abilities.json must still author a drain")

	var pooled: Dictionary = {}
	for region in es.enemy_pools.keys():
		for entry in es.enemy_pools[region]:
			pooled[str(entry.get("id", entry) if entry is Dictionary else entry)] = true
	var casters: Array = []
	for mid in monsters.keys():
		if not pooled.has(mid):
			continue
		for aid in (monsters[mid] as Dictionary).get("abilities", []):
			if drains.has(aid):
				casters.append("%s/%s" % [mid, aid])
	var player_side: Array = []
	for aid in drains:
		if jobs_txt.contains('"%s"' % aid):
			player_side.append(aid)
	gut.p("    pooled drainers: %s" % str(casters))
	gut.p("    player-castable: %s" % str(player_side))
	assert_gt(casters.size(), 0, "no pooled monster drains any more — re-justify this wiring rather than keeping it on faith")
	assert_gt(player_side.size(), 0, "no job teaches a drain any more — the player-side half of this fix is unreachable")
