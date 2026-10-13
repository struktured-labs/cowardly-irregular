extends GutTest

## A Flame Sword sounded fiery on a basic swing and mundane on Cleave, with identical mechanics.
##
## play_strike_element is the weapon's elemental voice. It sat below _on_damage_dealt's ability
## early-return, so only basic attacks reached it. The exclusion's stated reason is about SPELLS --
## "a Fire spell won't also fire strike_fire" -- which is correct and preserved. It was also
## excluding PHYSICAL abilities, where the weapon does the striking exactly as it does on a swing.
## _weapon_element_for's own note is the argument for including them: "the cue is a strike voice,
## so only the thing doing the striking counts."
##
## Mechanically identical, which is what makes this purely an audio inconsistency: <element>_damage_bonus
## is consumed at only two sites (BattleManager:5857 in _execute_magic_ability and :6182 in
## estimate_ability_breakdown), BOTH keyed on the ABILITY's element. Nothing in the basic-attack or
## physical-ability path applies a weapon element, so neither deals elemental damage -- the cue is
## flavour in both, and the blade does not stop being enchanted because you used an ability.

const BATTLE_SCENE := "res://src/battle/BattleScene.gd"
const EQUIPMENT := "res://data/equipment.json"
const ABILITIES := "res://data/abilities.json"
const SFX_MANIFEST := "res://data/sfx_manifest.json"
const GdSource := preload("res://test/unit/helpers/gd_source.gd")
const FUNC_HEAD := "func _on_damage_dealt(target: Combatant"
## ⚠️ The TWO-LINE form, deliberately. The hoisted block's own condition begins
## `if _current_ability_id != "" and ...`, so the one-line anchor matched MY OWN insertion
## and the ordering arm compared the new code against itself. An anchor must be unique in
## the range it anchors, and this change is what made the short one ambiguous.
const EARLY_RETURN := 'if _current_ability_id != "":\n\t\treturn'
const ELEMENT_CUE := "SoundManager.play_strike_element("
const TYPE_GATE := '== "physical"'


func _body() -> String:
	var src: String = GdSource.code_of(BATTLE_SCENE)
	var i: int = src.find(FUNC_HEAD)
	if i < 0:
		return ""
	var j: int = src.find("\nfunc ", i + FUNC_HEAD.length())
	return src.substr(i, (j - i) if j > i else src.length() - i)


func _json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return (parsed as Dictionary) if parsed is Dictionary else {}


## Weapon id -> element, derived the way _weapon_element_for derives it: a special_effects key
## ending in _damage_bonus with a positive value. Not an `element` field -- there is none.
func _elemental_weapons() -> Dictionary:
	var out: Dictionary = {}
	var weapons: Dictionary = (_json(EQUIPMENT).get("weapons", {}) as Dictionary)
	for wid in weapons.keys():
		var w: Variant = weapons[wid]
		if not (w is Dictionary):
			continue
		var se: Variant = (w as Dictionary).get("special_effects", {})
		if not (se is Dictionary):
			continue
		for k in (se as Dictionary).keys():
			var key: String = str(k)
			if key.ends_with("_damage_bonus") and float((se as Dictionary)[k]) > 0.0:
				out[str(wid)] = key.trim_suffix("_damage_bonus")
				break
	return out


func test_the_anchors_this_guard_reads_still_exist() -> void:
	## FLOOR: every arm below indexes into this body; a rename makes them compare -1 to -1.
	var b: String = _body()
	assert_ne(b, "", "FLOOR: %s is gone — every ordering arm below is vacuous" % FUNC_HEAD)
	if b == "":
		return
	for anchor in [EARLY_RETURN, ELEMENT_CUE]:
		assert_true(b.contains(anchor), "FLOOR: `%s` is no longer in _on_damage_dealt" % anchor)
	assert_true(GdSource.code_of(BATTLE_SCENE).contains("func _weapon_element_for"),
		"FLOOR: _weapon_element_for is gone — the element the cue needs is no longer derived")


func test_a_physical_ability_reaches_the_weapon_element_cue() -> void:
	## THE DEFECT. Below the return an ability never reaches the cue, so order IS the behaviour.
	var b: String = _body()
	if b == "":
		return
	var first_cue: int = b.find(ELEMENT_CUE)
	var ret: int = b.find(EARLY_RETURN)
	assert_gt(first_cue, -1, "precondition: the element cue is called in this function")
	assert_gt(ret, -1, "precondition: the ability early-return is in this function")
	assert_lt(first_cue, ret,
		("every play_strike_element call sits at or below the ability early-return (first at %d, "
		+ "return at %d), so a Flame Sword's Cleave is mute while the same sword's basic swing "
		+ "is not.") % [first_cue, ret])


func test_the_hoisted_route_is_gated_to_PHYSICAL_abilities() -> void:
	## CONTROL against the over-correction, and the whole reason the old exclusion existed: an
	## ungated hoist makes a Fire spell fire strike_fire on top of its own cast cue.
	var b: String = _body()
	if b == "":
		return
	var ret: int = b.find(EARLY_RETURN)
	if ret < 0:
		return
	var above: String = b.substr(0, ret)
	var cue: int = above.find(ELEMENT_CUE)
	assert_gt(cue, -1, "precondition: a hoisted element-cue route exists above the return")
	assert_true(above.contains(TYPE_GATE),
		("the hoisted element cue is not gated on %s, so a MAGIC ability would layer a weapon "
		+ "element over its own cast sound — the exact thing the early-return was protecting.") % TYPE_GATE)
	assert_lt(above.find(TYPE_GATE), cue,
		"the physical gate must be ABOVE the hoisted cue it guards, not after it")


func test_the_basic_attack_site_stays_BELOW_the_return() -> void:
	## The basic-attack layering (weapon hit, then the element over it) must not move: hoisting the
	## whole block would put a sword thump under every spell.
	var b: String = _body()
	if b == "":
		return
	var ret: int = b.find(EARLY_RETURN)
	assert_gt(b.find("SoundManager.play_attack_hit("), ret,
		"play_attack_hit moved ABOVE the ability return — a spell would now carry a weapon layer")
	assert_true(b.substr(ret).contains(ELEMENT_CUE),
		"the basic-attack element cue is gone from below the return — this fix was meant to ADD a route, not move one")


func test_an_elemental_weapon_and_a_physical_ability_both_exist() -> void:
	## PREMISE: without a weapon carrying an element AND a physical ability to swing it with, the
	## ordering above defends nothing. Both halves measured from data, plus the cue that plays.
	var weapons: Dictionary = _elemental_weapons()
	assert_gt(weapons.size(), 0,
		"no weapon's special_effects yields an element — _weapon_element_for can only return \"\" and this guard is moot")
	var ab: Dictionary = _json(ABILITIES)
	var abilities: Dictionary = (ab.get("abilities", ab) as Dictionary)
	var physical: int = 0
	for aid in abilities.keys():
		var a: Variant = abilities[aid]
		if a is Dictionary and str((a as Dictionary).get("type", "")) == "physical":
			physical += 1
	assert_gt(physical, 5, "only %d physical abilities exist; the hoisted route would be near-dead" % physical)
	var cues: Dictionary = (_json(SFX_MANIFEST).get("sfx", {}) as Dictionary)
	var voiced: Array = []
	for wid in weapons.keys():
		if cues.has("strike_" + str(weapons[wid])):
			voiced.append(str(weapons[wid]))
	assert_gt(voiced.size(), 0,
		"no strike_<element> cue is authored for any elemental weapon (%s) — the hoist would be a no-op" % [weapons.values()])
