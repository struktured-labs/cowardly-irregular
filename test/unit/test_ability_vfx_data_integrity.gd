extends GutTest

## Every ability in data/abilities.json must resolve to a real EffectType, and the count that falls
## all the way through to PHYSICAL is RATCHETED — it may only go down.
##
## Pre-fix EffectSystem's ~45-id whitelist matched 19 of 289 abilities; the other 270 rendered a
## generic sword swing regardless of element. The ratchet exists so that number cannot silently
## climb back when someone adds abilities.

const ABILITIES_PATH := "res://data/abilities.json"
const BATTLE_SCENE_PATH := "res://src/battle/BattleScene.gd"

## The RATCHET is on the defect, not on a raw count: an ability declared physical SHOULD render a
## swing, so pinning the total would freeze correct behaviour. What must stay at zero is a
## NON-physical ability falling all the way through to PHYSICAL.
const MAX_NONPHYSICAL_FALLBACK := 0

var _abilities: Dictionary = {}


func before_all() -> void:
	var raw := FileAccess.get_file_as_string(ABILITIES_PATH)
	var parsed: Variant = JSON.parse_string(raw)
	_abilities = parsed if parsed is Dictionary else {}


func test_the_corpus_loaded() -> void:
	assert_gt(_abilities.size(), 200,
		"CONTROL: abilities.json must parse to a large dict — every count below is vacuous otherwise")
	assert_true(_abilities.has("fire"),
		"CONTROL: a NAMED known-present member, not just a count (a count passes on a wrong parse)")
	assert_false(_abilities.has("zzz_not_an_ability"),
		"CONTROL: and a fabricated id must be absent, or membership means nothing")


func test_every_ability_resolves_to_a_valid_effect_type() -> void:
	var valid := EffectSystemClass.EffectType.values()
	var bad: Array[String] = []
	for id in _abilities:
		var a: Dictionary = _abilities[id]
		a["id"] = id
		var r: Dictionary = AbilityVFX.resolve(a)
		if not (r["type"] in valid):
			bad.append("%s -> %s" % [id, r["type"]])
	assert_eq(bad, [] as Array[String], "these resolved outside the EffectType enum: %s" % [bad])


func test_resolve_survives_an_empty_dictionary() -> void:
	## Items and free moves reach spawn_ability_effect with ids that are not in abilities.json.
	var r: Dictionary = AbilityVFX.resolve({})
	assert_eq(r["type"], EffectSystemClass.EffectType.PHYSICAL, "an empty dict must fall back, not crash")
	assert_eq(r["power"], 1.0, "and carry the base power tier")


func test_no_nonphysical_ability_falls_back_to_a_sword_swing() -> void:
	var fallback: Array[String] = []
	var offenders: Array[String] = []
	for id in _abilities:
		var a: Dictionary = _abilities[id]
		a["id"] = id
		if str(AbilityVFX.resolve(a)["source"]) != "fallback":
			continue
		fallback.append(str(id))
		if str(a.get("type", "")) != "physical":
			offenders.append("%s (type=%s)" % [id, a.get("type", "")])
	gut.p("pure-fallback total: %d of %d — of which non-physical: %d" % [fallback.size(), _abilities.size(), offenders.size()])
	assert_gt(fallback.size(), 0,
		"CONTROL: some abilities MUST reach the fallback (the physical ones) — zero here means the resolver stopped running")
	assert_lte(offenders.size(), MAX_NONPHYSICAL_FALLBACK,
		"non-physical abilities rendering a generic swing: %s" % [offenders])


func test_authored_vfx_values_are_in_vocabulary() -> void:
	var bad: Array[String] = []
	for id in _abilities:
		var a: Dictionary = _abilities[id]
		if not (a.get("vfx") is Dictionary):
			continue
		var v: Dictionary = a["vfx"]
		if v.has("type") and not AbilityVFX.TYPE_NAMES.has(str(v["type"])):
			bad.append("%s: type=%s" % [id, v["type"]])
		if v.has("shape") and not (str(v["shape"]) in AbilityVFX.SHAPES):
			bad.append("%s: shape=%s" % [id, v["shape"]])
		if v.has("color") and not Color.html_is_valid(str(v["color"])):
			bad.append("%s: color=%s" % [id, v["color"]])
	assert_eq(bad, [] as Array[String],
		"authored vfx values outside the vocabulary — these silently fall back: %s" % [bad])


func test_element_colors_agree_with_battlescene() -> void:
	## Redundant sources that must AGREE — BattleScene has no class_name so the table is duplicated,
	## and this is the join that keeps the copies honest rather than modelling a precedence.
	var src := FileAccess.get_file_as_string(BATTLE_SCENE_PATH)
	var idx := src.find("const WEAKNESS_ELEMENT_COLORS")
	assert_gt(idx, -1, "CONTROL: the BattleScene table must be found or this test is vacuous")
	var block := src.substr(idx, src.find("\n}", idx) - idx)
	var missing: Array[String] = []
	for element in AbilityVFX.ELEMENT_COLORS:
		if not block.contains('"%s"' % element):
			missing.append(str(element))
	assert_eq(missing, [] as Array[String],
		"AbilityVFX.ELEMENT_COLORS has elements BattleScene's table lacks: %s" % [missing])
	assert_true(block.contains('"fire"'),
		"CONTROL: a known member of the BattleScene table must be found by this parse")
