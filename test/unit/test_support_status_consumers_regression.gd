extends GutTest

## Regression tests for the support-status consumer wiring (slice 47bf8a49).
##
## Pre-fix: barrier/reflect/physical_reflect/prismatic_reflect/magic_block/
## evasion/invisible/pacify were applied as statuses by _execute_support_ability
## but NO battle code ever read them — silent no-ops with full FX noise.
##
## These tests verify the consumers exist in BattleManager.gd. They're source-
## level checks (cheap, no scene wiring) because the full attack path requires
## BattleScene autoloads.

const BM_PATH := "res://src/battle/BattleManager.gd"


func _src() -> String:
	var f = FileAccess.open(BM_PATH, FileAccess.READ)
	if f == null:
		return ""
	var t = f.get_as_text()
	f.close()
	return t


func test_barrier_consumer_exists_in_attack_path() -> void:
	var src = _src()
	assert_string_contains(src, "has_status(\"barrier\")",
		"BattleManager must check has_status(barrier) — pre-fix barrier was applied but never read")


func test_reflect_consumer_exists() -> void:
	var src = _src()
	assert_string_contains(src, "has_status(\"reflect\")",
		"BattleManager must check has_status(reflect)")
	assert_string_contains(src, "physical_reflect",
		"BattleManager must check has_status(physical_reflect)")


func test_prismatic_reflect_consumer_exists() -> void:
	var src = _src()
	assert_string_contains(src, "has_status(\"prismatic_reflect\")",
		"BattleManager must check has_status(prismatic_reflect) in magic ability path")


func test_magic_block_consumer_exists() -> void:
	var src = _src()
	assert_string_contains(src, "has_status(\"magic_block\")",
		"BattleManager must check has_status(magic_block) in magic ability path")


func test_evasion_consumer_exists() -> void:
	var src = _src()
	assert_string_contains(src, "has_status(\"evasion\")",
		"BattleManager must check has_status(evasion) for dodge rolls")


func test_invisible_consumer_exists() -> void:
	var src = _src()
	assert_string_contains(src, "has_status(\"invisible\")",
		"BattleManager must check has_status(invisible) for untargetable behavior")


func test_pacify_consumer_exists() -> void:
	var src = _src()
	assert_string_contains(src, "has_status(\"pacify\")",
		"BattleManager must check has_status(pacify) to block offensive actions")


func test_dodge_helper_exists() -> void:
	var src = _src()
	assert_string_contains(src, "_target_dodges_physical",
		"BattleManager must expose _target_dodges_physical helper used by attack/physical-ability paths")


func test_dodge_helper_called_in_attack_paths() -> void:
	var src = _src()
	# Must fire in BOTH basic attack and physical_ability (otherwise the
	# physical_ability path silently ignores invisible/evasion).
	var occurrences = src.count("_target_dodges_physical(")
	assert_gte(occurrences, 3,
		"_target_dodges_physical must be called in basic attack + physical_ability paths (and defined)")
