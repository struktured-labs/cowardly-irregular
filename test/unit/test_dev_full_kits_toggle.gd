extends GutTest

## Item 18 part 2 — "we can toggle that in settings though as
## 'developer mode' for me to test things easier" (user). ON grants
## every level-gated ability to the party; OFF strips exactly the
## unlocks ABOVE each member's level, so legitimately-earned spells
## survive the round trip. Deterministic from data — no grant markers.


func _mage_at(level: int) -> Combatant:
	var c := Combatant.new()
	add_child_autofree(c)
	c.initialize({"name": "KitMage", "max_hp": 80, "max_mp": 60,
		"attack": 5, "defense": 5, "magic": 12, "speed": 8})
	c.job_level = level
	assert_true(JobSystem.assign_job(c, "mage"))
	return c


func test_toggle_on_grants_everything() -> void:
	var c := _mage_at(1)
	assert_does_not_have(c.learned_abilities, "firaga")
	JobSystem.set_dev_full_kits(true, [c])
	for aid in ["fira", "blizzara", "thundara", "firaga", "blizzaga", "thundaga"]:
		assert_has(c.learned_abilities, aid, "dev ON must grant %s" % aid)


func test_toggle_off_strips_only_above_level() -> void:
	var c := _mage_at(7)  # legitimately has fira(6) + blizzara(7)
	JobSystem.set_dev_full_kits(true, [c])
	JobSystem.set_dev_full_kits(false, [c])
	assert_has(c.learned_abilities, "fira", "earned unlock must survive dev OFF")
	assert_has(c.learned_abilities, "blizzara", "earned unlock must survive dev OFF")
	assert_does_not_have(c.learned_abilities, "firaga", "above-level grant must strip on dev OFF")
	assert_does_not_have(c.learned_abilities, "thundaga", "above-level grant must strip on dev OFF")


func test_purchased_spells_survive_dev_off() -> void:
	# Item 18 part 3: a level-1 mage BUYS fira at the magic shop, then
	# toggles dev kits on and off — the strip must never repossess
	# gold-paid knowledge.
	var c := _mage_at(1)
	c.learn_ability("fira")
	c.purchased_abilities.append("fira")
	JobSystem.set_dev_full_kits(true, [c])
	JobSystem.set_dev_full_kits(false, [c])
	assert_has(c.learned_abilities, "fira", "purchased spell must survive the dev-OFF strip")
	assert_does_not_have(c.learned_abilities, "firaga", "unpurchased above-level grants still strip")


func test_purchased_abilities_roundtrip_save() -> void:
	var c := _mage_at(1)
	c.learn_ability("fira")
	c.purchased_abilities.append("fira")
	var data: Dictionary = c.to_dict()
	var c2 := Combatant.new()
	add_child_autofree(c2)
	c2.from_dict(data)
	assert_has(c2.purchased_abilities, "fira",
		"purchased marker must survive the save roundtrip (typed-array coercion)")


func test_w1_magic_shops_stock_full_tier2() -> void:
	var VS = load("res://src/exploration/VillageShop.gd")
	for spell in ["fira", "blizzara", "thundara"]:
		assert_has(VS.BLACK_MAGIC_INVENTORY, spell)
	for spell in ["cura", "esuna", "regen", "raise"]:
		assert_has(VS.WHITE_MAGIC_INVENTORY, spell)
	for spell in VS.BLACK_MAGIC_INVENTORY + VS.WHITE_MAGIC_INVENTORY:
		var a: Dictionary = JobSystem.get_ability(str(spell))
		assert_false(a.is_empty(), "stocked spell %s must resolve" % spell)
		assert_gt(int(a.get("cost", 0)), 0, "stocked spell %s needs a price" % spell)


func test_settings_menu_wires_the_toggle() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/ui/SettingsMenu.gd")
	assert_true(src.contains("\"dev_full_kits\""), "settings item must exist")
	assert_true(src.contains("_apply_dev_full_kits()"), "flip must apply grant/strip")
	assert_true(src.contains("game_constants.get(\"dev_full_kits\""),
		"toggle state must reload from game_constants")
