extends GutTest

## tick 325: EncounterSystem.generate_enemy_party() public alias for
## _generate_enemy_party() so OverworldController._generate_enemies
## stops hitting "Invalid call. Nonexistent function" on every
## encounter.
##
## Pre-fix OverworldController._generate_enemies at line ~126 called
## `es.generate_enemy_party()`. EncounterSystem only had the underscore-
## prefixed `_generate_enemy_party()` (private convention). The public
## call therefore hit Godot's "Invalid call. Nonexistent function" at
## runtime and returned null. _trigger_battle then emitted
## battle_triggered with effectively empty enemies.
##
## The bug stayed INVISIBLE in normal play because the parallel
## ES.encounter_triggered → SceneTransition path supplied proper enemy
## data ahead of the controller's emit — so the actual battle had real
## enemies, while the controller's redundant signal carried garbage.
## The error message still spammed the console on every encounter
## though, and any downstream consumer of OverworldController's
## battle_triggered emit silently got empty arrays.

const ENCOUNTER_SYSTEM_PATH := "res://src/encounters/EncounterSystem.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


# ── Source pin: public alias exists ─────────────────────────────────

func test_public_alias_exists() -> void:
	var src := _read(ENCOUNTER_SYSTEM_PATH)
	assert_true(src.contains("func generate_enemy_party()"),
		"EncounterSystem must declare public generate_enemy_party() — OverworldController calls it directly")
	# Private impl must still exist (alias forwards to it).
	assert_true(src.contains("func _generate_enemy_party()"),
		"_generate_enemy_party() implementation must remain — the public alias delegates to it")


# ── Source pin: alias is one-line delegate ──────────────────────────

func test_alias_delegates_to_private() -> void:
	var src := _read(ENCOUNTER_SYSTEM_PATH)
	var fn_idx: int = src.find("func generate_enemy_party()")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("return _generate_enemy_party()"),
		"alias must delegate to the private impl, not duplicate the logic")


# ── Behavioral: public call works on the real autoload ──────────────

func test_real_autoload_responds_to_public_call() -> void:
	assert_not_null(EncounterSystem, "EncounterSystem autoload required")
	if EncounterSystem == null:
		return
	assert_true(EncounterSystem.has_method("generate_enemy_party"),
		"EncounterSystem.has_method('generate_enemy_party') must return true post-fix — pre-fix it was false and the call threw Invalid call")
	# Call it — should return an Array (possibly empty if pool is empty
	# at autoload-init time but the call itself must not error).
	var result: Variant = EncounterSystem.generate_enemy_party()
	assert_true(result is Array,
		"public alias must return an Array (delegating to _generate_enemy_party)")


# ── Behavioral: alias returns the same type as private impl ─────────

func test_alias_matches_private_return_type() -> void:
	# Both must return Array. Verify equivalence by calling both on the
	# same autoload and checking type.
	assert_not_null(EncounterSystem, "EncounterSystem autoload required")
	if EncounterSystem == null:
		return
	var pub: Variant = EncounterSystem.generate_enemy_party()
	var priv: Variant = EncounterSystem._generate_enemy_party()
	assert_true(pub is Array and priv is Array,
		"both public and private must return Array")
