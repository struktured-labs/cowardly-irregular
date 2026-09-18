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

## Named-payload types whose seed erases op/value. item_count is deliberately absent: it is in
## the same owner map and keeps a real number.
const NAMED_NO_NUMBER := ["has_status", "not_has_status", "ally_has_status",
	"enemy_has_status", "not_enemy_has_status", "enemy_weak_to", "has_buff", "not_has_buff"]

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


func test_the_named_payload_set_is_derived_and_not_empty() -> void:
	## FLOOR. Every type below must be one the OWNER calls named-payload, or the arms are
	## asserting about a set this file invented.
	assert_gt(NAMED_NO_NUMBER.size(), 0, "an empty list makes every arm below vacuous")
	for t in NAMED_NO_NUMBER:
		assert_true(_abs.CONDITION_REQUIRED_FIELD.has(t),
			"%s must be in CONDITION_REQUIRED_FIELD, or this file is pinning its own opinion" % t)


func test_dialling_a_named_payload_condition_invents_no_number() -> void:
	## THE ARM.
	for t in NAMED_NO_NUMBER:
		var e: Node = await _editor()
		e.call("_apply_condition_type", t)
		assert_false(_cond(e).has("value"),
			"CONTROL: %s must start with no value, or the arm below proves nothing" % t)
		for _i in range(5):
			e.call("_adjust_condition_value", 1)
			e.call("_adjust_condition_value", -1)
		assert_false(_cond(e).has("value"),
			"%s gained a number the dial invented: %s" % [t, _cond(e)])


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
