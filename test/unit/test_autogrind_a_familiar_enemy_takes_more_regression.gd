extends GutTest

const GdSource := preload("res://test/unit/helpers/gd_source.gd")
const ResolverScript = preload("res://src/autogrind/HeadlessBattleResolver.gd")
const GRIND := "res://src/autogrind/HeadlessBattleResolver.gd"

## returned_sword's "Familiar Weight" — +10% damage against any enemy the party has SEEN or DEFEATED,
## or that lives in the sword's own static ledger — did nothing in a grind.
##
## 🔑 INVISIBLE TO THIS LANE'S GEAR CENSUS, AND THAT IS THE FINDING. The bonus is a
## `special_effects` key; the seed list is a TOP-LEVEL equipment field. My census walks
## special_effects, so it could see one half of a two-part mechanism and never the other. Found by
## applying @cowir-battle's "the predicate is a corpus" to my own instrument rather than to code.
##
## ⚠️ It is worth MORE in a grind than in normal play, which is the opposite of how it reads: a grind
## fills the bestiary faster than anything, so `is_seen` is true of nearly every pooled monster after
## the first few battles. The seed list exists so the FIRST encounter already benefits.
##
## Live applies it from two sites (:4498 basic attack, :4915 physical ability) and so does this file —
## the one-site mistake is what the dodge fix an hour earlier was written for.

var _res


func before_each() -> void:
	_res = ResolverScript.new()


func _fighter(name: String) -> Combatant:
	var c := Combatant.new()
	c.initialize({"name": name, "max_hp": 999999, "max_mp": 500,
		"attack": 60, "defense": 10, "magic": 40, "speed": 10})
	add_child_autofree(c)
	c.current_hp = c.max_hp
	c.current_mp = c.max_mp
	return c


## An enemy carrying the monster_type meta GameLoop:5744 sets before handing the party to the
## resolver — without it the whole mechanism is inert, in both engines.
func _enemy(name: String, mtype: String) -> Combatant:
	var c := _fighter(name)
	if mtype != "":
		c.set_meta("monster_type", mtype)
	return c


## Median damage over n swings, so the ±15% damage roll cannot decide the comparison.
func _median_hit(attacker: Combatant, target: Combatant, n: int) -> float:
	var rolls: Array = []
	for i in n:
		target.current_hp = target.max_hp
		var d: int = _res._resolve_attack(attacker, target)
		if d > 0:
			rolls.append(d)
	rolls.sort()
	return float(rolls[rolls.size() / 2]) if rolls.size() > 0 else 0.0


func test_the_sword_and_its_seed_are_still_authored() -> void:
	var eq: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/equipment.json"))
	var sword: Dictionary = (eq.get("weapons", {}) as Dictionary).get("returned_sword", {})
	assert_almost_eq(float((sword.get("special_effects", {}) as Dictionary).get("familiar_weight_bonus", 0.0)), 0.1, 0.001,
		"returned_sword no longer authors familiar_weight_bonus 0.1")
	var seed: Variant = sword.get("familiar_weight_static_seed", [])
	assert_true(seed is Array and (seed as Array).size() > 0,
		"returned_sword no longer carries a familiar_weight_static_seed — the TOP-LEVEL field this lane's census could not see")
	assert_true((seed as Array).has("slime"),
		"the seed no longer contains slime, which the bands below use as a known-familiar type")


func test_a_seeded_enemy_takes_more_from_the_returned_sword() -> void:
	## slime is in the sword's static ledger, so the bonus applies on the FIRST encounter with no
	## bestiary history at all — which is what the seed exists for.
	var armed := _fighter("Armed")
	armed.equipped_weapon = "returned_sword"
	var bare := _fighter("Bare")
	var seeded_a := _enemy("SlimeA", "slime")
	var seeded_b := _enemy("SlimeB", "slime")
	var with_sword: float = _median_hit(armed, seeded_a, 240)
	var without: float = _median_hit(bare, seeded_b, 240)
	gut.p("    vs a SEEDED type — returned_sword %.0f, unarmed-of-that-effect %.0f" % [with_sword, without])
	assert_gt(without, 0.0, "CONTROL: the baseline must land hits, or the ratio is meaningless")
	assert_gt(with_sword, without,
		"returned_sword dealt no more to a seeded enemy — familiar_weight_bonus is authored on it and the grind is not reading it")


func test_an_unfamiliar_unseeded_enemy_takes_no_bonus() -> void:
	## ⛔ THE ARM THAT STOPS THIS BEING A FLAT DAMAGE BUFF. A type absent from the seed AND unseen in
	## the bestiary must take normal damage — otherwise the sword is +10% against everything and the
	## whole discovery mechanic is decoration.
	var armed := _fighter("Armed")
	armed.equipped_weapon = "returned_sword"
	var bs = _res._get_autoload("BestiarySystem")
	var mtype: String = "zz_unfamiliar_probe_type"
	if bs and bs.has_method("is_seen"):
		assert_false(bs.is_seen(mtype), "CONTROL: the probe type must be genuinely unseen, or this arm proves nothing")
	var unknown_a := _enemy("UnknownA", mtype)
	var unknown_b := _enemy("UnknownB", mtype)
	var bare := _fighter("Bare")
	var with_sword: float = _median_hit(armed, unknown_a, 240)
	var without: float = _median_hit(bare, unknown_b, 240)
	gut.p("    vs an UNFAMILIAR type — returned_sword %.0f, baseline %.0f (must match)" % [with_sword, without])
	assert_almost_eq(with_sword, without, without * 0.06,
		"returned_sword boosted damage against an enemy the party has never seen and the sword does not know — the bestiary/seed gate is not being applied")


func test_an_enemy_with_no_monster_type_is_left_alone() -> void:
	## GameLoop:5744 sets the meta and guards on it being non-empty, so a metaless combatant is
	## reachable. Live returns the damage unmodified in that case; so must this.
	var armed := _fighter("Armed")
	armed.equipped_weapon = "returned_sword"
	var metaless_a := _enemy("MetalessA", "")
	var metaless_b := _enemy("MetalessB", "")
	var bare := _fighter("Bare")
	var with_sword: float = _median_hit(armed, metaless_a, 240)
	var without: float = _median_hit(bare, metaless_b, 240)
	gut.p("    vs a METALESS combatant — returned_sword %.0f, baseline %.0f (must match)" % [with_sword, without])
	assert_almost_eq(with_sword, without, without * 0.06,
		"the bonus applied to a combatant carrying no monster_type — live returns damage unmodified there")


func test_the_bonus_has_the_two_call_sites_live_has() -> void:
	## Structural, and it is the mistake this lane made an hour ago on the dodge: live applies Familiar
	## Weight on the basic attack AND on a physical ability. One site is half a fix.
	var code: String = GdSource.code_of(GRIND)
	assert_gt(code.length(), 10000, "CONTROL: the resolver was actually read")
	var calls: int = code.count("_apply_familiar_weight_bonus(") - 1   ## minus its own declaration
	gut.p("    _apply_familiar_weight_bonus call sites: %d (live has 2)" % calls)
	assert_eq(calls, 2,
		"Familiar Weight is no longer applied from exactly two sites — live applies it at :4498 (basic attack) and :4915 (physical ability)")


func test_the_seed_is_read_from_a_top_level_field_not_special_effects() -> void:
	## ⚠️ THE CENSUS LESSON, pinned. If someone "tidies" the seed into special_effects, the gear census
	## would start seeing it and this read would break — and the failure would look like the sword
	## losing its ledger rather than like a schema move.
	var code: String = GdSource.code_of(GRIND)
	assert_true(code.contains('entry.get("familiar_weight_static_seed", [])'),
		"the seed is no longer read from the equipment entry's TOP LEVEL — live reads it there at :3163, and it is the half a special_effects census cannot see")
	var eq: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/equipment.json"))
	var sword: Dictionary = (eq.get("weapons", {}) as Dictionary).get("returned_sword", {})
	assert_false((sword.get("special_effects", {}) as Dictionary).has("familiar_weight_static_seed"),
		"the seed moved INTO special_effects — update the reader, and note that the gear census can now see it")
