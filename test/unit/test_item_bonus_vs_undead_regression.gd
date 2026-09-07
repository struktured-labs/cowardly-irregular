extends GutTest

## Regression: items with `bonus_vs_undead: true` (holy_water) must deal
## 2x damage vs monsters flagged `undead: true` in the bestiary
## (skeleton, specter, cursed_armor, pipe_phantom, data_wraith).
## Pre-fix the flag was set in items.json and on 5 monsters but
## ItemSystem.use_item never read it — holy_water dealt flat damage
## regardless of target type, indistinguishable from a generic damage
## potion. Silent design failure.

const ITEM_SYSTEM_PATH := "res://src/items/ItemSystem.gd"
const COMBATANT_PATH := "res://src/battle/Combatant.gd"


func _read(path: String) -> String:
	var file = FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "file should exist: %s" % path)
	var text = file.get_as_text()
	file.close()
	return text


func _make_combatant(name_str: String) -> Combatant:
	var script = load(COMBATANT_PATH)
	var c = script.new()
	c.initialize({"name": name_str, "max_hp": 1000, "max_mp": 100,
		"attack": 10, "defense": 10, "magic": 10, "speed": 10})
	return c


func test_use_item_damage_branch_reads_bonus_vs_undead() -> void:
	var text = _read(ITEM_SYSTEM_PATH)
	# Source pin: the damage block must read effects.bonus_vs_undead.
	# Catches anyone removing the bonus path or letting it become dead code.
	var damage_idx = text.find("if effects.has(\"damage\"):")
	assert_true(damage_idx > -1, "damage branch must exist")
	# Window from damage branch to the next major section.
	var window = text.substr(damage_idx, 1200)
	assert_true(window.find("bonus_vs_undead") > -1,
		"damage branch must read effects.bonus_vs_undead flag")
	assert_true(window.find("_is_target_undead(target)") > -1,
		"damage branch must call _is_target_undead helper for the lookup")
	# Multiplier path must apply 2.0 (the bonus). Catches anyone setting
	# it to 1.5 or some other value by mistake.
	assert_true(window.find("multiplier *= 2.0") > -1,
		"bonus_vs_undead must multiply damage by 2x — that's the design intent")


func test_is_target_undead_helper_safe_on_null_target() -> void:
	# Behavioral: helper must return false safely when target is null
	# or has no monster_type meta (PC), or the monster_type is unknown.
	if not ItemSystem:
		pending("ItemSystem autoload missing")
		return

	assert_false(ItemSystem._is_target_undead(null),
		"null target must return false (defensive guard)")

	# PC-like Combatant with no monster_type meta — must NOT be flagged
	# as undead (would break holy_water in PvP-style item tests).
	var pc = _make_combatant("Hero")
	assert_false(ItemSystem._is_target_undead(pc),
		"Combatant without monster_type meta (PC) must NOT be flagged undead")
	pc.free()

	# Monster with monster_type meta but bestiary doesn't know it — must
	# return false (unknown monster shouldn't crash or claim undead).
	var stranger = _make_combatant("Mystery")
	stranger.set_meta("monster_type", "this_monster_does_not_exist_xyz")
	assert_false(ItemSystem._is_target_undead(stranger),
		"Unknown monster_type must return false (bestiary safe lookup)")
	stranger.free()


func test_is_target_undead_recognizes_real_undead_monsters() -> void:
	if not ItemSystem:
		pending("ItemSystem autoload missing")
		return
	# Sample at least one monster flagged `undead: true` in monsters.json.
	# Test stays current with data updates because it uses the live
	# bestiary, not a hard-coded ID list.
	for undead_id in ["skeleton", "specter", "cursed_armor"]:
		var data: Dictionary = BestiarySystem.get_monster_data(undead_id)
		if data.is_empty() or not data.get("undead", false):
			continue  # Skip if bestiary content changed and this id isn't undead
		var c = _make_combatant("Test_" + undead_id)
		c.set_meta("monster_type", undead_id)
		assert_true(ItemSystem._is_target_undead(c),
			"%s (undead in bestiary) must be flagged by _is_target_undead" % undead_id)
		c.free()


func test_holy_water_does_2x_damage_to_undead() -> void:
	# Behavioral: cast holy_water effects on an undead vs a non-undead.
	# Damage on undead should be 2x of damage on non-undead with all other
	# variables held constant.
	if not ItemSystem:
		pending("ItemSystem autoload missing")
		return

	var undead = _make_combatant("TestSkeleton")
	undead.set_meta("monster_type", "skeleton")
	var living = _make_combatant("TestSlime")
	living.set_meta("monster_type", "slime")

	var hp_undead_before = undead.current_hp
	var hp_living_before = living.current_hp

	# Synthesize holy_water-shape item.
	var holy = {
		"id": "holy_water_test",
		"name": "Test Holy Water",
		"category": ItemSystem.ItemCategory.OFFENSIVE,
		"target_type": ItemSystem.TargetType.SINGLE_ENEMY,
		"effects": {
			"damage": 100,
			"element": "holy",
			"bonus_vs_undead": true,
		},
	}
	# Inject into ItemSystem for the duration of the test.
	var prev_item = ItemSystem.items.get("holy_water_test", {})
	ItemSystem.items["holy_water_test"] = holy

	var user = _make_combatant("Caster")
	ItemSystem.use_item(user, "holy_water_test", [undead] as Array[Combatant])
	ItemSystem.use_item(user, "holy_water_test", [living] as Array[Combatant])

	var dmg_undead = hp_undead_before - undead.current_hp
	var dmg_living = hp_living_before - living.current_hp

	assert_gt(dmg_undead, dmg_living,
		"holy_water must deal MORE damage to undead than to non-undead (got %d vs %d)" % [
			dmg_undead, dmg_living])
	# Ratio check with wide tolerance: take_damage applies defense
	# subtraction AFTER the multiplier, so the ratio can drift slightly
	# above 2x (e.g. dmg=100, def=10 → 90 base; dmg=200, def=10 → 190
	# undead → ratio 2.11x). Accept anything in [1.7x, 2.5x] — the
	# design contract is "noticeably more damage", not a precise 2x.
	var ratio: float = float(dmg_undead) / float(max(1, dmg_living))
	assert_true(ratio >= 1.7 and ratio <= 2.5,
		"undead/non-undead damage ratio must be ~2x (got %.2f from dmg %d vs %d)" % [
			ratio, dmg_undead, dmg_living])

	# Restore.
	if prev_item.is_empty():
		ItemSystem.items.erase("holy_water_test")
	else:
		ItemSystem.items["holy_water_test"] = prev_item
	undead.free()
	living.free()
	user.free()
