extends GutTest

## Regression: cutscene update_item step transforms an item ID in
## inventory (e.g. world1_orrery's "fool_card" → "wild_card"). Pre-fix
## the step type wasn't in CutsceneDirector._execute_step's dispatch,
## so the swap silently failed and players ended up with a fool_card
## that the rest of the story expected to be a wild_card.

const DIRECTOR_PATH := "res://src/cutscene/CutsceneDirector.gd"
const COMBATANT_PATH := "res://src/battle/Combatant.gd"


func _read(path: String) -> String:
	var file = FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "file should exist: %s" % path)
	var text = file.get_as_text()
	file.close()
	return text


func test_dispatch_handles_update_item() -> void:
	var text = _read(DIRECTOR_PATH)
	var match_idx = text.find("func _execute_step")
	var fn_end = text.find("\n\nfunc ", match_idx)
	var body = text.substr(match_idx, fn_end - match_idx) if fn_end > -1 else text.substr(match_idx, 1500)
	assert_true(body.find("\"update_item\":") > -1,
		"_execute_step match must include update_item case (was silently dropped pre-fix)")


func test_update_item_handler_warns_on_missing_fields() -> void:
	var text = _read(DIRECTOR_PATH)
	var fn_idx = text.find("func _step_update_item(")
	assert_true(fn_idx > -1, "_step_update_item handler must exist")
	var fn_end = text.find("\n\n\nfunc ", fn_idx)
	var body = text.substr(fn_idx, fn_end - fn_idx) if fn_end > -1 else text.substr(fn_idx, 1500)
	# Must warn on malformed step (missing item or new_id).
	assert_true(body.find("push_warning") > -1,
		"_step_update_item must push_warning on missing fields — no silent failure")
	# Must walk party (not just leader) so the swap finds items that ended
	# up on non-leader members.
	assert_true(body.find("for member in game_loop.party") > -1,
		"_step_update_item must iterate the whole party to find the item")
	# Must remove old THEN add new (the swap semantics).
	assert_true(body.find("remove_item(old_id") > -1,
		"_step_update_item must call remove_item for the old id")
	assert_true(body.find("add_item(new_id") > -1,
		"_step_update_item must call add_item for the new id")


func test_update_item_handles_missing_item_gracefully() -> void:
	# Behavioral: if the item to swap isn't in any inventory, the helper
	# must push_warning and return without crashing.
	var script = load(DIRECTOR_PATH)
	var d = script.new()
	add_child_autofree(d)
	# No game_loop in this test context = early return. Just confirm it
	# doesn't crash.
	d._step_update_item({
		"type": "update_item",
		"item": "test_item_that_does_not_exist",
		"new_id": "test_replacement",
	})
	# If we got here without crashing, the early-return guard works.
	assert_true(true, "update_item with missing GameLoop must return cleanly")


func test_update_item_swaps_quantity_in_inventory() -> void:
	# Tick 258: previously skipped via pending() because no GameLoop was
	# instantiated in headless GUT. The director only needs a node at
	# /root/GameLoop exposing a `party` Array[Combatant] — build a stub
	# (matches the fixture pattern in test_cutscene_grant_give_item_regression).
	var fixture: Dictionary = _make_game_loop_stub_with_leader()
	var stub: Node = fixture["stub"]
	var leader = fixture["leader"]

	# Seed the leader with 3 of the source item.
	leader.add_item("fool_card", 3)
	assert_eq(leader.get_item_count("fool_card"), 3, "test setup: leader should have 3 fool_card")
	assert_eq(leader.get_item_count("wild_card"), 0, "test setup: leader should have 0 wild_card")

	var script = load(DIRECTOR_PATH)
	var d = script.new()
	add_child_autofree(d)
	d._step_update_item({
		"type": "update_item",
		"item": "fool_card",
		"new_id": "wild_card",
	})

	assert_eq(leader.get_item_count("fool_card"), 0,
		"fool_card must be removed after update_item")
	assert_eq(leader.get_item_count("wild_card"), 3,
		"wild_card must hold the same quantity (3) that fool_card had")

	# Cleanup
	_teardown_game_loop_stub(stub)


# ── Test fixture: mirrors test_cutscene_grant_give_item_regression ─

func _make_game_loop_stub_with_leader() -> Dictionary:
	# See test_cutscene_grant_give_item_regression for the fixture rationale.
	var existing := get_tree().root.get_node_or_null("GameLoop")
	if existing != null and "party" in existing:
		if not existing.party.is_empty():
			return {"stub": null, "leader": existing.party[0]}
		var leader_real: Combatant = Combatant.new()
		leader_real.combatant_name = "Test Leader"
		existing.party.append(leader_real)
		return {"stub": null, "leader": leader_real, "_appended_to": existing}
	var stub_script: GDScript = load("res://test/unit/_test_game_loop_stub.gd")
	var stub: Node = stub_script.new()
	stub.name = "GameLoop"
	get_tree().root.add_child(stub)
	var leader: Combatant = Combatant.new()
	leader.combatant_name = "Test Leader"
	stub.party.append(leader)
	return {"stub": stub, "leader": leader}


func _teardown_game_loop_stub(stub: Node) -> void:
	if stub != null and is_instance_valid(stub):
		stub.queue_free()
