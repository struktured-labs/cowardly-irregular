class_name AbilityVFX
extends RefCounted

## Data-driven ability VFX resolution. Static and scene-free so tests and EffectSystem can both call it.
## Pre-fix EffectSystem mapped a hardcoded ~45-id whitelist; it matched 19 of 289 abilities and the
## other 270 rendered generic PHYSICAL. Precedence keeps that whitelist as level 2 so hand-tuned
## mappings survive, and derives everything else from fields abilities.json already carries.

## Must agree with BattleScene.WEAKNESS_ELEMENT_COLORS — pinned by test_ability_vfx_data_integrity.
## Duplicated rather than referenced because BattleScene has no class_name; the test is the join.
const ELEMENT_COLORS: Dictionary = {
	"fire": Color(2.5, 0.6, 0.15),
	"ice": Color(0.4, 1.8, 2.6),
	"lightning": Color(2.6, 2.6, 0.5),
	"dark": Color(1.4, 0.4, 2.0),
	"holy": Color(2.6, 2.4, 1.6),
	"physical": Color(1.9, 1.5, 1.0),
	"wind": Color(1.2, 2.2, 1.2),
	"earth": Color(1.7, 1.3, 0.7),
	"water": Color(0.6, 1.2, 2.4),
	"poison": Color(1.2, 2.0, 0.7),
	"arcane": Color(2.2, 1.4, 2.4),
}

## The four elements with no dedicated animation reuse an existing one and carry a tint instead.
const ELEMENT_TYPES: Dictionary = {
	"fire": EffectSystemClass.EffectType.FIRE,
	"ice": EffectSystemClass.EffectType.ICE,
	"lightning": EffectSystemClass.EffectType.LIGHTNING,
	"holy": EffectSystemClass.EffectType.HOLY,
	"dark": EffectSystemClass.EffectType.DARK,
	"poison": EffectSystemClass.EffectType.POISON,
	"earth": EffectSystemClass.EffectType.PHYSICAL,
	"wind": EffectSystemClass.EffectType.ICE,
	"water": EffectSystemClass.EffectType.ICE,
	"arcane": EffectSystemClass.EffectType.DARK,
}

const SHAPES: Array[String] = ["bolt", "shards", "strike", "bloom"]

## Level 2 of the precedence chain — the pre-existing hand-tuned map, kept verbatim.
const LEGACY_IDS: Dictionary = {
	"fire": EffectSystemClass.EffectType.FIRE,
	"fira": EffectSystemClass.EffectType.FIRE,
	"firaga": EffectSystemClass.EffectType.FIRE,
	"flame_strike": EffectSystemClass.EffectType.FIRE,
	"blizzard": EffectSystemClass.EffectType.ICE,
	"blizzara": EffectSystemClass.EffectType.ICE,
	"blizzaga": EffectSystemClass.EffectType.ICE,
	"ice_lance": EffectSystemClass.EffectType.ICE,
	"thunder": EffectSystemClass.EffectType.LIGHTNING,
	"thundara": EffectSystemClass.EffectType.LIGHTNING,
	"thundaga": EffectSystemClass.EffectType.LIGHTNING,
	"shock": EffectSystemClass.EffectType.LIGHTNING,
	"holy": EffectSystemClass.EffectType.HOLY,
	"divine_light": EffectSystemClass.EffectType.HOLY,
	"smite": EffectSystemClass.EffectType.HOLY,
	"dark": EffectSystemClass.EffectType.DARK,
	"drain": EffectSystemClass.EffectType.DARK,
	"darkness": EffectSystemClass.EffectType.DARK,
	"shadow_bolt": EffectSystemClass.EffectType.DARK,
	"life_drain": EffectSystemClass.EffectType.DARK,
	"cure": EffectSystemClass.EffectType.HEAL,
	"cura": EffectSystemClass.EffectType.HEAL,
	"curaga": EffectSystemClass.EffectType.HEAL,
	"heal": EffectSystemClass.EffectType.HEAL,
	"regen": EffectSystemClass.EffectType.HEAL,
	"ether": EffectSystemClass.EffectType.MP_RESTORE,
	"hi_ether": EffectSystemClass.EffectType.MP_RESTORE,
	"mega_ether": EffectSystemClass.EffectType.MP_RESTORE,
	"elixir": EffectSystemClass.EffectType.MP_RESTORE,
	"megalixir": EffectSystemClass.EffectType.MP_RESTORE,
	"channel": EffectSystemClass.EffectType.MP_RESTORE,
	"pray": EffectSystemClass.EffectType.MP_RESTORE,
	"riff": EffectSystemClass.EffectType.MP_RESTORE,
	"protect": EffectSystemClass.EffectType.BUFF,
	"shell": EffectSystemClass.EffectType.BUFF,
	"haste": EffectSystemClass.EffectType.BUFF,
	"brave": EffectSystemClass.EffectType.BUFF,
	"faith": EffectSystemClass.EffectType.BUFF,
	"slow": EffectSystemClass.EffectType.DEBUFF,
	"dispel": EffectSystemClass.EffectType.DEBUFF,
	"break": EffectSystemClass.EffectType.DEBUFF,
	"weaken": EffectSystemClass.EffectType.DEBUFF,
	"poison": EffectSystemClass.EffectType.POISON,
	"bio": EffectSystemClass.EffectType.POISON,
	"venom": EffectSystemClass.EffectType.POISON,
}

const TYPE_NAMES: Dictionary = {
	"fire": EffectSystemClass.EffectType.FIRE,
	"ice": EffectSystemClass.EffectType.ICE,
	"lightning": EffectSystemClass.EffectType.LIGHTNING,
	"holy": EffectSystemClass.EffectType.HOLY,
	"dark": EffectSystemClass.EffectType.DARK,
	"heal": EffectSystemClass.EffectType.HEAL,
	"physical": EffectSystemClass.EffectType.PHYSICAL,
	"buff": EffectSystemClass.EffectType.BUFF,
	"debuff": EffectSystemClass.EffectType.DEBUFF,
	"poison": EffectSystemClass.EffectType.POISON,
	"mp_restore": EffectSystemClass.EffectType.MP_RESTORE,
}


## Full resolution. An empty dict must not crash — items and free moves arrive with unknown ids.
static func resolve(ability: Dictionary) -> Dictionary:
	var id: String = str(ability.get("id", ""))
	var element: String = str(ability.get("element", ""))
	var vfx: Dictionary = ability.get("vfx", {}) if ability.get("vfx") is Dictionary else {}

	var out := {
		"type": EffectSystemClass.EffectType.PHYSICAL,
		"power": power_for(id),
		"color": null,
		"shape": "strike",
		"source": "fallback",
	}

	## 1 — authored override wins outright.
	if vfx.has("type") and TYPE_NAMES.has(str(vfx["type"])):
		out["type"] = TYPE_NAMES[str(vfx["type"])]
		out["source"] = "authored"
	## 2 — the legacy whitelist, so hand-tuned ids keep their mapping.
	elif LEGACY_IDS.has(id):
		out["type"] = LEGACY_IDS[id]
		out["source"] = "legacy"
	## 3 — the element field, which 71 abilities carry.
	elif ELEMENT_TYPES.has(element):
		out["type"] = ELEMENT_TYPES[element]
		out["source"] = "element"
	else:
		var inferred: Variant = _infer(ability)
		if inferred != null:
			out["type"] = inferred
			out["source"] = "inferred"

	if vfx.has("power"):
		out["power"] = float(vfx["power"])
	if vfx.has("color") and Color.html_is_valid(str(vfx["color"])):
		out["color"] = Color.html(str(vfx["color"]))
	elif ELEMENT_COLORS.has(element):
		out["color"] = ELEMENT_COLORS[element]
	elif out["source"] == "inferred" and str(ability.get("type", "")) == "magic":
		out["color"] = ELEMENT_COLORS["arcane"]

	if vfx.has("shape") and str(vfx["shape"]) in SHAPES:
		out["shape"] = str(vfx["shape"])
	else:
		out["shape"] = _shape_for(out["type"])
	return out


## Level 4 — derived from fields abilities.json already carries, so no authoring is required.
static func _infer(ability: Dictionary) -> Variant:
	var atype: String = str(ability.get("type", ""))
	var effect: String = str(ability.get("effect", ""))
	if atype in ["healing", "revival"] or ability.has("heal_amount") or ability.has("revive_percentage"):
		return EffectSystemClass.EffectType.HEAL
	if atype == "mp_restore" or ability.has("mp_amount"):
		return EffectSystemClass.EffectType.MP_RESTORE
	if effect.ends_with("_up") or effect in ["buff", "regen", "haste", "shield", "invisible"]:
		return EffectSystemClass.EffectType.BUFF
	if effect.ends_with("_down") or effect in ["debuff", "dispel", "slow", "cleanse", "taunt"]:
		return EffectSystemClass.EffectType.DEBUFF
	if effect in ["poison", "venom", "disease"]:
		return EffectSystemClass.EffectType.POISON
	## Unelemented magic reads as arcane rather than a sword swing.
	if atype in ["magic", "summon", "song", "meta"]:
		return EffectSystemClass.EffectType.DARK
	## Anything non-physical left over is a utility ability; target_type says which way it points.
	## Derived rather than hand-listed — every ability carries target_type, and it classified all 33.
	if atype != "physical" and atype != "":
		if str(ability.get("target_type", "")) in ["self", "single_ally", "all_allies", "dead_ally"]:
			return EffectSystemClass.EffectType.BUFF
		return EffectSystemClass.EffectType.DEBUFF
	return null


static func _shape_for(effect_type: int) -> String:
	match effect_type:
		EffectSystemClass.EffectType.LIGHTNING, EffectSystemClass.EffectType.DARK:
			return "bolt"
		EffectSystemClass.EffectType.ICE:
			return "shards"
		EffectSystemClass.EffectType.HEAL, EffectSystemClass.EffectType.BUFF, EffectSystemClass.EffectType.MP_RESTORE:
			return "bloom"
		_:
			return "strike"


## Moved from EffectSystem._get_ability_power_tier — the -a / -aga suffix ladder, unchanged.
static func power_for(ability_id: String) -> float:
	if ability_id.ends_with("aga") or ability_id in ["holy", "flare", "ultima", "megalixir"]:
		return 1.8
	if ability_id.ends_with("a") or ability_id in ["cura", "fira", "blizzara", "thundara", "hi_ether"]:
		return 1.3
	return 1.0
