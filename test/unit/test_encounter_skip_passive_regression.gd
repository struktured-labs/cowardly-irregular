extends GutTest

## tick 440: encounter_skip passive's meta_effects.
## encounter_skip_chance now actually rolls to skip encounters.
##
## Pre-fix passives.json authored:
##   encounter_skip: {meta_effects: {encounter_skip_chance: 0.25}}
##   description: "25% chance to skip random encounters entirely"
## but no code path read the field — players equipped it expecting
## fewer encounters and got the full encounter rate.

const ENCOUNTER_SYSTEM_PATH := "res://src/encounters/EncounterSystem.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


func test_helper_exists() -> void:
	var src := _read(ENCOUNTER_SYSTEM_PATH)
	assert_true(src.contains("func _party_encounter_skip_chance"),
		"EncounterSystem must declare _party_encounter_skip_chance helper")
	# Pin the meta_effects read.
	assert_true(src.contains("me.get(\"encounter_skip_chance\", 0.0)"),
		"helper must read encounter_skip_chance from passive meta_effects")


func test_check_for_encounter_consults_helper() -> void:
	var src := _read(ENCOUNTER_SYSTEM_PATH)
	var fn_idx: int = src.find("func check_for_encounter")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("_party_encounter_skip_chance()"),
		"check_for_encounter must consult _party_encounter_skip_chance after the rate roll succeeds")


func test_helper_uses_max_wins_semantics() -> void:
	# Pin the > max_chance pattern so stacked passives don't add up
	# to near-100% silence.
	var src := _read(ENCOUNTER_SYSTEM_PATH)
	var fn_idx: int = src.find("func _party_encounter_skip_chance")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("if c > max_chance:") and body.contains("max_chance = c"),
		"helper must use max-wins semantics across party passives")


func test_skip_check_after_roll_success() -> void:
	# Pin ordering: skip check happens AFTER the rate roll succeeds.
	# Don't roll the skip if the encounter wouldn't have triggered
	# anyway — wastes the chance.
	var src := _read(ENCOUNTER_SYSTEM_PATH)
	var fn_idx: int = src.find("func check_for_encounter")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	# The skip block must sit inside the `if roll < chance:` branch.
	var rate_idx: int = body.find("if roll < chance:")
	var skip_idx: int = body.find("_party_encounter_skip_chance")
	# Find the _trigger_encounter that gates on the skip check (not
	# the earlier forced-encounter one).
	var trigger_idx: int = body.find("_trigger_encounter()", skip_idx)
	assert_gt(rate_idx, -1)
	assert_gt(skip_idx, -1)
	assert_gt(trigger_idx, -1)
	assert_lt(rate_idx, skip_idx,
		"skip check must come AFTER the rate roll passed")
	assert_lt(skip_idx, trigger_idx,
		"skip check must come BEFORE _trigger_encounter so a successful skip prevents it")


func test_data_still_authors_passive() -> void:
	var raw: String = FileAccess.get_file_as_string("res://data/passives.json")
	var parsed: Variant = JSON.parse_string(raw)
	var data: Dictionary = parsed
	assert_true(data.has("encounter_skip"))
	var me: Variant = data["encounter_skip"].get("meta_effects", {})
	assert_true(me is Dictionary)
	assert_gt(float(me.get("encounter_skip_chance", 0.0)), 0.0,
		"encounter_skip passive must still author encounter_skip_chance > 0")


func test_helper_returns_zero_for_no_party() -> void:
	# Sanity: empty party / no GameState returns 0.0.
	var es = Engine.get_main_loop().root.get_node_or_null("EncounterSystem")
	if es == null:
		pending("EncounterSystem autoload required")
		return
	if not GameState:
		pending("GameState autoload required")
		return
	var prior_party: Array = GameState.player_party.duplicate(true)
	GameState.player_party = []
	assert_eq(es._party_encounter_skip_chance(), 0.0,
		"empty player_party must return 0.0 skip chance")
	GameState.player_party = prior_party
