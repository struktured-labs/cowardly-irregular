extends GutTest

## tick 327: PassiveSystem._create_default_passives now includes
## mp_boost (the +30% max_mp_multiplier pair to hp_boost).
##
## Pre-fix mp_boost was the natural pair to hp_boost (same +30%
## pattern, same category) but was MISSING from the defaults
## fallback. Mage-class passive selection in passives.json references
## it. If both jobs.json AND passives.json failed to load, equip_passive
## ("mp_boost") fired its "passive_id not found in passives table"
## warning and the equip silently failed.
##
## Same omission class as tick 319 (encore) and tick 318 (max_mp from
## stat_modifiers). Defaults are intentionally a minimal subset, but
## they must be SYMMETRICAL — hp_boost without mp_boost left MP-heavy
## classes without a defensive option in the fallback path.

const PASSIVE_SYSTEM_PATH := "res://src/jobs/PassiveSystem.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


# ── Source pin: mp_boost exists alongside hp_boost ──────────────────

func test_mp_boost_in_defaults() -> void:
	var src := _read(PASSIVE_SYSTEM_PATH)
	var fn_idx: int = src.find("func _create_default_passives")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("\"mp_boost\":"),
		"mp_boost must exist in PassiveSystem defaults (pair to hp_boost)")
	assert_true(body.contains("\"max_mp_multiplier\": 1.3"),
		"mp_boost must use max_mp_multiplier=1.3 (mirrors data/passives.json)")


# ── Source pin: defensive pair symmetry ─────────────────────────────

func test_defensive_pair_symmetry() -> void:
	# hp_boost and mp_boost should both appear in the defensive section
	# with matching +30% pattern.
	var src := _read(PASSIVE_SYSTEM_PATH)
	var fn_idx: int = src.find("func _create_default_passives")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	# hp_boost should come BEFORE mp_boost (insertion order matters for
	# readability + pairing).
	var hp_idx: int = body.find("\"hp_boost\":")
	var mp_idx: int = body.find("\"mp_boost\":")
	assert_gt(hp_idx, -1, "hp_boost must exist")
	assert_gt(mp_idx, -1, "mp_boost must exist")
	assert_lt(hp_idx, mp_idx,
		"mp_boost should come right after hp_boost (paired)")


# ── Behavioral: PassiveSystem.get_passive resolves it ───────────────

func test_get_passive_mp_boost_returns_data() -> void:
	# Real autoload — passives.json is available, so this just exercises
	# the canonical path. The defaults gap is fallback-only.
	assert_not_null(PassiveSystem, "PassiveSystem autoload required")
	if PassiveSystem == null:
		return
	var mp_boost: Dictionary = PassiveSystem.get_passive("mp_boost") if PassiveSystem.has_method("get_passive") else {}
	assert_false(mp_boost.is_empty(),
		"PassiveSystem.get_passive('mp_boost') must return data — confirms either the JSON OR the defaults cover it")
	assert_eq(float(mp_boost.get("stat_mods", {}).get("max_mp_multiplier", 0.0)), 1.3,
		"mp_boost.stat_mods.max_mp_multiplier must be 1.3")
