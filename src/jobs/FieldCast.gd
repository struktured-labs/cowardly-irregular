extends RefCounted
class_name FieldCast

## Out-of-battle casting (struktured 2026-11-01: "ANY heal abilities are allowed out of battle").
## The castable set is DERIVED from each ability's own type/effect, never listed: a new restorative
## spell is castable the day it is authored, and a damaging or combat-buff one never is.

## Which restorative kind this ability is, or "" when it stays battle-only.
static func kind(ability: Dictionary) -> String:
	var t := str(ability.get("type", ""))
	var e := str(ability.get("effect", ""))
	match t:
		"revival":
			return "revive"
		"mp_restore":
			return "mp"
		"healing":
			if e == "regen":
				return "regen"
			return "heal" if int(ability.get("heal_amount", 0)) > 0 else ""
		"support":
			if e == "cleanse" or e == "regen":
				return e
	return ""


static func castable(ability: Dictionary) -> bool:
	return kind(ability) != ""


## Who the player picks: "self" casts on the caster, "all" on the party, "one" asks for a target.
static func target_mode(ability: Dictionary) -> String:
	match str(ability.get("target_type", "single_ally")):
		"self":
			return "self"
		"all_allies", "all_dead_allies":
			return "all"
	return "one"


## Why this ability would do nothing to `target`, in the player's words; "" when it would land.
static func refusal(ability: Dictionary, target: Combatant) -> String:
	if target == null or not is_instance_valid(target):
		return "No one to cast on."
	var who := str(target.combatant_name)
	match kind(ability):
		"revive":
			if target.is_alive:
				return "%s isn't down." % who
			if not target.can_be_revived():
				return "%s is beyond reviving." % who
			return ""
		"":
			return "That only works in battle."
	if not target.is_alive:
		return "%s is down. Only a revival reaches them." % who
	match kind(ability):
		"heal", "regen":
			if target.current_hp >= target.max_hp:
				return "%s is already at full HP." % who
		"mp":
			if target.current_mp >= target.max_mp:
				return "%s's MP is already full." % who
		"cleanse":
			if _ailments(target).is_empty():
				return "%s has nothing to cure." % who
	return ""


## Cast `ability_id` from `caster` on `targets`. MP is spent only when at least one target is helped.
## Returns {"ok": bool, "text": String} — the text is what the menu shows either way.
static func cast(caster: Combatant, ability_id: String, targets: Array) -> Dictionary:
	var ability: Dictionary = JobSystem.get_ability(ability_id)
	if ability.is_empty() or not castable(ability):
		return {"ok": false, "text": "That only works in battle."}
	if caster == null or not is_instance_valid(caster) or not caster.is_alive:
		return {"ok": false, "text": "A fallen caster can't cast."}
	var cost: int = int(JobSystem.get_ability_mp_cost(caster, ability_id))
	if caster.current_mp < cost:
		return {"ok": false, "text": "Not enough MP (%d needed)." % cost}
	var helped: Array[String] = []
	var first_refusal := ""
	for t in targets:
		var why := refusal(ability, t)
		if why != "":
			if first_refusal == "":
				first_refusal = why
			continue
		helped.append(_apply(caster, ability, t))
	if helped.is_empty():
		return {"ok": false, "text": first_refusal if first_refusal != "" else "No one needed it."}
	caster.spend_mp(cost)
	return {"ok": true, "text": " ".join(helped)}


static func _apply(caster: Combatant, ability: Dictionary, t: Combatant) -> String:
	var who := str(t.combatant_name)
	match kind(ability):
		"heal":
			return "%s recovers %d HP." % [who, t.heal(BattleManager.heal_cast_amount(caster, ability))]
		"regen":
			## The whole regen in one go: per-turn (authored, or the 5%-of-max tick Combatant uses) x its turns.
			var per: int = int(ability.get("regen_per_turn", 0))
			if per <= 0:
				per = max(1, int(t.max_hp * 0.05))
			return "%s recovers %d HP." % [who, t.heal(per * int(ability.get("duration", 3)))]
		"revive":
			t.revive(int(t.max_hp * float(ability.get("revive_percentage", 50)) / 100.0))
			if not t.is_alive:
				return "%s is beyond reviving." % who
			return "%s is revived with %d HP." % [who, t.current_hp]
		"mp":
			var before: int = t.current_mp
			t.current_mp = min(t.max_mp, t.current_mp + BattleManager._mp_restore_amount(ability))
			return "%s restores %d MP." % [who, t.current_mp - before]
		"cleanse":
			var cured := _ailments(t)
			for s in cured:
				t.remove_status(s)
			if t.doom_counter > 0:
				t.doom_counter = 0
			return "%s is cured of %s." % [who, ", ".join(cured)]
	return ""


static func _ailments(t: Combatant) -> Array[String]:
	var out: Array[String] = []
	for s in BattleManager.ESUNA_AILMENTS:
		if t.has_status(s):
			out.append(s)
	if t.doom_counter > 0 and not ("doom" in out):
		out.append("doom")
	return out
