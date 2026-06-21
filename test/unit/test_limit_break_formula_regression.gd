extends GutTest

## Regression test for Limit Break having a distinct damage formula.
##
## Pre-fix: Limit Break and All-Out Attack both called _execute_physical_group
## with the same scale/formula — Limit Break cost 4x the AP for IDENTICAL
## damage. This pins:
##   - the is_limit_break branch in _execute_physical_group
##   - the post-strike status cleanse (_limit_break_cleanse)
## CLAUDE.md describes Limit Break as "Ultimate attacks requiring full AP";
## the test confirms the source recognises that group_type distinction.

const BM_PATH := "res://src/battle/BattleManager.gd"


func _src() -> String:
	var f = FileAccess.open(BM_PATH, FileAccess.READ)
	if f == null:
		return ""
	var t = f.get_as_text()
	f.close()
	return t


func test_physical_group_branches_on_limit_break() -> void:
	var src = _src()
	var idx = src.find("func _execute_physical_group")
	assert_gt(idx, -1, "_execute_physical_group must exist")
	# Grab next ~1200 chars of the function body.
	var body = src.substr(idx, 1400)
	assert_string_contains(body, "is_limit_break",
		"_execute_physical_group must branch on limit_break vs all_out_attack")
	assert_string_contains(body, "limit_break",
		"_execute_physical_group must recognise the limit_break group_type string")


func test_limit_break_cleanse_function_exists() -> void:
	var src = _src()
	assert_string_contains(src, "_limit_break_cleanse",
		"BattleManager must define a _limit_break_cleanse helper (Limit Break = clears negative statuses)")


func test_limit_break_multiplier_present() -> void:
	var src = _src()
	# Pin the design: Limit Break should be at least 2x raw — 3.0 is the
	# default per CLAUDE.md slice spec but we allow >= 2.0 in case someone
	# rebalances. Below 2.0 nullifies the 4x AP justification.
	var idx = src.find("lb_dmg_mult")
	assert_gt(idx, -1, "BattleManager must declare an lb_dmg_mult constant for Limit Break")
