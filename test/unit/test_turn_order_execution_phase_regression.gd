extends GutTest

## Feature 2026-07-04: the CTB turn-order strip read only selection_order,
## which is fully consumed by the time the EXECUTION phase starts — so
## the strip went blank exactly when the player wants to see "who acts
## next." It now falls back to execution_order (speed-sorted pending
## actions, front = next to act) during execution/processing, keeping
## the upcoming order visible while actions resolve.

const UIM := "res://src/battle/BattleUIManager.gd"


## 2026-08-14: the queue build was extracted into _compute_ctb_queue() for the UI-motion
## work. Same behavior, one function over — so the pin spans BOTH and stays location-proof.
func _strip_body() -> String:
	var src: String = FileAccess.get_file_as_string(UIM)
	var fn: int = src.find("func _update_turn_order_strip")
	assert_gt(fn, -1, "_update_turn_order_strip must exist")
	var body: String = src.substr(fn, src.find("\nfunc ", fn + 1) - fn)
	var q: int = src.find("func _compute_ctb_queue")
	assert_gt(q, -1, "the extracted queue builder must exist")
	return body + src.substr(q, src.find("\nfunc ", q + 1) - q)


func test_execution_phase_reads_execution_order() -> void:
	var body := _strip_body()
	assert_true(body.contains("BattleManager.execution_order"),
		"the strip must read execution_order during execution — selection_order is empty by then")
	assert_true(body.contains("BattleState.EXECUTION_PHASE") and body.contains("BattleState.PROCESSING_ACTION"),
		"execution-order display must be gated to the execution/processing phases")


func test_execution_entries_extract_the_combatant() -> void:
	var body := _strip_body()
	# execution_order holds action Dicts, not bare combatants — must pull .combatant
	assert_true(body.contains("action.get(\"combatant\")"),
		"execution_order entries are action dicts — the strip must extract the combatant")


func test_head_of_queue_marked_current() -> void:
	var body := _strip_body()
	assert_true(body.contains("shown == 0"),
		"the head of the queue (current selector / next to act) must render as the highlighted entry")


func test_execution_order_field_exists_and_is_sorted_by_speed() -> void:
	# Cross-check the source the strip now depends on.
	var bm: String = FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	assert_true(bm.contains("var execution_order"),
		"BattleManager must expose execution_order for the strip to read")
	assert_true(bm.contains("execution_order.sort_custom"),
		"execution_order must be speed-sorted — the strip presents it as turn order")
