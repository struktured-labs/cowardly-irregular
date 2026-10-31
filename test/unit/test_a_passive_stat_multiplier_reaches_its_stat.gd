extends GutTest

## `damage_reduction` says "Take 15% less damage from all sources" and covered exactly ONE source.
##
## Its only stat_mod was `defense_multiplier`, and BattleManager:6391 reads `magic_defense` for a
## magical hit and `defense` for a physical one — so the passive was inert against every dragon and
## both finales, which are precisely the magic walls. Same shape as Protect before Shell existed,
## which BattleManager:6960 records in its own words: "Protect gave no magic mitigation and nothing
## raised magic_defense at all". Equipping it and reading the description, a player gets a defensive
## option that does nothing in the fights that kill them.
##
## 🔑 THE CAUSE WAS A HAND-LISTED SET, AND THE FIX WAS ALREADY WRITTEN TWICE IN THE SAME FUNCTION.
## recalculate_stats has three stat blocks. The secondary-job block and the equipment block both
## derive from MODDABLE_STATS and both carry a comment saying why — "a hand-listed six silently omits
## whatever it does not name". The passive block between them was the last hand-listed one, and
## `magic_defense` was exactly what it omitted. So a passive could declare magic_defense_multiplier
## and be silently inert, which is why fixing the DATA alone would not have held.
##
## ⚠️ What is NOT a defect, checked before claiming it: `crit_chance`, `crit_damage_bonus`, `evasion`,
## `mp_cost_multiplier` and `steal_chance` are declared by passives and never touched by
## recalculate_stats — correctly, because they are not stats. Each is read at its point of use
## (BattleManager:6660 · JobSystem:748 · BattleManager:6550 · PassiveSystem:434), and
## healing_multiplier in heal(). The derived arm below is scoped to MODDABLE_STATS for that reason:
## widened to every declared key it would report five working mechanics as holes.
##
## iron_skin ("+25% defense") and glass_cannon ("-40% defense") name DEFENSE and stay physical-only
## on purpose. damage_reduction is the one whose own text promises both, so it is the only one changed.

const COMBATANT_PATH := "res://src/battle/Combatant.gd"


func _passive_system() -> Node:
	return Engine.get_main_loop().root.get_node_or_null("PassiveSystem")


## ⛔ `passives` MUST be typed. equipped_passives is Array[String]; assigning a plain Array is a
## SCRIPT ERROR that ABORTS THIS FUNCTION, so _make returned null and every caller's later lines
## never ran. Caught only because ONE arm touched the result before its first assert and scored
## Risky (EC=4). The other four had an assert above the call, so they went GREEN while measuring
## nothing — the rung-3 silent case, in the file written to prove a stat moves.
## ⚠️ base_* RATHER THAN initialize(). recalculate_stats:1808-1814 RESETS every stat from base_*
## before applying anything, so values handed to initialize() are discarded and the subject arrives
## with engine defaults — magic_defense 5, where int(5 * 1.15) truncates back to 5 and a working
## multiplier is indistinguishable from an inert one. Magnitudes are chosen so a 15% change survives
## int(): 400 -> 460. A job is deliberately NOT assigned, because job mods REPLACE base_* (:1820).
func _make(passives: Array[String]) -> Combatant:
	var c: Combatant = (load(COMBATANT_PATH) as GDScript).new()
	c.combatant_name = "Subject"
	c.base_max_hp = 2000
	c.base_max_mp = 400
	c.base_attack = 300
	c.base_defense = 400
	c.base_magic = 300
	c.base_magic_defense = 400
	c.base_speed = 120
	add_child_autofree(c)
	var typed: Array[String] = []
	for p in passives:
		typed.append(str(p))
	c.equipped_passives = typed
	c.recalculate_stats()
	assert_not_null(c, "FLOOR: _make must hand back a live Combatant — a null here aborts its caller")
	return c


## stat key -> {passive, value}, read off the live passive table rather than retyped. Only
## MODDABLE_STATS keys, because only those are stats recalculate_stats owns.
func _declared_stat_multipliers() -> Dictionary:
	var ps := _passive_system()
	if ps == null:
		return {}
	var out := {}
	for pid in ps.passives:
		var mods: Dictionary = (ps.passives[pid] as Dictionary).get("stat_mods", {})
		for key in mods:
			for stat in Combatant.MODDABLE_STATS:
				if str(key) == str(stat) + "_multiplier" and float(mods[key]) != 1.0:
					out[str(key)] = {"passive": str(pid), "value": float(mods[key]), "stat": str(stat)}
	return out


func test_damage_reduction_declares_both_defences() -> void:
	var ps := _passive_system()
	if ps == null:
		pending("PassiveSystem autoload required")
		return
	var mods: Dictionary = (ps.passives.get("damage_reduction", {}) as Dictionary).get("stat_mods", {})
	assert_eq(float(mods.get("defense_multiplier", 1.0)), 1.15,
		"the physical half, unchanged by this fix")
	assert_eq(float(mods.get("magic_defense_multiplier", 1.0)), 1.15,
		("the half that was missing. Its description promises 'all sources' and BattleManager:6391 " +
		 "reads magic_defense for magical hits, so without this key the passive is inert in every " +
		 "fight the endgame is made of"))


## ⛔ THE ARM THE FIX EXISTS FOR.
func test_damage_reduction_actually_raises_magic_defense() -> void:
	if _passive_system() == null:
		pending("PassiveSystem autoload required")
		return
	var bare := _make([])
	var armoured := _make(["damage_reduction"])
	assert_gt(armoured.magic_defense, bare.magic_defense,
		("damage_reduction left magic_defense at %d, same as an unequipped party. Its own text says " +
		 "'from all sources'; magical damage divides by magic_defense, so an unmoved value is a " +
		 "defensive passive that does nothing against the dragons and both finales") % bare.magic_defense)
	assert_gt(armoured.defense, bare.defense,
		"CONTROL: the physical half must still work, or this is a swap rather than a fix")


## The derived loop must apply only the keys a passive DECLARES. speed_boost declares a speed
## multiplier and nothing else, so it is the discriminator: its speed must move while both defences
## stay put. An earlier version of this arm compared bare against itself through an `if ... in`
## fallback — a clause that cannot fail, and it would have passed a loop that multiplied everything.
func test_the_loop_applies_only_what_a_passive_declares() -> void:
	if _passive_system() == null:
		pending("PassiveSystem autoload required")
		return
	var ps := _passive_system()
	var mods: Dictionary = (ps.passives.get("speed_boost", {}) as Dictionary).get("stat_mods", {})
	assert_gt(float(mods.get("speed_multiplier", 1.0)), 1.0,
		"CONTROL: speed_boost must declare a speed multiplier, or it cannot discriminate here")
	assert_false(mods.has("defense_multiplier"),
		"CONTROL: speed_boost must declare NO defence multiplier for this arm to mean anything")
	assert_false(mods.has("magic_defense_multiplier"), "CONTROL: nor a magic one")

	var bare := _make([])
	var swift := _make(["speed_boost"])
	assert_gt(swift.speed, bare.speed, "the declared key must land, or the loop is not running at all")
	assert_eq(swift.defense, bare.defense,
		"an undeclared stat must not move — the derived loop must read keys, not multiply every stat")
	assert_eq(swift.magic_defense, bare.magic_defense,
		"likewise magic_defense: this fix adds a stat to the loop, not a buff to everyone")


## ⛔ THE STRUCTURAL ARM, AND THE REASON THE DATA FIX ALONE WOULD NOT HOLD. Derived from the live
## passive table crossed with MODDABLE_STATS, so a passive declaring a multiplier for a stat the
## block forgets reds here instead of shipping inert. A hand-listed set is what caused the defect.
func test_every_declared_stat_multiplier_reaches_its_stat() -> void:
	if _passive_system() == null:
		pending("PassiveSystem autoload required")
		return
	var declared := _declared_stat_multipliers()
	assert_gt(declared.size(), 5,
		("ANTI-VACUITY: only %d stat multipliers derived from the passive table — an empty or thin " +
		 "derivation makes every assertion below free") % declared.size())
	var bare := _make([])
	var inert: Array = []
	for key in declared:
		var d: Dictionary = declared[key]
		var typed_one: Array[String] = [str(d["passive"])]
		var subject := _make(typed_one)
		var before: int = int(bare.get(str(d["stat"])))
		var after: int = int(subject.get(str(d["stat"])))
		var moved_right: bool = after > before if float(d["value"]) > 1.0 else after < before
		if not moved_right:
			inert.append("%s (%s declares %.2f): %s stayed %d -> %d" % [
				key, str(d["passive"]), float(d["value"]), str(d["stat"]), before, after])
	inert.sort()
	assert_eq(inert, [],
		("a passive declares a multiplier for a MODDABLE stat and recalculate_stats does not apply " +
		 "it — the equip button makes a promise the combatant never receives: %s") % str(inert))


## Without this, the arm above is satisfied by a loop that moves every stat for any reason.
func test_a_fabricated_multiplier_moves_nothing() -> void:
	if _passive_system() == null:
		pending("PassiveSystem autoload required")
		return
	var declared := _declared_stat_multipliers()
	assert_false(declared.has("zzz_no_such_stat_multiplier"),
		"CONTROL: a fabricated key must not appear in the derivation")
	var bare := _make([])
	var fake := _make(["zzz_no_such_passive"])
	assert_eq(fake.magic_defense, bare.magic_defense,
		"CONTROL: an unknown passive id must change nothing, or the comparison above proves nothing")
	assert_eq(fake.defense, bare.defense, "CONTROL: likewise for physical defence")
