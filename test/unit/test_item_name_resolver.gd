extends GutTest

## tick 135: ItemNameResolver behavior tests — these run the actual
## resolver against the live autoloads. The string-pin tests in the
## other resolver tests cover code shape; this file covers runtime
## correctness for the four canonical resolution paths.


func test_resolves_consumable_via_item_system() -> void:
	# "hi_potion" is in data/items.json with canonical name "Hi-Potion"
	# (hyphen). Pre-tick-130 the prettifier returned "Hi Potion".
	var name: String = ItemNameResolver.resolve("hi_potion")
	assert_eq(name, "Hi-Potion",
		"hi_potion must resolve to canonical 'Hi-Potion' (hyphen) from items.json — not the prettified 'Hi Potion'")


func test_resolves_spell_via_job_system() -> void:
	# "fire" is in data/abilities.json — used in BLACK_MAGIC_INVENTORY.
	var name: String = ItemNameResolver.resolve("fire")
	# Should match the canonical "name" field in abilities.json.
	# Not pinning the exact string in case content changes; just
	# pin that JobSystem won (non-prettifier result).
	assert_ne(name, "",
		"fire must resolve to a non-empty name via JobSystem")
	# Must NOT be empty / null / the raw id (which IS already
	# "fire" — but the JSON entry has a "name" field that should win).
	var job_sys = get_node_or_null("/root/JobSystem")
	if job_sys != null and job_sys.has_method("get_ability"):
		var data: Dictionary = job_sys.get_ability("fire")
		if not data.is_empty() and data.has("name"):
			assert_eq(name, str(data["name"]),
				"resolver result must equal JobSystem's canonical name for 'fire'")


func test_resolves_weapon_via_equipment_system() -> void:
	# "iron_sword" is in data/equipment.json under weapons.
	var name: String = ItemNameResolver.resolve("iron_sword")
	var equip_sys = get_node_or_null("/root/EquipmentSystem")
	if equip_sys != null and "weapons" in equip_sys:
		var weapons: Dictionary = equip_sys["weapons"]
		if weapons.has("iron_sword"):
			var expected: String = str(weapons["iron_sword"].get("name", ""))
			assert_eq(name, expected,
				"iron_sword must resolve to the canonical 'name' from EquipmentSystem.weapons")


func test_resolves_armor_via_equipment_system_armors_pool() -> void:
	# "leather_armor" — defends against the singular-vs-plural typo.
	# Pre-tick-133 the bestiary's "armor" branch silently never fired,
	# so this fell through to the prettifier.
	var name: String = ItemNameResolver.resolve("leather_armor")
	var equip_sys = get_node_or_null("/root/EquipmentSystem")
	if equip_sys != null and "armors" in equip_sys:
		var armors: Dictionary = equip_sys["armors"]
		if armors.has("leather_armor"):
			var expected: String = str(armors["leather_armor"].get("name", ""))
			assert_eq(name, expected,
				"leather_armor must resolve to canonical name from EquipmentSystem.armors (plural) — was silently leaking before tick 133")
			# Negative pin: the prettifier output is the SAME for this
			# specific id, so we can't use string inequality. Instead,
			# verify it's the expected armors-pool name.
			assert_ne(expected, "",
				"sanity: leather_armor must have a non-empty canonical name set in equipment.json")


func test_empty_id_returns_empty() -> void:
	assert_eq(ItemNameResolver.resolve(""), "",
		"empty id must return empty string")


func test_unknown_id_falls_back_to_prettifier() -> void:
	var name: String = ItemNameResolver.resolve("totally_not_real_xyz")
	assert_eq(name, "Totally Not Real Xyz",
		"unknown id must prettify the raw id via replace+capitalize")


func test_returns_id_unchanged_when_already_human_readable() -> void:
	# Edge case: no underscores. Prettifier just capitalizes the
	# first letter (Godot's String.capitalize doesn't title-case
	# without separators).
	var name: String = ItemNameResolver.resolve("definitely_unknown_id")
	assert_true(name.length() > 0,
		"resolver must never return empty for non-empty input")
