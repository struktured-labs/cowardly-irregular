extends GutTest

## tick 326: OverworldController.set_area_config / set_enemy_pool now
## push the new pool into EncounterSystem.current_enemy_pool so
## es.generate_enemy_party() spawns the controller's intended monsters.
##
## Pre-fix set_area_config(_, _, _, enemy_pool) stored the value in
## OverworldController._enemy_pool but NEVER told EncounterSystem.
## ES.current_enemy_pool stayed at its default (["slime", "bat"]) or
## whatever the LAST ES.set_enemy_pool call pushed.
##
## Effect:
##   - DragonCave._update_floor_encounters calls
##     controller.set_area_config(area_id, false, rate, pool) with
##     floor-specific pools (e.g., fire dungeon: ["fire_imp",
##     "salamander", "lava_slug"]). Pre-fix the actual encounters spawned
##     slimes and bats because ES.current_enemy_pool stayed default.
##   - Same for set_enemy_pool(pool_id) — the controller cached the
##     pool but ES never saw it.
##
## Fix adds _push_pool_to_encounter_system helper that resolves the
## ES autoload, coerces Array → Array[String] (dodges the typed-array
## silent-assignment trap), and calls ES.set_enemy_pool. Same stored-
## locally-never-pushed class as tick 324 (encounter_rate).

const CONTROLLER_PATH := "res://src/exploration/OverworldController.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


# ── Source pin: helper exists ───────────────────────────────────────

func test_push_helper_exists() -> void:
	var src := _read(CONTROLLER_PATH)
	assert_true(src.contains("func _push_pool_to_encounter_system(pool: Array)"),
		"_push_pool_to_encounter_system helper must exist — the canonical sync point")


# ── Source pin: typed coercion preserves Array[String] ─────────────

func test_helper_does_typed_coercion() -> void:
	var src := _read(CONTROLLER_PATH)
	var fn_idx: int = src.find("func _push_pool_to_encounter_system")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("var typed: Array[String] = []"),
		"helper must coerce to Array[String] explicitly (typed-array assignment silently no-ops if source is plain Array)")
	assert_true(body.contains("for entry in pool:"),
		"helper must loop to coerce — typed Array[X] = untyped Array fails silently")
	assert_true(body.contains("es.set_enemy_pool(typed)"),
		"helper must call ES.set_enemy_pool with the typed array")


# ── Source pin: both setters call the helper ────────────────────────

func test_set_area_config_pushes() -> void:
	var src := _read(CONTROLLER_PATH)
	var fn_idx: int = src.find("func set_area_config")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("_push_pool_to_encounter_system"),
		"set_area_config must push the new pool into EncounterSystem")


func test_set_enemy_pool_pushes() -> void:
	var src := _read(CONTROLLER_PATH)
	var fn_idx: int = src.find("func set_enemy_pool(pool_id")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("_push_pool_to_encounter_system"),
		"set_enemy_pool(pool_id) must also push — same sync gap as set_area_config")


# ── Behavioral: set_area_config mutates ES.current_enemy_pool ──────

func test_set_area_config_mutates_es_pool() -> void:
	assert_not_null(EncounterSystem, "EncounterSystem autoload required")
	if EncounterSystem == null:
		return

	var ctrl_script: GDScript = load(CONTROLLER_PATH)
	var ctrl: Object = ctrl_script.new()
	add_child_autofree(ctrl)

	var prior_pool: Array = EncounterSystem.current_enemy_pool.duplicate()

	# Push a distinctive pool — verify ES receives it.
	ctrl.set_area_config("test_area_326", false, 0.1, ["fire_imp", "salamander"])
	assert_eq(EncounterSystem.current_enemy_pool.size(), 2,
		"ES.current_enemy_pool must reflect the controller's pool (pre-fix: stayed at default)")
	assert_eq(EncounterSystem.current_enemy_pool[0], "fire_imp",
		"first entry must be 'fire_imp'")
	assert_eq(EncounterSystem.current_enemy_pool[1], "salamander",
		"second entry must be 'salamander'")

	# Restore.
	EncounterSystem.current_enemy_pool = prior_pool
