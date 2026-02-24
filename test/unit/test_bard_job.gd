extends GutTest

## Tests for the Bard job
## Covers: abilities, passive, stats, song effect types

const CombatantScript = preload("res://src/battle/Combatant.gd")

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
	_jobs = _load_json("res://data/jobs.json")
	if _jobs == null:
		_jobs = {}
	_abilities = _load_json("res://data/abilities.json")
	if _abilities == null:
		_abilities = {}
	_passives = _load_json("res://data/passives.json")
	if _passives == null:
		_passives = {}


## ---- Bard Job Exists ----

func test_bard_exists_in_jobs() -> void:
	assert_true(_jobs.has("bard"), "jobs.json should have bard")


func test_bard_is_starter_type() -> void:
	assert_eq(int(_jobs["bard"]["type"]), 0, "Bard should be type 0 (starter)")


func test_bard_has_correct_id() -> void:
	assert_eq(_jobs["bard"]["id"], "bard", "Bard ID should be 'bard'")


func test_bard_has_correct_name() -> void:
	assert_eq(_jobs["bard"]["name"], "Bard", "Bard name should be 'Bard'")


## ---- Bard Stats ----

func test_bard_stat_modifiers() -> void:
	var mods = _jobs["bard"]["stat_modifiers"]
	assert_eq(int(mods["max_hp"]), 85, "Bard HP should be 85")
	assert_eq(int(mods["max_mp"]), 65, "Bard MP should be 65")
	assert_eq(int(mods["attack"]), 9, "Bard ATK should be 9")
	assert_eq(int(mods["defense"]), 8, "Bard DEF should be 8")
	assert_eq(int(mods["magic"]), 14, "Bard MAG should be 14")
	assert_eq(int(mods["speed"]), 14, "Bard SPD should be 14")


func test_bard_stats_apply_to_combatant() -> void:
	var c = CombatantScript.new()
	add_child_autofree(c)

	var job = _jobs["bard"]
	c.job = job
	var mods = job["stat_modifiers"]
	c.max_hp = int(mods["max_hp"])
	c.max_mp = int(mods["max_mp"])
	c.attack = int(mods["attack"])
	c.defense = int(mods["defense"])
	c.magic = int(mods["magic"])
	c.speed = int(mods["speed"])

	assert_eq(c.max_hp, 85, "Applied Bard HP should be 85")
	assert_eq(c.magic, 14, "Applied Bard MAG should be 14")
	assert_eq(c.speed, 14, "Applied Bard SPD should be 14")


## ---- Bard Abilities ----

func test_bard_has_4_abilities() -> void:
	var abilities = _jobs["bard"]["abilities"]
	assert_eq(abilities.size(), 4, "Bard should have exactly 4 abilities")


func test_bard_abilities_exist_in_data() -> void:
	var expected = ["battle_hymn", "lullaby", "discord", "inspiring_melody"]
	for ability_id in expected:
		assert_true(_abilities.has(ability_id),
			"Bard ability '%s' should exist in abilities.json" % ability_id)


func test_battle_hymn_is_song_type() -> void:
	var ability = _abilities["battle_hymn"]
	assert_eq(ability["type"], "song", "Battle Hymn should be type 'song'")
	assert_eq(ability["target_type"], "all_allies", "Battle Hymn should target all allies")
	assert_eq(int(ability["mp_cost"]), 8, "Battle Hymn should cost 8 MP")
	assert_eq(ability["effect"], "attack_up", "Battle Hymn should boost attack")
	assert_eq(int(ability["duration"]), 3, "Battle Hymn should last 3 turns")


func test_lullaby_is_song_type() -> void:
	var ability = _abilities["lullaby"]
	assert_eq(ability["type"], "song", "Lullaby should be type 'song'")
	assert_eq(ability["target_type"], "single_enemy", "Lullaby should target single enemy")
	assert_eq(int(ability["mp_cost"]), 12, "Lullaby should cost 12 MP")
	assert_eq(ability["effect"], "sleep", "Lullaby should inflict sleep")


func test_discord_is_song_type() -> void:
	var ability = _abilities["discord"]
	assert_eq(ability["type"], "song", "Discord should be type 'song'")
	assert_eq(ability["target_type"], "all_enemies", "Discord should target all enemies")
	assert_eq(int(ability["mp_cost"]), 10, "Discord should cost 10 MP")
	assert_eq(ability["effect"], "defense_down", "Discord should lower defense")


func test_inspiring_melody_is_song_type() -> void:
	var ability = _abilities["inspiring_melody"]
	assert_eq(ability["type"], "song", "Inspiring Melody should be type 'song'")
	assert_eq(ability["target_type"], "all_allies", "Inspiring Melody should target all allies")
	assert_eq(int(ability["mp_cost"]), 15, "Inspiring Melody should cost 15 MP")


## ---- Bard Passive ----

func test_bard_has_1_passive() -> void:
	var passives = _jobs["bard"]["passive_abilities"]
	assert_eq(passives.size(), 1, "Bard should have exactly 1 passive")
	assert_eq(passives[0], "encore", "Bard passive should be 'encore'")


func test_encore_passive_exists() -> void:
	assert_true(_passives.has("encore"), "passives.json should have 'encore'")


func test_encore_passive_has_song_duration_bonus() -> void:
	var encore = _passives["encore"]
	assert_eq(int(encore["category"]), 2, "Encore should be category 2")
	assert_true(encore.has("meta_effects"), "Encore should have meta_effects")
	assert_eq(int(encore["meta_effects"]["song_duration_bonus"]), 1,
		"Encore should grant +1 song duration")


## ---- Bard Visual ----

func test_bard_visual_config() -> void:
	var visual = _jobs["bard"]["visual"]
	assert_eq(visual["sprite_type"], "performer", "Bard sprite type should be 'performer'")
	assert_eq(visual["headgear"], "feathered_cap", "Bard headgear should be 'feathered_cap'")


## ---- Bard Evolution ----

func test_bard_has_evolution_data() -> void:
	assert_true(_jobs["bard"].has("evolution"), "Bard should have evolution field")
	var evo = _jobs["bard"]["evolution"]
	assert_true(evo.has("future_targets"), "Bard evolution should have future_targets")
	assert_true("troubadour" in evo["future_targets"], "Troubadour should be a future target")
	assert_true("cantor" in evo["future_targets"], "Cantor should be a future target")
