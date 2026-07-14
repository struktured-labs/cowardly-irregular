class_name ItemNameResolver
extends RefCounted

## Tick 135: shared resolver for canonical display names. Ticks
## 130-134 added three near-identical copies of this logic across
## BestiaryMenu, TreasureChest, VillageShop — and tick 133 caught
## a singular-vs-plural typo (`"armor"` vs the actual `armors`
## field) that was locked in by one of those copies' tests. Extract
## once so future fixes touch one file.
##
## Resolution order (cheapest, most-common first):
##   1. ItemSystem.get_item     — consumables, main item table
##   2. JobSystem.get_ability   — spells (shop-sold magic, drops)
##   3. EquipmentSystem pools   — weapons, armors (PLURAL),
##                                accessories
##   4. Prettifier fallback     — replace+capitalize, for ids none
##                                of the autoloads know (debug,
##                                Scriptweaver custom, save-drift)
##
## All steps are defensive: missing autoload, missing method,
## empty dict, dict-without-name field — every failure mode falls
## through gracefully.


static func resolve(item_id: String) -> String:
	if item_id == "":
		return ""
	var item_sys = Engine.get_main_loop().root.get_node_or_null("ItemSystem")
	if item_sys != null and item_sys.has_method("get_item"):
		var data: Dictionary = item_sys.get_item(item_id)
		if not data.is_empty() and data.has("name"):
			return str(data["name"])
	var job_sys = Engine.get_main_loop().root.get_node_or_null("JobSystem")
	if job_sys != null and job_sys.has_method("get_ability"):
		var ab: Dictionary = job_sys.get_ability(item_id)
		if not ab.is_empty() and ab.has("name"):
			return str(ab["name"])
	var equip_sys = Engine.get_main_loop().root.get_node_or_null("EquipmentSystem")
	if equip_sys != null:
		for pool_name in ["weapons", "armors", "accessories"]:
			if pool_name in equip_sys:
				var pool: Dictionary = equip_sys[pool_name]
				if pool.has(item_id) and pool[item_id] is Dictionary:
					var name = str(pool[item_id].get("name", ""))
					if name != "":
						return name
	return item_id.replace("_", " ").capitalize()
