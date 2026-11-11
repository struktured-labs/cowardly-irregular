extends RefCounted
class_name AbilityCost

## What an action costs in AP, ONE place for the live menu, the live engine and the headless resolver (scene-free).
## A slot bills 1 AP (the Advance rule) plus its ability's own `ap_cost`, and a queue must stay at or above AP_FLOOR
## (BD's -4; struktured 2026-11-07: "an ability that takes +1 AP ... should account for that the same way BD does").
## `bp_cost` is NOT read: All In (brave) GRANTS AP, so billing its bp_cost would make it net 0, a dead button. It stays
## declared unbuilt until struktured rules on real BD Brave (cowir-battle 23478, main 23481 option a).

const AP_FLOOR := Combatant.AP_FLOOR


## The EXTRA AP an ability costs beyond its slot's 1. 0 unless the ability authors `ap_cost`.
static func ap_for(_combatant, ability_id: String) -> int:
	return maxi(0, int(_ability(ability_id).get("ap_cost", 0)))


## What one queued slot bills: 1 + its ability's ap_cost, 1 for an attack or item, 0 for a defer.
static func slot_ap(combatant, action: Dictionary) -> int:
	match str(action.get("type", "")):
		"defer":
			return 0
		"ability":
			return 1 + ap_for(combatant, str(action.get("ability_id", "")))
		_:
			return 1


static func queue_fits(combatant, actions: Array) -> bool:
	var total := 0
	for a in actions:
		if a is Dictionary:
			total += slot_ap(combatant, a)
	return int(combatant.current_ap) - total >= AP_FLOOR


static func _ability(ability_id: String) -> Dictionary:
	var tree := Engine.get_main_loop() as SceneTree
	var js = tree.root.get_node_or_null("JobSystem") if tree and tree.root else null
	return js.get_ability(ability_id) if js else {}
