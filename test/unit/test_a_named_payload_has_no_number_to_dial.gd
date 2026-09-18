extends GutTest

## The value dial INVENTED a number for conditions that do not have one. `has_status` and its
## four siblings, `enemy_weak_to` and the two `has_buff` types carry a NAMED payload — a status
## id, an element, a stat — and _apply_condition_type erases their op and value on purpose.
## _adjust_condition_value read `cond.get("value", 50)`, defaulted to 50, and wrote the result
## back, so one press left `value: 55` on a condition whose evaluator never reads it.
##
## MEASURED before the fix, one press each:
##     has_status     {type, status:poison}        -> {type, status:poison, value:55}
##     enemy_weak_to  {type, element:fire}         -> {type, element:fire,  value:55}
##     has_buff       {type, stat:defense}         -> {type, stat:defense,  value:55}
##     item_count     {type, item_id, op:>, value:0} -> value 5      <- CORRECT, must not change
##
## It reaches the saved script and any COWIR1: share code, and it is the shape RuleComposer
## already repairs on the way in. Found downstream of cowir-autogrind's report of the same dial
## in the autogrind twin, where the payload is a String and the arithmetic THROWS instead.

const EDITOR := "res://src/ui/autobattle/AutobattleGridEditor.gd"

var _abs


func before_each() -> void:
	_abs = get_tree().root.get_node_or_null("AutobattleSystem")
	assert_not_null(_abs, "CONTROL: AutobattleSystem autoload must exist")


func _editor() -> Node:
	var e: Node = load(EDITOR).new()
	add_child_autofree(e)
	await get_tree().process_frame
	var rules: Array = e.get("rules") as Array
	rules.clear()
	rules.append({"conditions": [{"type": "hp_percent", "op": "<", "value": 50}],
		"actions": [{"type": "attack"}], "enabled": true})
	e.set("cursor_row", 0)
	e.set("cursor_col", 0)
	return e


func _cond(e: Node) -> Dictionary:
	return ((e.get("rules") as Array)[0] as Dictionary)["conditions"][0] as Dictionary


func test_dialling_never_invents_a_number_for_any_condition_type() -> void:
	## THE ARM, and it needs NO list: for EVERY type the grammar defines, one press must not
	## ADD a `value` key that was not already there. That is the invariant — a hand-list of the
	## eight named-payload types would be a second copy of a set AutobattleSystem already owns,
	## and would drift the day a ninth lands (cowir-autogrind hit exactly that in the twin).
	var types: Array = _abs.CONDITION_TYPES.keys()
	assert_gt(types.size(), 0, "FLOOR: an empty grammar makes this arm vacuous")
	var invented: Array[String] = []
	var valueless: int = 0
	for t in types:
		var e: Node = await _editor()
		e.call("_apply_condition_type", str(t))
		var had: bool = _cond(e).has("value")
		if not had:
			valueless += 1
		e.call("_adjust_condition_value", 1)
		if not had and _cond(e).has("value"):
			invented.append("%s -> %s" % [str(t), _cond(e)])
	## CONTROL: if every type seeded a value, the check above passed over an empty population.
	assert_gt(valueless, 0,
		"no condition type seeds WITHOUT a value, so this arm examined nothing — re-derive it")
	assert_eq(invented.size(), 0,
		"one press invented a number for a condition that carries none: %s" % [invented])


func test_item_count_still_dials() -> void:
	## ANTI-OVERCORRECTION. item_count is in the SAME owner map and keeps a real op/value, so
	## blocking the whole map would make a working control dead.
	var e: Node = await _editor()
	e.call("_apply_condition_type", "item_count")
	assert_true(_cond(e).has("value"), "CONTROL: item_count must carry a number to dial")
	var before: int = int(_cond(e)["value"])
	e.call("_adjust_condition_value", 1)
	assert_ne(int(_cond(e)["value"]), before,
		"item_count must still dial — it is named-payload AND numeric")


func test_an_ordinary_numeric_condition_still_dials() -> void:
	## The other half of anti-overcorrection: nothing outside the owner map may be affected.
	var e: Node = await _editor()
	e.call("_apply_condition_type", "hp_percent")
	var before: int = int(_cond(e).get("value", -1))
	e.call("_adjust_condition_value", 1)
	assert_ne(int(_cond(e).get("value", -1)), before, "hp_percent must still dial")
