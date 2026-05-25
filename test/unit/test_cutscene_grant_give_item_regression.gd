extends GutTest

## Regression: cutscene grant_item / give_item step types must dispatch
## to real handlers that add to inventory. Pre-fix the CutsceneDirector
## match statement didn't include these cases — 30+ occurrences across
## 9+ cutscene JSONs (including W1 fragments, world1_orrery, all six
## Masterite-fragment cutscenes) silently fell through to push_warning
## and the player got nothing despite the dialogue saying "Take this."
##
## grant_item is for key/META items (KeyItemPopup), give_item is for
## ordinary cutscene rewards (silent — cutscene narrative provides
## context).

const DIRECTOR_PATH := "res://src/cutscene/CutsceneDirector.gd"
const COMBATANT_PATH := "res://src/battle/Combatant.gd"


func _read(path: String) -> String:
	var file = FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "file should exist: %s" % path)
	var text = file.get_as_text()
	file.close()
	return text


func test_dispatch_handles_grant_item() -> void:
	# Source pin: match statement in _execute_step must include grant_item.
	var text = _read(DIRECTOR_PATH)
	var match_idx = text.find("func _execute_step")
	assert_true(match_idx > -1, "_execute_step must exist")
	var fn_end = text.find("\n\nfunc ", match_idx)
	var body = text.substr(match_idx, fn_end - match_idx) if fn_end > -1 else text.substr(match_idx, 1500)
	assert_true(body.find("\"grant_item\":") > -1,
		"_execute_step match must include grant_item case (was silently dropped pre-fix)")
	assert_true(body.find("\"give_item\":") > -1,
		"_execute_step match must include give_item case")


func test_grant_item_handler_exists_with_popup_wiring() -> void:
	var text = _read(DIRECTOR_PATH)
	assert_true(text.find("func _step_grant_item(step: Dictionary)") > -1,
		"_step_grant_item handler must exist")
	# The grant variant must call KeyItemPopup.show_item with the supplied
	# name + description so the player actually sees the reveal.
	var fn_idx = text.find("func _step_grant_item(")
	var fn_end = text.find("\n\n\nfunc ", fn_idx)
	var body = text.substr(fn_idx, fn_end - fn_idx) if fn_end > -1 else text.substr(fn_idx, 1200)
	assert_true(body.find("KeyItemPopup.show_item(") > -1,
		"_step_grant_item must invoke KeyItemPopup.show_item — otherwise the popup ships dead")
	assert_true(body.find("await popup.dismissed") > -1,
		"_step_grant_item must await popup.dismissed so the cutscene pauses on the reveal")
	# Skip path: when player is skipping the cutscene we still add the
	# item but skip the popup (don't force a wait through a skip).
	assert_true(body.find("if _skipping:") > -1,
		"_step_grant_item must guard the popup behind _skipping check — skipped runs still add the item, just no popup")


func test_grant_item_actually_adds_to_party_leader() -> void:
	if not GameState:
		pending("GameState autoload missing")
		return
	# Need a GameLoop autoload for the inventory routing to land.
	var game_loop = get_tree().root.get_node_or_null("GameLoop")
	if game_loop == null or not "party" in game_loop or game_loop.party.is_empty():
		pending("GameLoop with non-empty party not available — skipping behavioral test")
		return

	var leader = game_loop.party[0]
	var prev_quantity = leader.get_item_count("phoenix_down") if leader.has_method("get_item_count") else 0

	# Drive _step_grant_item via direct instance call (skipping the cutscene
	# UI/timing entirely).
	var script = load(DIRECTOR_PATH)
	var d = script.new()
	add_child_autofree(d)
	d._skipping = true  # bypass the popup so we don't need to await
	await d._step_grant_item({
		"type": "grant_item",
		"item": "phoenix_down",
		"name": "Phoenix Down (Test)",
		"description": "Test description",
		"quantity": 2,
	})

	var new_quantity = leader.get_item_count("phoenix_down") if leader.has_method("get_item_count") else -1
	assert_eq(new_quantity, prev_quantity + 2,
		"grant_item must add quantity to party leader inventory (was %d, now %d, expected delta=2)" % [
			prev_quantity, new_quantity])

	# Cleanup
	if leader.has_method("remove_item"):
		leader.remove_item("phoenix_down", 2)


func test_give_item_handler_silent_no_popup() -> void:
	var text = _read(DIRECTOR_PATH)
	assert_true(text.find("func _step_give_item(step: Dictionary)") > -1,
		"_step_give_item handler must exist")
	var fn_idx = text.find("func _step_give_item(")
	var fn_end = text.find("\n\n\nfunc ", fn_idx)
	var body = text.substr(fn_idx, fn_end - fn_idx) if fn_end > -1 else text.substr(fn_idx, 800)
	# give_item must NOT show a popup — it's the silent variant for
	# ordinary cutscene rewards. KeyItemPopup is reserved for grant_item.
	assert_false(body.find("KeyItemPopup") > -1,
		"_step_give_item must NOT show KeyItemPopup — that's grant_item's job; give_item stays silent")
	# But it MUST add to inventory via the shared helper.
	assert_true(body.find("_add_item_to_party_leader(") > -1,
		"_step_give_item must call _add_item_to_party_leader — otherwise the cutscene drops the item silently")


func test_handlers_warn_on_missing_item_field() -> void:
	# Source pin: both handlers should push_warning when step lacks the
	# item field, rather than silently doing nothing.
	var text = _read(DIRECTOR_PATH)
	# Look at both handler bodies — both must call push_warning for the
	# missing-item case.
	var grant_idx = text.find("func _step_grant_item(")
	var give_idx = text.find("func _step_give_item(")
	for fn_idx in [grant_idx, give_idx]:
		assert_true(fn_idx > -1, "Both step handlers must exist")
		var fn_end = text.find("\n\n\nfunc ", fn_idx)
		var body = text.substr(fn_idx, fn_end - fn_idx) if fn_end > -1 else text.substr(fn_idx, 800)
		assert_true(body.find("push_warning") > -1,
			"Handler at idx %d must push_warning on malformed step (missing item field)" % fn_idx)
