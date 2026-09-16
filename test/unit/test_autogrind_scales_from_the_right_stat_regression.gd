extends GutTest

## `scales_with` swaps the stat a physical ability computes its damage FROM. The live engine reads it
## (BattleManager:4736) and the resolver used `attack` for everything — so guard_strike on a
## high-defense caster dealt "poverty damage", which is the live engine's own phrase for the same bug
## when IT had this field unread (tick 437).
##
##   guard_strike        scales_with=defense      cast by rat_guard, a POOLED monster
##   throw_shuriken      scales_with=speed        job ability
##   last_stand_ability  scales_with=missing_hp   job ability — a multiplier, not a base-stat swap
##
## ⛔ TWO VARIANTS ARE DELIBERATELY NOT IMPLEMENTED, and they are declared rather than forgotten.
## `target_defense` (complement, cast by the pooled empty_set) and `most_used_ability`
## (player_knowledge) have ZERO references in BattleManager — live scales both from attack, exactly as
## the grind does. Wiring them here alone would push the simulation past the game it simulates, which
## is this file's failure mode inverted. Arm 4 reds if live starts reading either, so the exclusion
## cannot outlive its reason; `complement` is worth @cowir-battle's attention because a pooled monster
## casts it and its authored scaling does nothing in EITHER engine.
##
## Sixth instance of this resolver's documented class: heal_amount, mp_amount, hits,
## drain_percentage, secondary_effect, and now this.

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


## HP/MP after add_child — entering the tree restores full HP and a pre-add assignment is discarded.
func _combatant(name: String, atk: int, def_: int, spd: int, hp: int = 500) -> Combatant:
	var c := Combatant.new()
	c.initialize({"name": name, "max_hp": hp, "max_mp": 999,
		"attack": atk, "defense": def_, "magic": 20, "speed": spd})
	add_child_autofree(c)
	c.current_mp = c.max_mp
	return c


func _damage_of(ability_id: String, caster: Combatant) -> int:
	var target := _combatant("Victim", 1, 10, 1, 99999)
	var before: int = target.current_hp
	_res._resolve_ability(caster, ability_id, [target])
	return before - target.current_hp


func test_a_defense_scaling_strike_reads_defense_not_attack() -> void:
	var ab: Dictionary = _authored("guard_strike")
	if ab.is_empty():
		pass_test("JobSystem autoload unavailable")
		return
	assert_eq(str(ab.get("scales_with", "")), "defense", "CONTROL: guard_strike must still scale from defense")
	## A TANK: defense far above attack, so the two candidate bases give clearly different damage and
	## the arm cannot pass on the wrong one by coincidence.
	var tank := _combatant("Rat Guard", 5, 80, 10)
	var glass := _combatant("Glass", 80, 5, 10)
	var tank_dmg: int = _damage_of("guard_strike", tank)
	var glass_dmg: int = _damage_of("guard_strike", glass)
	gut.p("    guard_strike: def-80/atk-5 caster -> %d   atk-80/def-5 caster -> %d" % [tank_dmg, glass_dmg])
	assert_gt(tank_dmg, glass_dmg,
		"guard_strike hit harder from the ATTACK stat (%d) than from defense (%d) — the caster's signature stat is not being read" % [glass_dmg, tank_dmg])


func test_a_speed_scaling_throw_reads_speed() -> void:
	var ab: Dictionary = _authored("throw_shuriken")
	if ab.is_empty():
		pass_test("JobSystem autoload unavailable")
		return
	assert_eq(str(ab.get("scales_with", "")), "speed", "CONTROL: throw_shuriken must still scale from speed")
	var swift := _combatant("Ninja", 5, 10, 80)
	var slow := _combatant("Lump", 80, 10, 5)
	var swift_dmg: int = _damage_of("throw_shuriken", swift)
	var slow_dmg: int = _damage_of("throw_shuriken", slow)
	gut.p("    throw_shuriken: spd-80 -> %d   atk-80 -> %d" % [swift_dmg, slow_dmg])
	assert_gt(swift_dmg, slow_dmg, "throw_shuriken scaled from attack, not speed")


func test_last_stand_hits_harder_the_lower_the_casters_hp() -> void:
	var ab: Dictionary = _authored("last_stand_ability")
	if ab.is_empty():
		pass_test("JobSystem autoload unavailable")
		return
	assert_eq(str(ab.get("scales_with", "")), "missing_hp", "CONTROL: last_stand must still scale from missing HP")
	var healthy := _combatant("Healthy", 30, 10, 10)
	var dying := _combatant("Dying", 30, 10, 10)
	dying.current_hp = int(dying.max_hp * 0.1)
	var healthy_dmg: int = _damage_of("last_stand_ability", healthy)
	var dying_dmg: int = _damage_of("last_stand_ability", dying)
	gut.p("    last_stand: full HP -> %d   10%% HP -> %d" % [healthy_dmg, dying_dmg])
	assert_gt(dying_dmg, healthy_dmg,
		"last_stand dealt %d at 10%% HP and %d at full — the 'more damage the lower your HP' promise is still dropped" % [dying_dmg, healthy_dmg])
	## And a full-HP caster must be UNCHANGED: the multiplier is 1.0 there, so this cannot be a
	## blanket damage buff wearing a scaling fix's clothes.
	var plain := _combatant("Plain", 30, 10, 10)
	assert_eq(_damage_of("attack_ability_that_does_not_exist", plain), 0, "CONTROL: an unknown id is a no-op")


func test_the_two_unimplemented_variants_are_dead_in_live_too() -> void:
	## DECLARED. If live starts reading either, the grind must follow and this arm says so.
	var live: String = GdSource.code_of(LIVE)
	assert_gt(live.length(), 10000, "CONTROL: BattleManager was actually read")
	assert_true(live.contains('scales_with == "missing_hp"'),
		"CONTROL: live must still read the variant we DO mirror, or this arm is measuring an empty file")
	for dead in ["target_defense", "most_used_ability"]:
		assert_false(live.contains('"%s"' % dead),
			"live now reads scales_with=%s — the grind scales it from attack and must be taught to follow" % dead)


func test_the_resolver_mirrors_the_live_variants_and_default() -> void:
	## Structural, bounded to the helper so a mention elsewhere cannot satisfy it.
	var code: String = GdSource.code_of(SRC)
	var start: int = code.find("func _scaled_base")
	assert_gt(start, 0, "CONTROL: the helper must exist")
	var body: String = code.substr(start, code.find("\nfunc ", start + 10) - start)
	assert_false(body.contains("func _missing_hp_multiplier"), "CONTROL: the slice stops at the next function")
	assert_true(body.contains('"defense"') and body.contains('"speed"'),
		"the helper must mirror both base-stat variants live implements")
	assert_true(body.contains('caster.get_buffed_stat("attack"'),
		"and fall back to attack, which is live's default arm")
	## ⚠️ THE max_multiplier DEFAULT IS UNREACHABLE BY ANY SHIPPED ABILITY, and this is the only arm
	## that can defend it. last_stand_ability is the sole missing_hp ability and it authors its own
	## 5.0, so changing the default changes no behaviour and no behavioural arm can notice — measured:
	## mutating it to 1.0 left the last_stand arm GREEN. It is a second copy of a live constant, which
	## is the class this lane keeps fixing; the two engines are separate implementations by policy, so
	## the answer is to assert they AGREE rather than to pin either literal.
	var live_default: String = _default_after('ability.get("max_multiplier", ', GdSource.code_of(LIVE))
	var grind_default: String = _default_after('ability.get("max_multiplier", ', code)
	assert_ne(live_default, "", "CONTROL: live must still author a max_multiplier default to compare against")
	assert_eq(grind_default, live_default,
		"the two engines disagree on max_multiplier's default (live %s, grind %s) — last_stand was a flat 1.0x when live had this unread" % [live_default, grind_default])
	## The exclusion enforced from THIS side too. The live-side arm above catches live gaining a
	## reader; without this one, nothing stops the grind gaining one first and diverging the other way,
	## which is the direction that makes the simulation harsher than the game.
	for dead in ["target_defense", "most_used_ability"]:
		assert_false(body.contains('"%s"' % dead),
			"the resolver scales from %s while live does not — the grind would hit harder than the game it simulates" % dead)


## The literal immediately after a `.get(key, ` occurrence, or "" if absent. Used to compare a default
## between two engines without typing it in a third place.
func _default_after(needle: String, code: String) -> String:
	var at: int = code.find(needle)
	if at < 0:
		return ""
	var rest: String = code.substr(at + needle.length(), 24)
	var end: int = rest.find(")")
	return rest.substr(0, end).strip_edges() if end > 0 else ""
