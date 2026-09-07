extends GutTest

## tick 366: EncounterSystem.set_enemy_pool_for_area now explicitly
## coerces the JSON-loaded plain Array into Array[String] before
## assignment, dodging the documented silent-fail class where assigning
## a plain Array to a typed Array[String] field is a SCRIPT ERROR but
## the script halts WITHIN the assignment so the field silently stays
## at its prior value (see CLAUDE.md Common Pitfalls).
##
## Pre-fix:
##   current_enemy_pool = enemy_pools[area_id].duplicate()
##       # ↑ duplicate() returns plain Array (Variant), assignment
##       #   into Array[String] silently failed → pool unchanged
##
## This function has no production callers today but is preserved as
## a public surface (referenced by tests and tick-304 push_warning).
## If a future caller wires it up (Scriptweaver, debug console, save
## migration), they need it to actually work.

const ENCOUNTER_SYSTEM_PATH := "res://src/encounters/EncounterSystem.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


# ── Source pin: explicit coercion replaces the silent-fail assign ───

func test_source_uses_typed_string_coercion() -> void:
	var src := _read(ENCOUNTER_SYSTEM_PATH)
	var fn_idx: int = src.find("func set_enemy_pool_for_area")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	# The fix must declare a typed local and append-str.
	assert_true(body.contains("var typed: Array[String] = []"),
		"set_enemy_pool_for_area must build a typed Array[String] local")
	assert_true(body.contains("typed.append(str(entry))"),
		"set_enemy_pool_for_area must append str-coerced entries (the pattern that survives the typed-array trap)")
	# Negative pin: bare duplicate() assignment must be gone.
	assert_false(body.contains("current_enemy_pool = enemy_pools[area_id].duplicate()"),
		"bare `.duplicate()` direct assignment must be removed — that was the silent-fail surface")


# ── Behavioral: typed pool actually overwrites prior state ──────────

func test_set_enemy_pool_for_area_actually_assigns() -> void:
	var script: GDScript = load(ENCOUNTER_SYSTEM_PATH)
	var es: Object = script.new()
	add_child_autofree(es)
	# Seed a plain-Array pool the way JSON loads it (no typed-Array hint).
	es.enemy_pools = {"fire_cave": ["fire_imp", "salamander", "ember_wisp"]}
	# Reset the typed field to its default so we can detect the override.
	var seed_pool: Array[String] = ["slime", "bat"]
	es.current_enemy_pool = seed_pool

	es.set_enemy_pool_for_area("fire_cave")

	# Pre-fix the pool would still be ["slime", "bat"] because the typed
	# assignment silently failed. Post-fix it must be the fire_cave list.
	assert_eq(es.current_enemy_pool.size(), 3,
		"current_enemy_pool must now be the 3-element fire_cave pool")
	assert_true(es.current_enemy_pool.has("fire_imp"),
		"fire_imp must be in current_enemy_pool after set_enemy_pool_for_area('fire_cave')")
	assert_true(es.current_enemy_pool.has("salamander"),
		"salamander must be in current_enemy_pool")
	assert_true(es.current_enemy_pool.has("ember_wisp"),
		"ember_wisp must be in current_enemy_pool")


# ── Behavioral: non-Array value in enemy_pools warns + keeps prior ──

func test_set_enemy_pool_for_area_handles_malformed_value() -> void:
	var script: GDScript = load(ENCOUNTER_SYSTEM_PATH)
	var es: Object = script.new()
	add_child_autofree(es)
	# A corrupted enemy_pools where the value is an int (not an Array).
	es.enemy_pools = {"weird_area": 42}
	var seed_pool: Array[String] = ["slime", "bat"]
	es.current_enemy_pool = seed_pool

	es.set_enemy_pool_for_area("weird_area")

	# Prior pool must survive.
	assert_eq(es.current_enemy_pool, ["slime", "bat"] as Array[String],
		"malformed pool value must NOT corrupt current_enemy_pool")


# ── Behavioral: unknown area keeps prior (the existing tick-304 path) ─

func test_set_enemy_pool_for_area_unknown_keeps_prior() -> void:
	# Negative regression: don't accidentally regress tick 304 when
	# wiring up the typed-array coercion above.
	var script: GDScript = load(ENCOUNTER_SYSTEM_PATH)
	var es: Object = script.new()
	add_child_autofree(es)
	es.enemy_pools = {"fire_cave": ["fire_imp"]}
	var seed_pool: Array[String] = ["slime", "bat"]
	es.current_enemy_pool = seed_pool

	es.set_enemy_pool_for_area("typo_area")

	assert_eq(es.current_enemy_pool, ["slime", "bat"] as Array[String],
		"unknown area_id must keep prior pool (tick 304 contract)")
