extends GutTest

## Tests for job rename migration (v0.11.0)
## Covers: alias resolution, old save compatibility, data integrity post-rename

var _jobs: Dictionary
var _abilities: Dictionary
var _passives: Dictionary
var _aliases: Dictionary
var _lore: Dictionary


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
	_jobs = _load_json("res://data/jobs.json")
	if _jobs == null:
		_jobs = {}
	_abilities = _load_json("res://data/abilities.json")
	if _abilities == null:
		_abilities = {}
	_passives = _load_json("res://data/passives.json")
	if _passives == null:
		_passives = {}
	_aliases = _load_json("res://data/job_aliases.json")
	if _aliases == null:
		_aliases = {}
	_lore = _load_json("res://data/lore.json")
	if _lore == null:
		_lore = {}


## ---- Alias File ----

func test_alias_file_loads() -> void:
	assert_gt(_aliases.size(), 0, "job_aliases.json should load and have entries")


func test_alias_has_white_mage_to_cleric() -> void:
	assert_eq(_aliases.get("white_mage", ""), "cleric",
		"white_mage should alias to cleric")


func test_alias_has_black_mage_to_mage() -> void:
	assert_eq(_aliases.get("black_mage", ""), "mage",
		"black_mage should alias to mage")


func test_alias_has_thief_to_rogue() -> void:
	assert_eq(_aliases.get("thief", ""), "rogue",
		"thief should alias to rogue")


## ---- Alias Resolution via JobSystem ----

func test_resolve_job_id_via_job_system() -> void:
	var job_system = get_node_or_null("/root/JobSystem")
	if not job_system:
		pending("JobSystem not available")
		return

	assert_eq(job_system.resolve_job_id("white_mage"), "cleric",
		"resolve_job_id should map white_mage to cleric")
	assert_eq(job_system.resolve_job_id("black_mage"), "mage",
		"resolve_job_id should map black_mage to mage")
	assert_eq(job_system.resolve_job_id("thief"), "rogue",
		"resolve_job_id should map thief to rogue")


func test_resolve_job_id_identity_passthrough() -> void:
	var job_system = get_node_or_null("/root/JobSystem")
	if not job_system:
		pending("JobSystem not available")
		return

	assert_eq(job_system.resolve_job_id("fighter"), "fighter",
		"resolve_job_id should pass through non-aliased IDs")
	assert_eq(job_system.resolve_job_id("cleric"), "cleric",
		"resolve_job_id should pass through new IDs")
	assert_eq(job_system.resolve_job_id("bard"), "bard",
		"resolve_job_id should pass through bard")


func test_resolve_job_id_unknown_returns_unchanged() -> void:
	var job_system = get_node_or_null("/root/JobSystem")
	if not job_system:
		pending("JobSystem not available")
		return

	assert_eq(job_system.resolve_job_id("nonexistent"), "nonexistent",
		"resolve_job_id should return unknown IDs unchanged")


## ---- Old IDs Removed from jobs.json ----

func test_old_ids_not_in_jobs() -> void:
	assert_false(_jobs.has("white_mage"),
		"jobs.json should NOT have white_mage (renamed to cleric)")
	assert_false(_jobs.has("black_mage"),
		"jobs.json should NOT have black_mage (renamed to mage)")
	assert_false(_jobs.has("thief"),
		"jobs.json should NOT have thief (renamed to rogue)")


func test_new_ids_in_jobs() -> void:
	assert_true(_jobs.has("cleric"),
		"jobs.json should have cleric")
	assert_true(_jobs.has("mage"),
		"jobs.json should have mage")
	assert_true(_jobs.has("rogue"),
		"jobs.json should have rogue")


## ---- All 14 Jobs Load ----

func test_14_jobs_loaded() -> void:
	assert_eq(_jobs.size(), 14, "Should have exactly 14 jobs (got %d)" % _jobs.size())


func test_all_14_jobs_exist() -> void:
	var expected = [
		"fighter", "cleric", "mage", "rogue", "bard",
		"guardian", "ninja", "summoner", "speculator",
		"scriptweaver", "time_mage", "necromancer", "bossbinder", "skiptrotter"
	]
	for job_id in expected:
		assert_true(_jobs.has(job_id), "Should have job: %s" % job_id)


func test_5_starter_jobs() -> void:
	var starters = []
	for job_id in _jobs:
		if int(_jobs[job_id]["type"]) == 0:
			starters.append(job_id)
	assert_eq(starters.size(), 5, "Should have 5 starter jobs (got %d: %s)" % [starters.size(), starters])


func test_4_advanced_jobs() -> void:
	var advanced = []
	for job_id in _jobs:
		if int(_jobs[job_id]["type"]) == 1:
			advanced.append(job_id)
	assert_eq(advanced.size(), 4, "Should have 4 advanced jobs (got %d: %s)" % [advanced.size(), advanced])


func test_5_meta_jobs() -> void:
	var meta = []
	for job_id in _jobs:
		if int(_jobs[job_id]["type"]) == 2:
			meta.append(job_id)
	assert_eq(meta.size(), 5, "Should have 5 meta jobs (got %d: %s)" % [meta.size(), meta])


## ---- Evolution Data ----

func test_fighter_evolves_to_guardian() -> void:
	assert_true(_jobs["fighter"].has("evolution"), "Fighter should have evolution field")
	assert_eq(_jobs["fighter"]["evolution"]["target"], "guardian",
		"Fighter should evolve to guardian")
	assert_eq(int(_jobs["fighter"]["evolution"]["level_required"]), 5,
		"Fighter evolution should require level 5")


func test_rogue_evolves_to_ninja() -> void:
	assert_true(_jobs["rogue"].has("evolution"), "Rogue should have evolution field")
	assert_eq(_jobs["rogue"]["evolution"]["target"], "ninja",
		"Rogue should evolve to ninja")
	assert_eq(int(_jobs["rogue"]["evolution"]["level_required"]), 5,
		"Rogue evolution should require level 5")


func test_guardian_evolves_from_fighter() -> void:
	assert_true(_jobs["guardian"].has("evolves_from"), "Guardian should have evolves_from")
	assert_eq(_jobs["guardian"]["evolves_from"], "fighter",
		"Guardian should evolve from fighter")


func test_ninja_evolves_from_rogue() -> void:
	assert_true(_jobs["ninja"].has("evolves_from"), "Ninja should have evolves_from")
	assert_eq(_jobs["ninja"]["evolves_from"], "rogue",
		"Ninja should evolve from rogue")


func test_cleric_has_future_evolution_targets() -> void:
	assert_true(_jobs["cleric"].has("evolution"), "Cleric should have evolution field")
	var evo = _jobs["cleric"]["evolution"]
	assert_true(evo.has("future_targets"), "Cleric evolution should have future_targets")
	assert_true("high_priestess" in evo["future_targets"], "Cleric future: high_priestess")
	assert_true("paladin" in evo["future_targets"], "Cleric future: paladin")


func test_mage_has_future_evolution_targets() -> void:
	assert_true(_jobs["mage"].has("evolution"), "Mage should have evolution field")
	var evo = _jobs["mage"]["evolution"]
	assert_true(evo.has("future_targets"), "Mage evolution should have future_targets")
	assert_true("wizard" in evo["future_targets"], "Mage future: wizard")
	assert_true("dark_mage" in evo["future_targets"], "Mage future: dark_mage")


## ---- Lore Data ----

func test_lore_file_loads() -> void:
	assert_gt(_lore.size(), 0, "lore.json should load and have entries")


func test_lore_has_job_entries() -> void:
	assert_true(_lore.has("jobs"), "Lore should have 'jobs' section")
	var job_lore = _lore["jobs"]
	for job_id in ["fighter", "cleric", "mage", "rogue", "bard"]:
		assert_true(job_lore.has(job_id),
			"Lore should have entry for %s" % job_id)


func test_lore_job_entries_have_required_fields() -> void:
	var job_lore = _lore["jobs"]
	for job_id in job_lore:
		var entry = job_lore[job_id]
		assert_true(entry.has("origin"),
			"Lore for %s should have 'origin'" % job_id)
		assert_true(entry.has("personality_traits"),
			"Lore for %s should have 'personality_traits'" % job_id)
		assert_true(entry.has("worldview"),
			"Lore for %s should have 'worldview'" % job_id)
		assert_true(entry.has("flavor_quotes"),
			"Lore for %s should have 'flavor_quotes'" % job_id)


func test_lore_has_world_phases() -> void:
	assert_true(_lore.has("world_phases"), "Lore should have 'world_phases' section")
	assert_gte(_lore["world_phases"].size(), 6,
		"Should have at least 6 world phases")


func test_lore_has_villain_framework() -> void:
	assert_true(_lore.has("villain"), "Lore should have 'villain' section")
	assert_true(_lore["villain"].has("title"), "Villain should have title")
	assert_true(_lore["villain"].has("description"), "Villain should have description")


## ---- Renamed Job Data Integrity ----

func test_cleric_has_healing_abilities() -> void:
	var abilities = _jobs["cleric"]["abilities"]
	assert_true("cure" in abilities, "Cleric should have cure")
	assert_true("cura" in abilities, "Cleric should have cura")
	assert_true("raise" in abilities, "Cleric should have raise")


func test_mage_has_elemental_abilities() -> void:
	var abilities = _jobs["mage"]["abilities"]
	assert_true("fire" in abilities, "Mage should have fire")
	assert_true("blizzard" in abilities, "Mage should have blizzard")
	assert_true("thunder" in abilities, "Mage should have thunder")


func test_rogue_has_stealth_abilities() -> void:
	var abilities = _jobs["rogue"]["abilities"]
	assert_true("steal" in abilities, "Rogue should have steal")
	assert_true("backstab" in abilities, "Rogue should have backstab")


func test_cleric_visual_is_robed() -> void:
	assert_eq(_jobs["cleric"]["visual"]["sprite_type"], "robed",
		"Cleric should have robed sprite type")


func test_mage_visual_is_dark_robed() -> void:
	assert_eq(_jobs["mage"]["visual"]["sprite_type"], "dark_robed",
		"Mage should have dark_robed sprite type")


func test_rogue_visual_is_cloaked() -> void:
	assert_eq(_jobs["rogue"]["visual"]["sprite_type"], "cloaked",
		"Rogue should have cloaked sprite type")


## ---- Sprite Manifest ----

func test_sprite_manifest_loads() -> void:
	var manifest = _load_json("res://data/sprite_manifest.json")
	assert_not_null(manifest, "sprite_manifest.json should load")
	assert_true(manifest.has("sheets"), "Manifest should have 'sheets' key")
