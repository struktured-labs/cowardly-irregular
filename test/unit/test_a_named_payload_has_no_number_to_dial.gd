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
	assert_eq(str(_cond(e).get("type", "")), "item_count",
		"CONTROL: the type change must take — hp_percent also carries a value and would pass below")
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


# ── the mirror: switching AWAY left the old type's payload behind ──────────────

func test_switching_type_leaves_no_payload_from_the_old_one() -> void:
	## Every named payload survived a type change: has_status -> hp_percent left `status: poison`
	## on an hp_percent condition, and the same for element / stat / item_id / weather. It reaches
	## the saved script and every share code. Derived over the owner's map — every ordered pair
	## whose FIELD differs — so a tenth named-payload type is covered the day it lands.
	var fields: Dictionary = _abs.CONDITION_REQUIRED_FIELD
	assert_gt(fields.size(), 0, "FLOOR: an empty map makes every pair below vacuous")
	var stale: Array[String] = []
	var pairs: int = 0
	for was in fields.keys():
		for now in _abs.CONDITION_TYPES.keys():
			if str(fields.get(was, "")) == str(fields.get(now, "")):
				continue
			pairs += 1
			var e: Node = await _editor()
			e.call("_apply_condition_type", str(was))
			## CONTROL, inside the loop: a no-op _apply_condition_type would leave an hp_percent
			## condition that never had the old field, and the check below would pass over nothing.
			assert_eq(str(_cond(e).get("type", "")), str(was), "the first type change must take")
			e.call("_apply_condition_type", str(now))
			assert_eq(str(_cond(e).get("type", "")), str(now), "the second type change must take")
			if _cond(e).has(str(fields[was])):
				stale.append("%s -> %s kept %s" % [str(was), str(now), str(fields[was])])
	assert_gt(pairs, 0, "CONTROL: no differing-field pair was driven, so this arm examined nothing")
	assert_eq(stale.size(), 0, "the old type's payload survived the switch: %s" % [stale])


func test_switching_within_a_family_keeps_the_choice() -> void:
	## ANTI-OVERCORRECTION. The five status types share the "status" field and the two buff types
	## share "stat", so moving between them must PRESERVE what the player already picked —
	## erasing on every type change would throw it away.
	for pair in [["has_status", "ally_has_status"], ["has_buff", "not_has_buff"]]:
		var e: Node = await _editor()
		e.call("_apply_condition_type", pair[0])
		assert_eq(str(_cond(e).get("type", "")), str(pair[0]),
			"CONTROL: the type change must take, or the plant below lands on hp_percent")
		var field: String = str(_abs.CONDITION_REQUIRED_FIELD[pair[0]])
		## Plant a NON-SEED value. Comparing against the seed cannot discriminate: erase-then-
		## reseed yields the seed again, so an over-correction that erases on EVERY type change
		## passes. Measured — that mutation was green until this line. A composer-authored
		## "sleep" is the real case, since the editor itself can only ever seed "poison".
		var planted: String = "sleep" if field == "status" else "speed"
		_cond(e)[field] = planted
		var chosen: String = str(_cond(e).get(field, ""))
		assert_eq(chosen, planted, "CONTROL: the plant must take, or this arm proves nothing")
		e.call("_apply_condition_type", pair[1])
		assert_eq(str(_cond(e).get(field, "")), chosen,
			"%s -> %s must keep %s — they are the same field" % [pair[0], pair[1], field])
