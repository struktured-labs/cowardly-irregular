extends GutTest

## `GROUP_AP_COST` says of itself: "The COMMAND MENU reads this and group_participants() too, so a
## row is never offered that this function will refuse." `group_ap_shortfall` does read it. The
## SPENDER did not — `_execute_group_action` computed `4 if limit_break else (2 if combo_magic else
## 1)`, a second copy of the same three numbers, so the menu gated on the table and the engine
## charged a literal.
##
## Identical to the formation defect one arm over, and the formation fix DESTROYED THE EVIDENCE:
## `_execute_formation_special` now reads a table, so nothing pointed at its sibling. Found by
## asking cowir-ai's question — was the first instance the only one.
##
## They agree today (1/2/4), so this is latent: the trigger is a rebalance of GROUP_AP_COST, which
## would move the gate and not the debit.
##
## ⛔ SOURCE-LEVEL, AND THAT IS A LIMITATION RATHER THAN A CHOICE. The formation guard measures the
## real DEBIT because `_execute_formation_special` is callable in isolation. `_execute_group_action`
## is not: it emits `action_executed`, runs `_check_victory_conditions` and arms a timer, which is
## why ZERO of the eight test files mentioning it call it — the one that inspects it reads its source
## (`test_execute_next_action_delay_double_scale_regression`). This follows that precedent. It
## certifies that the cost is DERIVED, not what any party actually paid.
##
## ⚠️ `:2037`'s `current_ap < 4` is deliberately NOT in scope. Its message is "requires ALL
## participants at full AP (4)" — that is FULLNESS, a different concept that coincides with
## limit_break's cost at 4. Rewriting it to read the table would conflate the two.

const SRC := "res://src/battle/BattleManager.gd"
const FUNC := "func _execute_group_action"
const TABLE := "GROUP_AP_COST"


func _body() -> PackedStringArray:
	var lines: PackedStringArray = FileAccess.get_file_as_string(SRC).split("\n")
	var out := PackedStringArray()
	var inside := false
	for ln in lines:
		if ln.begins_with(FUNC):
			inside = true
			continue
		if inside and ln.begins_with("func "):
			break
		if inside:
			out.append(ln)
	return out


func _ap_cost_assignments() -> PackedStringArray:
	var out := PackedStringArray()
	for ln in _body():
		var t := ln.strip_edges()
		if t.begins_with("var ap_cost") or t.begins_with("ap_cost ="):
			out.append(t)
	return out


func test_the_parse_found_the_function_and_its_cost_assignment() -> void:
	assert_gt(_body().size(), 10,
		"FLOOR: %s's body must parse, or every claim below is about an empty list" % FUNC)
	assert_gt(_ap_cost_assignments().size(), 0,
		"FLOOR: no `ap_cost` assignment found in %s — the subject was renamed or removed, which "
		% FUNC + "must red here rather than pass quietly")


func test_the_spender_derives_its_price_from_the_table() -> void:
	var bad: Array[String] = []
	for a in _ap_cost_assignments():
		if a.contains(TABLE):
			continue
		## A literal price is the defect: the menu gates on the table, so a second copy drifts.
		for d in ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"]:
			if a.contains(d):
				bad.append(a)
				break
	assert_eq(bad, [],
		"%s must take its per-participant AP from %s — the table the command menu gates these rows "
		% [FUNC, TABLE] + "on. A literal here is a second copy of the same numbers: %s" % str(bad))
