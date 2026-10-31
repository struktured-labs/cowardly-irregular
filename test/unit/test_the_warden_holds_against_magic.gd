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


# ── the generalizing guard ──────────────────────────────────────────

func test_every_lens_stat_mod_key_survives_both_gates() -> void:
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
