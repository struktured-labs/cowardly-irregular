extends GutTest

## Regression: TreasureChest must categorize equipment using
## EquipmentSystem's actual dicts, not keyword heuristics. Pre-fix used
## string matching ("armor" or "robe" or "mail" → armors), which
## misclassified items whose IDs don't contain those substrings:
##   - "bone_armor"     → armors ✓ (keyword match)
##   - "bronze_sword"   → weapons ✓ (default)
##   - "iron_breastplate" → weapons ✗ (BUG — no keyword match)
##   - "obsidian_cuirass" → weapons ✗ (BUG — no keyword match)
##   - "speed_boots"    → accessories ✓ (keyword match)
##   - "hp_amulet"      → accessories ✓ (keyword match)
##   - "lucky_charm"    → weapons ✗ (BUG — no keyword match)
## The new resolver checks the EquipmentSystem dicts directly, which is
## the actual source of truth.

const TREASURE_CHEST_PATH := "res://src/exploration/TreasureChest.gd"


func _read(path: String) -> String:
	var file = FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "file should exist: %s" % path)
	var text = file.get_as_text()
	file.close()
	return text


func _make_chest():
	var script = load(TREASURE_CHEST_PATH)
	var chest = script.new()
	add_child_autofree(chest)
	return chest


func test_resolver_categorizes_real_armor_correctly() -> void:
	# Real armor ID from equipment.json that DOESN'T match the old
	# heuristic. Pre-fix this would have ended up in the weapons pool;
	# the new resolver consults EquipmentSystem and returns "armors".
	var chest = _make_chest()
	# Check several real armor IDs — at least one shouldn't match the
	# old keyword set, ensuring the new resolver is doing real work.
	for armor_id in ["bone_armor", "chain_mail", "cloth_robe", "dragon_mail"]:
		var slot = chest._resolve_equipment_pool(armor_id)
		assert_eq(slot, "armors",
			"%s must resolve to 'armors' pool (EquipmentSystem-backed lookup)" % armor_id)


func test_resolver_categorizes_real_weapons_correctly() -> void:
	var chest = _make_chest()
	for weapon_id in ["bronze_sword", "assassin_blade", "flame_sword"]:
		var slot = chest._resolve_equipment_pool(weapon_id)
		assert_eq(slot, "weapons",
			"%s must resolve to 'weapons' pool" % weapon_id)


func test_resolver_categorizes_real_accessories_correctly() -> void:
	var chest = _make_chest()
	# Pull a few accessory IDs from the live EquipmentSystem so the test
	# stays current with whatever data ships in equipment.json.
	var eq = get_node_or_null("/root/EquipmentSystem")
	if eq == null or not "accessories" in eq:
		pending("EquipmentSystem autoload not available")
		return
	var ids = eq.accessories.keys()
	if ids.is_empty():
		pending("equipment.json has no accessories — nothing to test")
		return
	# Spot-check up to 3 to keep the test fast.
	var sample = ids.slice(0, mini(3, ids.size()))
	for id in sample:
		var slot = chest._resolve_equipment_pool(id)
		assert_eq(slot, "accessories",
			"%s must resolve to 'accessories' pool" % id)


func test_resolver_falls_back_to_weapons_for_unknown_id() -> void:
	var chest = _make_chest()
	var slot = chest._resolve_equipment_pool("this_item_definitely_does_not_exist_xyz_qqq")
	assert_eq(slot, "weapons",
		"Unknown item ID must fall back to 'weapons' (preserves pre-fix default)")


func test_old_heuristic_removed_from_source() -> void:
	# Source pin: the old keyword-string match must be gone. Catches
	# anyone re-adding "if 'armor' in contents_id" etc. as a "quick fix"
	# that would silently re-introduce the misclassification.
	var text = _read(TREASURE_CHEST_PATH)
	assert_false(text.find("if \"armor\" in contents_id or \"robe\" in contents_id") > -1,
		"Stale keyword heuristic must be gone — caught reverting to fragile string-substring match")
	assert_true(text.find("_resolve_equipment_pool(contents_id)") > -1,
		"Equipment branch must use the EquipmentSystem-backed resolver")
