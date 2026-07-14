extends GutTest

## tick 360: _get_terrain_for_map maps castle_harmonia to "village"
## (medieval indoor) instead of falling through to "plains".
##
## Pre-fix Castle Harmonia (the W1 final boss arena, indoor stone
## setting where Chancellor Mordaine fights) had NO explicit arm
## and the `_:` default's substring keyword search (cave / dungeon
## / village / town / forest) didn't match "castle_harmonia". So
## it returned "plains" — players fought Mordaine in front of a
## plains battle background instead of a medieval indoor scene.
##
## Symptom: "the W1 final boss fight looks weird — it's set in a
## grassy field?"
##
## Fix maps the explicit map_id + adds a "castle" keyword guard so
## any future castle_<world> arenas default to village-style
## medieval terrain too.

const GAME_LOOP_PATH := "res://src/GameLoop.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


# ── Source pin: castle_harmonia arm exists ──────────────────────────

func test_castle_harmonia_arm_exists() -> void:
	var src := _read(GAME_LOOP_PATH)
	var fn_idx: int = src.find("func _get_terrain_for_map")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("\"castle_harmonia\":"),
		"_get_terrain_for_map must have an explicit castle_harmonia arm")


# ── Source pin: castle keyword in fallback heuristic ────────────────

func test_castle_keyword_in_fallback() -> void:
	var src := _read(GAME_LOOP_PATH)
	var fn_idx: int = src.find("func _get_terrain_for_map")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	# The fallback substring check should include "castle".
	assert_true(body.contains("\"castle\" in map_id"),
		"`_:` arm must include a 'castle' keyword guard for future castle_<world> arenas")


# ── Behavioral: castle_harmonia returns village ─────────────────────

func test_castle_harmonia_returns_village() -> void:
	var gl_script: GDScript = load(GAME_LOOP_PATH)
	var gl: Object = gl_script.new()
	add_child_autofree(gl)
	assert_eq(gl._get_terrain_for_map("castle_harmonia"), "village",
		"castle_harmonia must map to 'village' — pre-fix it returned 'plains' via the substring-keyword default")


# ── Behavioral: future castle_<world> maps via fallback ─────────────

func test_future_castle_maps_via_fallback() -> void:
	var gl_script: GDScript = load(GAME_LOOP_PATH)
	var gl: Object = gl_script.new()
	add_child_autofree(gl)
	# Hypothetical W3 castle arena.
	assert_eq(gl._get_terrain_for_map("castle_steampunk_hypo"), "village",
		"`_:` arm with 'castle' keyword must catch future castle_<world> ids")


# ── Behavioral: non-castle non-keyword map_ids still get plains ─────

func test_plain_fallback_preserved() -> void:
	var gl_script: GDScript = load(GAME_LOOP_PATH)
	var gl: Object = gl_script.new()
	add_child_autofree(gl)
	# Random unknown id with no matching substring.
	assert_eq(gl._get_terrain_for_map("__totally_unknown_thing__"), "plains",
		"`_:` arm must still return 'plains' for non-matching ids — fix must not invert the default")
