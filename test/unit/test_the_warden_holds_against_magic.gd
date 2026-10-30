extends GutTest

## The Warden Lens mitigated the PHYSICAL half only while every wall boss deals AoE magic, so the
## one defensive lens in the game was blind to the damage that actually kills the party. The key it
## needed was dropped at TWO gates: LensSystem.NEUTRAL_MODS, and again in the seed dict
## _compose_lens_mods filters against. The same key on a PASSIVE works at both, because
## _compose_mod creates missing _multiplier keys -- so the two vocabularies had silently drifted.

const LENS_DATA := "res://data/lenses.json"

var _owned_before: Array = []


func before_each() -> void:
	_owned_before = GameState.owned_lenses.duplicate()


func after_each() -> void:
	## Lens state is global; a leaked equip buffs an unrelated test's combatant.
	for who in ["fighter", "cleric", "mage", "rogue", "bard"]:
		if LensSystem.get_equipped(who) != "":
			LensSystem.unequip_lens(who)
	GameState.owned_lenses = _owned_before.duplicate()


func _combatant(who: String) -> Combatant:
	var c := Combatant.new()
	## IN THE TREE, or recalculate_stats' has_node("/root/PassiveSystem") is false for an orphan
	## and the whole passive/lens block is skipped -- the effect arm then measures nothing.
	add_child_autofree(c)
	c.combatant_name = who
	## 5 is the default and int(5 * 1.08) truncates back to 5, so the tilt would be invisible at
	## base: the effect arms need a stat a real W1 character actually carries.
	c.base_magic_defense = 100
	c.base_defense = 100
	return c


func _equip(who: String, axis: String) -> void:
	GameState.owned_lenses.append(axis)
	LensSystem.equip_lens(who.to_lower(), axis)


# ── the seam ────────────────────────────────────────────────────────

func test_the_warden_raises_magic_defense_in_the_shared_total() -> void:
	var c := _combatant("Fighter")
	var before: Dictionary = PassiveSystem.get_passive_mods(c)
	_equip("Fighter", "warden")
	var after: Dictionary = PassiveSystem.get_passive_mods(c)
	assert_eq(float(before["magic_defense_multiplier"]), 1.0,
		"neutral before the lens is equipped")
	assert_gt(float(after["magic_defense_multiplier"]), 1.0,
		"the Warden's magic tilt must reach the total every consumer reads")


func test_a_character_without_the_lens_keeps_neutral_magic_defense() -> void:
	var c := _combatant("Cleric")
	_equip("Fighter", "warden")
	var mods: Dictionary = PassiveSystem.get_passive_mods(c)
	assert_eq(float(mods["magic_defense_multiplier"]), 1.0,
		"a Lens on the Fighter must not harden the Cleric")


# ── the effect, not the bookkeeping ─────────────────────────────────

func test_the_warden_actually_reduces_a_magical_hit() -> void:
	## Through the real pipeline: recalculate_stats applies the mod to the stat, and
	## damage_preview's magical branch divides by it. No re-implementation of the formula.
	var bare := _combatant("Cleric")
	bare.recalculate_stats()
	var bare_mdef: int = bare.magic_defense
	var bare_hit: int = bare.damage_preview(200, true)

	var warded := _combatant("Fighter")
	_equip("Fighter", "warden")
	warded.recalculate_stats()

	assert_gt(warded.magic_defense, bare_mdef,
		"the tilt must land on the magic_defense STAT, not just in a mods dict")
	assert_lt(warded.damage_preview(200, true), bare_hit,
		"and a magical hit must actually land for less on the warded character")


func test_the_physical_half_is_exactly_as_it_was() -> void:
	## Pins the state this change did NOT touch: the Warden's steel was already 1.08 and must not
	## have moved, or a magic fix would read as a blanket defence buff.
	var raw = JSON.parse_string(FileAccess.get_file_as_string(LENS_DATA))
	var warden: Dictionary = raw["lenses"]["warden"]["stat_mods"]
	assert_eq(float(warden["defense_multiplier"]), 1.08, "physical tilt unchanged")
	assert_eq(float(warden["magic_defense_multiplier"]), 1.08,
		"and the magic half matches it rather than inventing a second number")


# ── the claim the comment now rests on ──────────────────────────────

func test_no_warden_deals_aoe_magic_so_the_comment_stays_true() -> void:
	## The rationale first shipped with this fix said "every wall boss deals AoE magic". It was
	## wrong and @cowir-adhoc measured it: the warden AoE (masterite_endurance_test) is PHYSICAL and
	## its magic (masterite_judgment) is single_enemy. This reds if that flips, which is exactly
	## when LensSystem's comment and lenses.json's note need re-reading -- not on a magnitude.
	var ab = JSON.parse_string(FileAccess.get_file_as_string("res://data/abilities.json"))
	var mo = JSON.parse_string(FileAccess.get_file_as_string("res://data/monsters.json"))
	var abil: Dictionary = ab.get("abilities", ab)
	var mons: Dictionary = mo.get("monsters", mo)
	var wardens := 0
	for mid in mons.keys():
		if not str(mid).begins_with("masterite_warden"):
			continue
		wardens += 1
		for aid in (mons[mid] as Dictionary).get("abilities", []):
			var a: Dictionary = abil.get(aid, {})
			var is_aoe_magic: bool = str(a.get("type", "")) == "magic" \
				and str(a.get("target_type", "")).contains("all")
			assert_false(is_aoe_magic,
				"%s now carries AoE magic (%s) — re-read LensSystem's magic_defense_multiplier comment and lenses.json's note, which both state no warden does" % [mid, aid])
	assert_gt(wardens, 0, "the derivation must reach some wardens, or it certifies nothing")


# ── the generalizing guard ──────────────────────────────────────────

func test_every_lens_stat_mod_key_survives_the_first_two_gates() -> void:
	## DERIVED from the data file, so this reds for any FUTURE lens key that nothing consumes --
	## which is the defect class that made the Warden's magic tilt impossible to author at all.
	var raw = JSON.parse_string(FileAccess.get_file_as_string(LENS_DATA))
	assert_true(raw is Dictionary, "lenses.json must parse")
	var seed: Dictionary = PassiveSystem.get_passive_mods(_combatant("Rogue"))
	var checked := 0
	for axis in (raw["lenses"] as Dictionary).keys():
		var mods = (raw["lenses"][axis] as Dictionary).get("stat_mods", {})
		for key in (mods as Dictionary).keys():
			checked += 1
			assert_true(LensSystem.NEUTRAL_MODS.has(key),
				"lens '%s' declares '%s', which LensSystem.NEUTRAL_MODS drops with a warning" % [axis, key])
			assert_true(seed.has(key),
				"lens '%s' declares '%s', which _compose_lens_mods drops: get_passive_mods' seed lacks it" % [axis, key])
	assert_gt(checked, 0, "the derivation must actually reach some keys, or it certifies nothing")


## Gate 3 is a SEPARATE list, so a key can pass both gates above and still be inert -- the very
## defect this file was written for, reproduced one gate further down. @cowir-adhoc found the hole.
## Non-stat keys are allowed through only by NAMING their consumer: the explanation is the fix, and
## you cannot silence this green, only explain it green.
const NON_STAT_MULTIPLIERS := {
	"mp_cost_multiplier": "not a stat — read at the point of MP spend",
	"healing_multiplier": "not a stat — read in Combatant.heal()",
}


func test_every_multiplier_in_neutral_mods_reaches_gate_three() -> void:
	var moddable: Array = Combatant.MODDABLE_STATS
	assert_gt(moddable.size(), 0, "MODDABLE_STATS must resolve, or this arm certifies nothing")
	var checked := 0
	for key in LensSystem.NEUTRAL_MODS.keys():
		var k := str(key)
		if not k.ends_with("_multiplier"):
			continue   # crit_chance / evasion are additive and read at the point of use
		checked += 1
		if NON_STAT_MULTIPLIERS.has(k):
			assert_false(str(NON_STAT_MULTIPLIERS[k]).is_empty(),
				"%s is exempt from gate 3 but names no consumer" % k)
			continue
		var stat := k.substr(0, k.length() - "_multiplier".length())
		assert_true(moddable.has(stat),
			"NEUTRAL_MODS declares '%s' but Combatant.MODDABLE_STATS has no '%s', so recalculate_stats never applies it — the lens tilt is INERT. Add the stat to MODDABLE_STATS, or exempt the key in NON_STAT_MULTIPLIERS naming its real consumer." % [k, stat])
	assert_gt(checked, 0, "no multiplier keys reached — the derivation is broken, not clean")
