class_name RecipeMatcher
extends RefCounted

## Which starter recipes one committed player choice counts toward; pure over a plain record (keys below in counts_toward).

const BM := preload("res://src/battle/BattleManager.gd")

## Starter catalog order (story 26928 ids); thresholds live in the ledger, not here.
const RECIPE_IDS: Array[String] = [
	"heal_ally_under_50",
	"cure_status",
	"hit_known_weakness",
	"finish_under_25",
	"defer_at_low_ap",
	"advance_full_bank",
	"bard_riff_unblinded",
	"steal_first",
	"revive_ko",
]


## Recipe ids this choice counts toward, in catalog order; empty when it teaches nothing.
static func recipes_for(choice: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for id in RECIPE_IDS:
		if counts_toward(id, choice):
			out.append(id)
	return out


## Keys: action_type, ability_id, ability_kind, target_side, target_hp_pct, target_ko, target_statuses, cures, target_weak, actor_ap, queued.
static func counts_toward(recipe_id: String, c: Dictionary) -> bool:
	var action := str(c.get("action_type", ""))
	var kind := str(c.get("ability_kind", ""))
	var side := str(c.get("target_side", ""))
	var hp := float(c.get("target_hp_pct", 1.0))
	var ko := bool(c.get("target_ko", false))
	var statuses: Array = c.get("target_statuses", [])
	match recipe_id:
		"heal_ally_under_50":
			return kind == "heal" and side == "ally" and not ko and hp < 0.5
		"cure_status":
			if side != "ally" or ko:
				return false
			for s in c.get("cures", []):
				if s in statuses:
					return true
			return false
		"hit_known_weakness":
			return side == "enemy" and bool(c.get("target_weak", false)) and (action == "attack" or kind == "damage")
		"finish_under_25":
			return action == "attack" and side == "enemy" and not ko and hp < 0.25
		"defer_at_low_ap":
			return action == "defer" and int(c.get("actor_ap", 0)) <= 0
		"advance_full_bank":
			return BM.is_full_bank(int(c.get("actor_ap", 0)), int(c.get("queued", 0)))
		"bard_riff_unblinded":
			return str(c.get("ability_id", "")) == "riff" and side == "enemy" and not ("blind" in statuses)
		"steal_first":
			return kind == "steal" and side == "enemy" and hp >= 1.0
		"revive_ko":
			return kind == "revive" and side == "ally" and ko
	push_warning("[RecipeMatcher] unknown recipe id '%s'" % recipe_id)
	return false


## The choice record for one committed player action; pure over its arguments (the caller passes the ability dict and its own party).
static func choice_from(actor: Combatant, action_type: String, ability: Dictionary, target: Combatant, allies: Array, queued: int = 0, strike_element: String = "") -> Dictionary:
	var c := {
		"action_type": action_type,
		"ability_id": str(ability.get("id", "")),
		"ability_kind": ability_kind(ability) if action_type == "ability" else "",
		"actor_ap": actor.current_ap if actor != null else 0,
		"queued": queued,
	}
	if action_type == "attack":
		c["ability_kind"] = "damage"
	if target == null:
		return c
	c["target_side"] = "ally" if target in allies else "enemy"
	c["target_ko"] = not target.is_alive
	c["target_hp_pct"] = float(target.current_hp) / float(maxi(1, target.max_hp))
	var statuses: Array = []
	for s in target.status_effects:
		statuses.append(str(s))
	c["target_statuses"] = statuses
	var element := str(ability.get("element", "")) if action_type == "ability" else strike_element
	c["target_weak"] = element != "" and element in target.elemental_weaknesses
	if c["ability_kind"] == "cure":
		var cures: Array = []
		for s in BM.ESUNA_AILMENTS:
			cures.append(s)
		c["cures"] = cures
	return c


## The recipe-facing kind of an ability row from abilities.json.
static func ability_kind(ability: Dictionary) -> String:
	var type := str(ability.get("type", ""))
	var effect := str(ability.get("effect", ""))
	if type == "revival":
		return "revive"
	if type == "healing":
		return "heal"
	if effect == "cleanse":
		return "cure"
	if effect == "steal":
		return "steal"
	if type == "magic" or type == "physical":
		return "damage"
	return "other"
