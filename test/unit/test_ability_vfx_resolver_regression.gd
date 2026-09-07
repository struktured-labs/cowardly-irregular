extends GutTest

## The precedence chain, pinned on synthetic dicts so it does not move when abilities.json changes.
##
##   1 authored ability.vfx.type
##   2 the legacy ~45-id whitelist   (kept so hand-tuned mappings survive)
##   3 the element field
##   4 inference from type / effect / target_type
##   5 PHYSICAL
##
## Each level is asserted to BEAT the level below it, not merely to work in isolation — an
## isolated pass cannot tell you the order is right.

const FIRE := EffectSystemClass.EffectType.FIRE
const ICE := EffectSystemClass.EffectType.ICE
const HEAL := EffectSystemClass.EffectType.HEAL
const BUFF := EffectSystemClass.EffectType.BUFF
const DEBUFF := EffectSystemClass.EffectType.DEBUFF
const DARK := EffectSystemClass.EffectType.DARK
const PHYSICAL := EffectSystemClass.EffectType.PHYSICAL
const MP_RESTORE := EffectSystemClass.EffectType.MP_RESTORE


func test_authored_vfx_beats_the_legacy_whitelist() -> void:
	## "fire" is in the whitelist as FIRE; an authored ice override must win.
	var r: Dictionary = AbilityVFX.resolve({"id": "fire", "vfx": {"type": "ice"}})
	assert_eq(r["type"], ICE, "level 1 must outrank level 2")
	assert_eq(str(r["source"]), "authored")


func test_legacy_whitelist_beats_the_element_field() -> void:
	## The whitelist exists to protect hand-tuned mappings from a later element edit.
	var r: Dictionary = AbilityVFX.resolve({"id": "cure", "element": "fire"})
	assert_eq(r["type"], HEAL, "level 2 must outrank level 3 — cure stays a heal")
	assert_eq(str(r["source"]), "legacy")


func test_element_beats_inference() -> void:
	## type=physical would infer nothing and fall to PHYSICAL; the element must win.
	var r: Dictionary = AbilityVFX.resolve({"id": "unknown_x", "element": "ice", "type": "physical"})
	assert_eq(r["type"], ICE, "level 3 must outrank level 4")
	assert_eq(str(r["source"]), "element")


func test_inference_beats_the_physical_fallback() -> void:
	var heal: Dictionary = AbilityVFX.resolve({"id": "unknown_h", "type": "healing"})
	assert_eq(heal["type"], HEAL, "healing infers a heal")
	var mp: Dictionary = AbilityVFX.resolve({"id": "unknown_m", "type": "mp_restore"})
	assert_eq(mp["type"], MP_RESTORE, "mp_restore infers an mp restore")
	var up: Dictionary = AbilityVFX.resolve({"id": "unknown_u", "type": "support", "effect": "attack_up"})
	assert_eq(up["type"], BUFF, "an _up effect infers a buff")
	var down: Dictionary = AbilityVFX.resolve({"id": "unknown_d", "type": "support", "effect": "speed_down"})
	assert_eq(down["type"], DEBUFF, "a _down effect infers a debuff")
	var magic: Dictionary = AbilityVFX.resolve({"id": "unknown_g", "type": "magic"})
	assert_eq(magic["type"], DARK, "unelemented magic reads as arcane, not a sword swing")


func test_target_type_splits_leftover_utility_abilities() -> void:
	## The rule that closed the last 33 — derived from a field every ability carries.
	var ally: Dictionary = AbilityVFX.resolve({"id": "u1", "type": "support", "target_type": "self"})
	assert_eq(ally["type"], BUFF, "a self-targeted utility ability points inward")
	var enemy: Dictionary = AbilityVFX.resolve({"id": "u2", "type": "support", "target_type": "single_enemy"})
	assert_eq(enemy["type"], DEBUFF, "an enemy-targeted one points outward")


func test_physical_still_falls_through() -> void:
	var r: Dictionary = AbilityVFX.resolve({"id": "cleave", "type": "physical", "target_type": "single_enemy"})
	assert_eq(r["type"], PHYSICAL, "a declared physical attack must still render a swing")
	assert_eq(str(r["source"]), "fallback", "and reach the fallback, which is correct for it")


func test_an_empty_dictionary_does_not_crash() -> void:
	var r: Dictionary = AbilityVFX.resolve({})
	assert_eq(r["type"], PHYSICAL)
	assert_eq(r["power"], 1.0)
	assert_null(r["color"], "no element, no authored colour — null rather than a guess")


func test_power_ladder_is_preserved_from_effectsystem() -> void:
	## Moved verbatim from _get_ability_power_tier; the suffix ladder must not drift.
	assert_eq(AbilityVFX.power_for("firaga"), 1.8, "-aga is tier 3")
	assert_eq(AbilityVFX.power_for("holy"), 1.8, "named tier-3 exception")
	assert_eq(AbilityVFX.power_for("fira"), 1.3, "-a is tier 2")
	assert_eq(AbilityVFX.power_for("fire"), 1.0, "base is tier 1")


func test_authored_colour_and_shape_are_honoured_and_validated() -> void:
	var good: Dictionary = AbilityVFX.resolve({"id": "x", "vfx": {"color": "#ff8800", "shape": "bloom"}})
	assert_eq(good["color"], Color.html("#ff8800"), "a valid authored colour is used")
	assert_eq(str(good["shape"]), "bloom", "and a shape in vocabulary")
	var bad: Dictionary = AbilityVFX.resolve({"id": "x", "element": "fire", "vfx": {"shape": "not_a_shape"}})
	assert_ne(str(bad["shape"]), "not_a_shape", "an out-of-vocabulary shape must not pass through")
	assert_eq(bad["color"], AbilityVFX.ELEMENT_COLORS["fire"], "and the element colour still applies")


func test_the_four_uncovered_elements_reuse_an_animation_and_carry_a_tint() -> void:
	for pair in [["earth", PHYSICAL], ["wind", ICE], ["water", ICE], ["arcane", DARK]]:
		var r: Dictionary = AbilityVFX.resolve({"id": "e_%s" % pair[0], "element": pair[0]})
		assert_eq(r["type"], pair[1], "%s must reuse an existing animation" % pair[0])
		assert_eq(r["color"], AbilityVFX.ELEMENT_COLORS[pair[0]],
			"%s must carry its own tint, or it is indistinguishable from the animation it borrows" % pair[0])
