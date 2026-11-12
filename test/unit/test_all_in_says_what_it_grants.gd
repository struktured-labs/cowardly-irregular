extends GutTest

## All In's description promised "extra actions this turn", but its handler (brave_actions) grants the caster AP when
## the action resolves, which only a LATER turn's Advance can spend. The description now states the grant, and this
## guard ties its number to the handler's own: change ap_grant and the description must change with it.

const HANDLER_DEFAULT_GRANT := 2  ## brave_actions' `ability.get("ap_grant", 2)`, checked against the source below


func _brave() -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/abilities.json"))
	return (parsed as Dictionary).get("brave", {}) if parsed is Dictionary else {}


func test_the_handler_default_is_the_one_this_guard_reads() -> void:
	var src := FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	var arm := src.find("\"brave_actions\":")
	assert_gt(arm, -1, "CONTROL: the brave_actions arm exists")
	assert_true(src.substr(arm, 400).contains("ability.get(\"ap_grant\", %d)" % HANDLER_DEFAULT_GRANT),
		"the handler's default grant must be the one this guard expects, or the guard checks a stale number")


func test_all_in_states_the_ap_it_grants() -> void:
	var brave := _brave()
	assert_eq(str(brave.get("effect", "")), "brave_actions", "CONTROL: All In is still the brave_actions ability")
	var grant := int(brave.get("ap_grant", HANDLER_DEFAULT_GRANT))
	var desc := str(brave.get("description", ""))
	assert_true(desc.contains("%d AP" % grant), "All In's description must state the %d AP it grants: '%s'" % [grant, desc])


func test_all_in_does_not_promise_actions_this_turn() -> void:
	var desc := str(_brave().get("description", "")).to_lower()
	assert_false(desc.contains("this turn"),
		"the AP arrives when All In resolves, so only a later turn can spend it: '%s'" % desc)
