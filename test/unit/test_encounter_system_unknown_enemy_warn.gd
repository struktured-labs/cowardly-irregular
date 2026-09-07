extends GutTest

## tick 306: EncounterSystem._create_enemy_data now push_warnings on
## unknown enemy_id instead of silently falling back to slime.
##
## Pre-fix the legacy hardcoded-fallback match's `_:` arm just
## returned a slime-shaped dict with no diagnostic. A typo'd id in
## enemy_pools.json (or save-format drift with a renamed monster)
## silently spawned slimes everywhere in the affected area. The
## visible symptom was "wrong monsters in this area," but the
## actual miss (unknown enemy_id) was totally invisible.
##
## Same silent-fail class as tick 304's set_enemy_pool_for_area fix
## and tick 303's modify_constant fix.

const ENCOUNTER_SYSTEM := "res://src/encounters/EncounterSystem.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


# ── Source pin: push_warning on unknown enemy_id ─────────────────

func test_unknown_enemy_pushes_warning() -> void:
	var src := _read(ENCOUNTER_SYSTEM)
	assert_true(src.contains("push_warning(\"[EncounterSystem] _create_enemy_data: unknown enemy_id"),
		"unknown enemy_id path must push_warning naming the id")


# ── Fallback to slime preserved ──────────────────────────────────

func test_slime_fallback_preserved() -> void:
	# The push_warning is informative but the fallback must still
	# spawn SOMETHING — silent crash on unknown enemy would be worse
	# than a typo'd encounter.
	var src := _read(ENCOUNTER_SYSTEM)
	var fn_idx: int = src.find("func _create_enemy_data")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	# The `_:` default branch contains both the warn AND the slime
	# fallback.
	var default_idx: int = body.find("_:")
	assert_gt(default_idx, -1, "default match arm must exist")
	var default_body: String = body.substr(default_idx, 800)
	assert_true(default_body.contains("push_warning"),
		"default arm must push_warning")
	assert_true(default_body.contains("_create_enemy_data(\"slime\")") or default_body.contains("\"name\": \"Slime\""),
		"default arm must still fall back to slime — keeping the spawn alive")


# ── Behavioral: unknown id triggers the warning + returns slime ──

func test_behavior_unknown_id_returns_slime_shape() -> void:
	var script: GDScript = load(ENCOUNTER_SYSTEM)
	var inst: Object = script.new()
	add_child_autofree(inst)
	# Force a non-matching enemy_id that won't hit any database or
	# match arm.
	var data: Dictionary = inst._create_enemy_data("__definitely_not_a_real_enemy_id_xyz")
	# Fallback returns slime-shape.
	assert_eq(data.get("id", ""), "slime",
		"unknown enemy_id must fall back to a slime-shaped dict")
	# Has the expected slime stat fields.
	assert_true(data.has("max_hp") and data.has("attack"),
		"slime-fallback must carry stat fields (combat won't crash on missing keys)")


# ── Known id still works (regression check) ──────────────────────

func test_known_id_does_not_warn() -> void:
	# Source pin: the database-hit branch (above the match) returns
	# directly without entering the _: arm.
	var src := _read(ENCOUNTER_SYSTEM)
	var fn_idx: int = src.find("func _create_enemy_data")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	# The database-hit branch starts with `if monster_database.has`
	# and ends with `return data`. Confirm it exits BEFORE the match.
	var db_check: int = body.find("if monster_database.has(enemy_id):")
	var match_idx: int = body.find("match enemy_id:")
	assert_gt(db_check, -1, "database-hit branch must exist")
	assert_gt(match_idx, -1, "fallback match must exist")
	assert_lt(db_check, match_idx,
		"database-hit branch must come BEFORE the fallback match — known ids never reach the warn")
