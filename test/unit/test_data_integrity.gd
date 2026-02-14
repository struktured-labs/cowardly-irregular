extends GutTest

## Data integrity tests
## Verifies all JSON data files are consistent and cross-references are valid
## Loads data directly from JSON files - no autoload singletons needed

var _items: Dictionary
var _weapons: Dictionary
var _armors: Dictionary
var _accessories: Dictionary
var _jobs: Dictionary
var _abilities: Dictionary
var _passives: Dictionary


func _load_json(path: String) -> Variant:
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		return null
	var json = JSON.new()
	var error = json.parse(file.get_as_text())
	file.close()
	if error != OK:
		return null
	return json.data


func before_all() -> void:
	_items = _load_json("res://data/items.json")
	if _items == null:
		_items = {}

	var equipment = _load_json("res://data/equipment.json")
	if equipment != null:
		_weapons = equipment.get("weapons", {})
		_armors = equipment.get("armors", {})
		_accessories = equipment.get("accessories", {})
	else:
		_weapons = {}
		_armors = {}
		_accessories = {}

	_jobs = _load_json("res://data/jobs.json")
	if _jobs == null:
		_jobs = {}

	_abilities = _load_json("res://data/abilities.json")
	if _abilities == null:
		_abilities = {}

	_passives = _load_json("res://data/passives.json")
	if _passives == null:
		_passives = {}


## ---- Data Files Load Successfully ----

func test_items_json_loads() -> void:
	assert_gt(_items.size(), 0, "items.json should load and have entries")


func test_equipment_json_loads() -> void:
	assert_gt(_weapons.size(), 0, "equipment.json should have weapons")
	assert_gt(_armors.size(), 0, "equipment.json should have armors")
	assert_gt(_accessories.size(), 0, "equipment.json should have accessories")


func test_jobs_json_loads() -> void:
	assert_gt(_jobs.size(), 0, "jobs.json should load and have entries")


func test_abilities_json_loads() -> void:
	assert_gt(_abilities.size(), 0, "abilities.json should load and have entries")


func test_passives_json_loads() -> void:
	assert_gt(_passives.size(), 0, "passives.json should load and have entries")


## ---- Minimum Counts ----

func test_minimum_item_count() -> void:
	assert_gte(_items.size(), 25, "Should have at least 25 items (got %d)" % _items.size())


func test_minimum_weapon_count() -> void:
	assert_gte(_weapons.size(), 19, "Should have at least 19 weapons (got %d)" % _weapons.size())


func test_minimum_armor_count() -> void:
	assert_gte(_armors.size(), 12, "Should have at least 12 armors (got %d)" % _armors.size())


func test_minimum_job_count() -> void:
	assert_gte(_jobs.size(), 12, "Should have at least 12 jobs (got %d)" % _jobs.size())


func test_minimum_ability_count() -> void:
	assert_gte(_abilities.size(), 50, "Should have at least 50 abilities (got %d)" % _abilities.size())


func test_minimum_passive_count() -> void:
	assert_gte(_passives.size(), 30, "Should have at least 30 passives (got %d)" % _passives.size())


## ---- Shop Inventory vs Data Files ----

func test_all_shop_items_exist() -> void:
	"""Every item in VillageShop.ITEM_INVENTORY must exist in items.json"""
	var shop_items = [
		"potion", "antidote", "eye_drops", "echo_herbs", "smoke_bomb",
		"hi_potion", "ether", "phoenix_down", "gold_needle",
		"power_drink", "speed_tonic", "defense_tonic", "magic_tonic",
		"bomb_fragment", "lightning_bolt", "holy_water",
		"remedy", "repel", "x_potion", "hi_ether",
	]

	for item_id in shop_items:
		assert_true(_items.has(item_id),
			"Shop item '%s' not found in items.json" % item_id)


func test_all_shop_items_have_cost() -> void:
	"""Every shop item must have a cost field for the shop to display prices"""
	var shop_items = [
		"potion", "antidote", "eye_drops", "echo_herbs", "smoke_bomb",
		"hi_potion", "ether", "phoenix_down", "gold_needle",
		"power_drink", "speed_tonic", "defense_tonic", "magic_tonic",
		"bomb_fragment", "lightning_bolt", "holy_water",
		"remedy", "repel", "x_potion", "hi_ether",
	]

	for item_id in shop_items:
		if _items.has(item_id):
			assert_true(_items[item_id].has("cost"),
				"Shop item '%s' must have a cost field" % item_id)
			if _items[item_id].has("cost"):
				assert_gt(_items[item_id]["cost"], 0,
					"Shop item '%s' cost should be > 0" % item_id)


func test_all_blacksmith_weapons_exist() -> void:
	"""Every weapon in VillageShop.BLACKSMITH_WEAPONS must exist in equipment.json"""
	var blacksmith_weapons = [
		"bronze_sword", "iron_dagger", "wooden_staff", "bone_staff",
		"iron_sword", "poison_dagger", "oak_staff", "sleep_dagger",
		"steel_sword", "shadow_rod", "war_axe", "thunder_rod",
		"mythril_dagger", "ice_blade", "flame_sword", "crystal_staff",
		"assassin_blade", "mythril_sword", "holy_staff"
	]

	for weapon_id in blacksmith_weapons:
		assert_true(_weapons.has(weapon_id),
			"Blacksmith weapon '%s' not found in equipment.json" % weapon_id)


func test_all_blacksmith_weapons_have_cost() -> void:
	var blacksmith_weapons = [
		"bronze_sword", "iron_dagger", "wooden_staff", "bone_staff",
		"iron_sword", "poison_dagger", "oak_staff", "sleep_dagger",
		"steel_sword", "shadow_rod", "war_axe", "thunder_rod",
		"mythril_dagger", "ice_blade", "flame_sword", "crystal_staff",
		"assassin_blade", "mythril_sword", "holy_staff"
	]

	for weapon_id in blacksmith_weapons:
		if _weapons.has(weapon_id):
			assert_true(_weapons[weapon_id].has("cost"),
				"Weapon '%s' must have a cost field for shop" % weapon_id)


func test_all_blacksmith_armor_exists() -> void:
	var blacksmith_armor = [
		"leather_armor", "cloth_robe", "thief_garb",
		"bone_armor", "chain_mail", "dark_robe",
		"iron_armor", "mage_robe", "ninja_garb",
		"sage_robe", "mythril_vest", "dragon_mail"
	]

	for armor_id in blacksmith_armor:
		assert_true(_armors.has(armor_id),
			"Blacksmith armor '%s' not found in equipment.json" % armor_id)


func test_all_blacksmith_armor_has_cost() -> void:
	var blacksmith_armor = [
		"leather_armor", "cloth_robe", "thief_garb",
		"bone_armor", "chain_mail", "dark_robe",
		"iron_armor", "mage_robe", "ninja_garb",
		"sage_robe", "mythril_vest", "dragon_mail"
	]

	for armor_id in blacksmith_armor:
		if _armors.has(armor_id):
			assert_true(_armors[armor_id].has("cost"),
				"Armor '%s' must have a cost field for shop" % armor_id)


func test_all_magic_shop_spells_exist() -> void:
	"""All spells sold in magic shops must exist in abilities.json"""
	var black_magic = ["fire", "blizzard", "thunder", "fira"]
	var white_magic = ["cure", "cura", "raise", "protect"]

	for spell_id in black_magic:
		assert_true(_abilities.has(spell_id),
			"Black magic spell '%s' not found in abilities.json" % spell_id)

	for spell_id in white_magic:
		assert_true(_abilities.has(spell_id),
			"White magic spell '%s' not found in abilities.json" % spell_id)


func test_all_magic_shop_spells_have_cost() -> void:
	var all_spells = ["fire", "blizzard", "thunder", "fira", "cure", "cura", "raise", "protect"]

	for spell_id in all_spells:
		if _abilities.has(spell_id):
			assert_true(_abilities[spell_id].has("cost"),
				"Magic spell '%s' must have a cost field for shop" % spell_id)


## ---- Job Abilities Cross-References ----

func test_all_job_passive_abilities_exist() -> void:
	"""Every passive referenced by a job in jobs.json must exist in passives.json"""
	for job_id in _jobs:
		var job = _jobs[job_id]
		for passive_id in job.get("passive_abilities", []):
			assert_true(_passives.has(passive_id),
				"Job '%s' references passive '%s' which doesn't exist in passives.json" % [job_id, passive_id])


func test_all_job_abilities_exist() -> void:
	"""Every ability referenced by a job must exist in abilities.json"""
	for job_id in _jobs:
		var job = _jobs[job_id]
		for ability_id in job.get("abilities", []):
			assert_true(_abilities.has(ability_id),
				"Job '%s' references ability '%s' which doesn't exist in abilities.json" % [job_id, ability_id])


## ---- Item Data Validation ----

func test_all_items_have_required_fields() -> void:
	for item_id in _items:
		var item = _items[item_id]
		assert_true(item.has("name"), "Item '%s' should have name" % item_id)
		assert_true(item.has("description"), "Item '%s' should have description" % item_id)
		assert_true(item.has("cost"), "Item '%s' should have cost" % item_id)


## ---- Equipment Data Validation ----

func test_all_weapons_have_names() -> void:
	for weapon_id in _weapons:
		assert_true(_weapons[weapon_id].has("name"),
			"Weapon '%s' should have a name" % weapon_id)


func test_all_armors_have_names() -> void:
	for armor_id in _armors:
		assert_true(_armors[armor_id].has("name"),
			"Armor '%s' should have a name" % armor_id)


func test_all_accessories_have_names() -> void:
	for acc_id in _accessories:
		assert_true(_accessories[acc_id].has("name"),
			"Accessory '%s' should have a name" % acc_id)


## ---- Ability Data Validation ----

func test_all_abilities_have_required_fields() -> void:
	for ability_id in _abilities:
		var ability = _abilities[ability_id]
		assert_true(ability.has("id"), "Ability '%s' should have id" % ability_id)
		assert_true(ability.has("name"), "Ability '%s' should have name" % ability_id)
		assert_true(ability.has("description"), "Ability '%s' should have description" % ability_id)


## ---- Passive Data Validation ----

func test_all_passives_have_required_fields() -> void:
	for passive_id in _passives:
		var passive = _passives[passive_id]
		assert_true(passive.has("id"), "Passive '%s' should have id" % passive_id)
		assert_true(passive.has("name"), "Passive '%s' should have name" % passive_id)


## ---- Job Data Validation ----

func test_all_expected_jobs_exist() -> void:
	var expected_jobs = [
		"fighter", "white_mage", "black_mage", "thief",
		"guardian", "ninja", "summoner",
		"scriptweaver", "time_mage", "necromancer", "bossbinder", "skiptrotter"
	]
	for job_id in expected_jobs:
		assert_true(_jobs.has(job_id),
			"jobs.json should contain job: %s" % job_id)


func test_all_jobs_have_required_fields() -> void:
	for job_id in _jobs:
		var job = _jobs[job_id]
		assert_true(job.has("id"), "Job '%s' should have id" % job_id)
		assert_true(job.has("name"), "Job '%s' should have name" % job_id)
		assert_true(job.has("type"), "Job '%s' should have type" % job_id)
		assert_true(job.has("stat_modifiers"), "Job '%s' should have stat_modifiers" % job_id)
		assert_true(job.has("abilities"), "Job '%s' should have abilities" % job_id)
		assert_true(job.has("visual"), "Job '%s' should have visual" % job_id)


func test_job_types_are_valid() -> void:
	"""Job types: 0=starter, 1=advanced, 2=meta"""
	for job_id in _jobs:
		var job = _jobs[job_id]
		var job_type = int(job["type"])
		assert_true(job_type in [0, 1, 2],
			"Job '%s' type should be 0, 1, or 2 (got %d)" % [job_id, job_type])


func test_starter_jobs_have_type_zero() -> void:
	for job_id in ["fighter", "white_mage", "black_mage", "thief"]:
		if _jobs.has(job_id):
			assert_eq(int(_jobs[job_id]["type"]), 0,
				"%s should be type 0 (starter)" % job_id)


func test_all_job_stat_modifiers_have_valid_keys() -> void:
	var valid_stats = ["max_hp", "max_mp", "attack", "defense", "magic", "speed"]
	for job_id in _jobs:
		var mods = _jobs[job_id].get("stat_modifiers", {})
		for stat in mods:
			assert_true(stat in valid_stats,
				"Job '%s' has invalid stat modifier: %s" % [job_id, stat])
