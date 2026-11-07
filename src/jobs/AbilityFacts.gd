extends RefCounted
class_name AbilityFacts

## What an ability DOES, one row per fact, read from its abilities.json row and the game's own estimators, never typed
## (struktured's zoom v2, main 23219/23225). ONE source for the field Abilities zoom and the battle card, so they cannot
## disagree. Each row is {icon: Texture2D or null, label, value, keys}; `keys` names the abilities.json keys it read,
## which is what test_every_ability_says_what_it_does uses to prove no authored mechanic is silently dropped.

const TYPE_WORDS := {
	"physical": "Physical", "magic": "Magic", "healing": "Healing", "support": "Support", "summon": "Summon",
	"revival": "Revival", "song": "Song", "escape": "Escape", "meta": "Meta", "mp_restore": "MP restore",
}
const TARGET_WORDS := {
	"single_enemy": "One foe", "all_enemies": "All foes", "single_ally": "One ally", "all_allies": "The whole party",
	"self": "Self", "dead_ally": "A fallen ally", "all_rat_allies": "Every rat on its side", "last_attacker": "Whoever hit it last",
}
const SCALES_WORDS := {
	"defense": "scales with Defense", "missing_hp": "scales with missing HP", "speed": "scales with Speed",
	"target_defense": "scales with the target's Defense", "most_used_ability": "scales with your most-used ability",
}
## Keys an ability row may carry that are not mechanics a player reads, each with its reason.
const NON_FACT := {
	"id": "the lookup key", "name": "the panel's title", "description": "the panel's prose, shown above the rows",
	"animation": "presentation", "vfx": "presentation", "family": "an icon family, not a mechanic",
	"tier": "an icon tier, not a mechanic", "cost": "a SHOP price, not a cost to cast (controller 23224)",
	"summon_message": "the flavour line printed when it summons", "threat_class": "an AI targeting hint, not something the player reads",
}


## Every fact for `ability_id` (aliases resolve through JobSystem). Type and Target always come first, so there are always 2+.
static func rows(ability_id: String, caster = null) -> Array:
	var js = _js()
	var a: Dictionary = js.get_ability(ability_id) if js else {}
	if a.is_empty():
		return []
	var out: Array = []
	var icon: Texture2D = AbilityIcons.tinted(str(a.get("id", ability_id)))
	var type_word := _word(TYPE_WORDS, str(a.get("type", "")))
	if a.has("magic_school"):
		type_word += " · %s magic" % _human(str(a["magic_school"]))
	out.append(_row(icon, "Type", type_word, ["type", "magic_school"]))
	out.append(_row(null, "Target", _word(TARGET_WORDS, str(a.get("target_type", ""))), ["target_type"]))
	if a.has("element") and str(a["element"]) != "" and str(a["element"]).to_lower() != "none":
		out.append(_row(null, "Element", _human(str(a["element"])), ["element"]))
	var mp: int = int(js.get_ability_mp_cost(caster, str(a.get("id", ability_id)))) if caster != null else int(a.get("mp_cost", 0))
	out.append(_row(null, "MP", "Free" if mp <= 0 else str(mp), ["mp_cost"]))
	if a.has("damage_multiplier"):
		var power := "×%s" % _num(float(a["damage_multiplier"]))
		if a.has("scales_with"):
			power += ", " + _word(SCALES_WORDS, str(a["scales_with"]))
		out.append(_row(null, "Power", power, ["damage_multiplier", "scales_with"]))
	if a.has("hits"):
		out.append(_row(null, "Hits", str(int(a["hits"])), ["hits"]))
	if a.has("heal_amount"):
		var bm = _bm()
		var healed: int = int(bm.heal_cast_amount(caster, a)) if bm and caster != null else 0
		out.append(_row(null, "Heals", ("~%d HP" % healed) if healed > 0 else "HP, scaled by Magic", ["heal_amount"]))
	if a.has("revive_percentage"):
		out.append(_row(null, "Revives", "at %d%% HP" % _pct(a["revive_percentage"]), ["revive_percentage"]))
	if a.has("drain_percentage"):
		out.append(_row(null, "Drains", "%d%% of the damage as HP" % _pct(a["drain_percentage"]), ["drain_percentage"]))
	if a.has("drain_mp"):
		out.append(_row(null, "Drains MP", str(int(a["drain_mp"])), ["drain_mp"]))
	if a.has("mp_restore_percent"):
		out.append(_row(null, "Restores", "%d%% MP" % _pct(a["mp_restore_percent"]), ["mp_restore_percent"]))
	if a.has("regen_per_turn"):
		out.append(_row(null, "Regenerates", "%d HP a turn" % int(a["regen_per_turn"]), ["regen_per_turn"]))
	if a.has("mp_amount"):
		out.append(_row(null, "Restores", "%d MP" % int(a["mp_amount"]), ["mp_amount"]))
	if a.has("absorb_amount"):
		out.append(_row(null, "Absorbs", "%d damage" % int(a["absorb_amount"]), ["absorb_amount"]))
	if a.has("effect") and str(a["effect"]) != "":
		out.append(_row(null, "Effect", _effect_text(a, "effect", "effect_chance", "duration", "stat_modifier"),
			["effect", "effect_chance", "duration", "stat_modifier"]))
	if a.has("stat") or a.has("modifier"):
		out.append(_row(null, "Changes", _stat_text(a), ["stat", "modifier"]))
	if a.has("secondary_effect"):
		out.append(_row(null, "Also", _effect_text(a, "secondary_effect", "secondary_chance", "", "secondary_modifier"),
			["secondary_effect", "secondary_chance", "secondary_modifier"]))
	if a.has("success_rate"):
		out.append(_row(null, "Lands", "%d%% of the time" % _pct(a["success_rate"]), ["success_rate"]))
	if a.has("crit_chance"):
		out.append(_row(null, "Critical", "%d%% chance" % _pct(a["crit_chance"]), ["crit_chance"]))
	if a.has("next_attack_multiplier"):
		out.append(_row(null, "Next attack", "×%s" % _num(float(a["next_attack_multiplier"])), ["next_attack_multiplier"]))
	if bool(a.get("ignores_resistance", false)):
		out.append(_row(null, "Ignores", "resistances", ["ignores_resistance"]))
	if a.has("steals"):
		out.append(_row(null, "Steals", "an item" if bool(a["steals"]) else "nothing", ["steals"]))
	if a.has("summon_id") or a.has("summon_count") or a.has("summon_duration"):
		out.append(_row(null, "Summons", _summon_text(a), ["summon_id", "summon_count", "summon_duration"]))
	if a.has("countdown"):
		out.append(_row(null, "Countdown", "%d turns" % int(a["countdown"]), ["countdown"]))
	if a.has("condition") or a.has("threshold"):
		out.append(_row(null, "When", _condition_text(a), ["condition", "threshold"]))
	if a.has("multiplier"):
		out.append(_row(null, "Multiplies", "×%s" % _num(float(a["multiplier"])), ["multiplier"]))
	if a.has("max_multiplier"):
		out.append(_row(null, "Up to", "×%s" % _num(float(a["max_multiplier"])), ["max_multiplier"]))
	if a.has("max_depth"):
		out.append(_row(null, "Up to", "%d deep" % int(a["max_depth"]), ["max_depth"]))
	if a.has("damage_variance"):
		out.append(_row(null, "Damage", "varies up to ×%s" % _num(float(a["damage_variance"])), ["damage_variance"]))
	if a.has("element_boost"):
		out.append(_row(null, "Boosts", "%s %s" % [_human(str(a["element_boost"])), _mod_pct(float(a.get("element_boost_modifier", 1.0)))],
			["element_boost", "element_boost_modifier"]))
	if a.has("reflect_damage_element"):
		out.append(_row(null, "Reflects", "%s damage" % _human(str(a["reflect_damage_element"])), ["reflect_damage_element"]))
	if a.has("damage_reduction"):
		out.append(_row(null, "Takes", "%d%% less damage" % _pct(a["damage_reduction"]), ["damage_reduction"]))
	if a.has("evasion_bonus"):
		out.append(_row(null, "Evasion", "+%d%%" % _pct(a["evasion_bonus"]), ["evasion_bonus"]))
	if a.has("damage_to_self_pct") or a.has("recoil_pct"):
		out.append(_row(null, "Recoil", "%d%% of the damage to itself" % _pct(a.get("damage_to_self_pct", a.get("recoil_pct", 0))),
			["damage_to_self_pct", "recoil_pct"]))
	if a.has("ap_gain"):
		out.append(_row(null, "Grants", "+%d AP" % int(a["ap_gain"]), ["ap_gain"]))
	if a.has("bp_cost"):
		out.append(_row(null, "BP cost", str(int(a["bp_cost"])), ["bp_cost"]))
	if a.has("bp_gain"):
		out.append(_row(null, "Grants", "+%d BP" % int(a["bp_gain"]), ["bp_gain"]))
	if bool(a.get("ignores_defense", false)):
		out.append(_row(null, "Ignores", "defense", ["ignores_defense"]))
	if bool(a.get("ignores_evasion", false)):
		out.append(_row(null, "Ignores", "evasion", ["ignores_evasion"]))
	if bool(a.get("next_crit", false)):
		out.append(_row(null, "Next hit", "is a critical", ["next_crit"]))
	if bool(a.get("priority", false)):
		out.append(_row(null, "Speed", "acts first", ["priority"]))
	if bool(a.get("guaranteed_escape", false)):
		out.append(_row(null, "Escape", "always succeeds", ["guaranteed_escape"]))
	if a.has("secondary_target"):
		out.append(_row(null, "Also hits", _word(TARGET_WORDS, str(a["secondary_target"])), ["secondary_target"]))
	if a.has("trigger"):
		out.append(_row(null, "Triggers", _human(str(a["trigger"])), ["trigger"]))
	if a.has("penalty"):
		out.append(_row(null, "Cost", _human(str(a["penalty"])), ["penalty"]))
	if a.has("meta_effect"):
		out.append(_row(null, "Meta", _human(str(a["meta_effect"])), ["meta_effect"]))
	if a.has("corruption_risk") or a.has("corruption_amount"):
		out.append(_row(null, "Risk", _corruption_text(a), ["corruption_risk", "corruption_amount"]))
	for r in out:
		r["keys"] = (r["keys"] as Array).filter(func(k): return a.has(k))
	return out


static func _row(icon, label: String, value: String, keys: Array) -> Dictionary:
	return {"icon": icon, "label": label, "value": value, "keys": keys}


static func _effect_text(a: Dictionary, effect_key: String, chance_key: String, dur_key: String, mod_key: String) -> String:
	var text := StatusNames.display(str(a[effect_key]))
	var bits: Array = []
	if chance_key != "" and a.has(chance_key):
		bits.append("%d%%" % _pct(a[chance_key]))
	if dur_key != "" and a.has(dur_key) and int(a[dur_key]) > 0:
		bits.append("%d turn%s" % [int(a[dur_key]), "" if int(a[dur_key]) == 1 else "s"])
	if mod_key != "" and a.has(mod_key):
		bits.append(_mod_pct(float(a[mod_key])))
	return text if bits.is_empty() else "%s (%s)" % [text, ", ".join(PackedStringArray(bits))]


static func _stat_text(a: Dictionary) -> String:
	var stat := _human(str(a.get("stat", "a stat")))
	return "%s %s" % [stat, _mod_pct(float(a.get("modifier", 1.0)))] if a.has("modifier") else stat


static func _summon_text(a: Dictionary) -> String:
	var who := _human(str(a.get("summon_id", "an ally")))
	var bits: Array = []
	if a.has("summon_count"):
		bits.append("×%d" % int(a["summon_count"]))
	if a.has("summon_duration"):
		bits.append("for %d turns" % int(a["summon_duration"]))
	return who if bits.is_empty() else "%s %s" % [who, " ".join(PackedStringArray(bits))]


static func _condition_text(a: Dictionary) -> String:
	if str(a.get("condition", "")) == "low_hp_threshold":
		return "below %d%% HP" % _pct(a.get("threshold", 0.3))
	var c := _human(str(a.get("condition", "a condition")))
	return "%s at %d%%" % [c, _pct(a["threshold"])] if a.has("threshold") else c


static func _corruption_text(a: Dictionary) -> String:
	var bits: Array = []
	if a.has("corruption_risk"):
		bits.append("%d%% chance of corruption" % _pct(a["corruption_risk"]))
	if a.has("corruption_amount"):
		bits.append("+%s corruption" % _num(float(a["corruption_amount"])))
	return ", ".join(PackedStringArray(bits))


## A JSON fraction (0.3) or whole percent (30) as a whole percent.
static func _pct(v) -> int:
	var f := float(v)
	return int(round(f * 100.0)) if f <= 1.0 else int(round(f))


## A multiplier as a signed percent: 0.7 -> "-30%", 1.5 -> "+50%".
static func _mod_pct(m: float) -> String:
	var p := int(round((m - 1.0) * 100.0))
	return "%+d%%" % p


static func _num(f: float) -> String:
	return str(int(f)) if is_equal_approx(f, round(f)) else ("%.2f" % f).rstrip("0").rstrip(".")


static func _word(table: Dictionary, v: String) -> String:
	return str(table[v]) if table.has(v) else _human(v)


## Never a raw key on screen: "copy_last_ability" -> "Copy Last Ability".
static func _human(v: String) -> String:
	return v.replace("_", " ").capitalize() if v != "" else "—"


static func _js():
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null("JobSystem") if tree and tree.root else null


static func _bm():
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null("BattleManager") if tree and tree.root else null
