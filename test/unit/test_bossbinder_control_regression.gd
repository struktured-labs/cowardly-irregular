extends GutTest

## Bossbinder control fix (2026-07-09): full_boss_control and mind_swap
## applied their statuses and the enemy AI IGNORED them — the job's whole
## promise was decoration. Now a controlled/swapped enemy fights its OWN
## side while the status holds; a solo boss turns on itself. Pins the
## targeting swap through the real AI-selection path.


func _combatant(cname: String, side_hp: int = 200) -> Combatant:
	var c := Combatant.new()
	add_child_autofree(c)
	c.initialize({"name": cname, "max_hp": side_hp, "max_mp": 20, "attack": 20,
		"defense": 5, "magic": 5, "speed": 10})
	c.current_ap = 0
	return c


func _run_selection(controlled_status: String) -> Dictionary:
	var hero := _combatant("Hero")
	var boss := _combatant("Boss")
	var minion := _combatant("Minion")
	var prev_party: Array = BattleManager.player_party
	var prev_enemies = BattleManager.enemy_party
	var prev_pending: Array = BattleManager.pending_actions.duplicate()
	BattleManager.player_party = [hero]
	BattleManager.enemy_party = [boss, minion]
	BattleManager.pending_actions = []
	if controlled_status != "":
		boss.add_status(controlled_status)

	BattleManager._process_ai_selection(boss)
	var queued: Dictionary = BattleManager.pending_actions[-1] if not BattleManager.pending_actions.is_empty() else {}

	BattleManager.player_party = prev_party
	BattleManager.enemy_party = prev_enemies
	BattleManager.pending_actions = prev_pending
	return {"action": queued, "hero": hero, "boss": boss, "minion": minion}


func _action_targets(action: Dictionary) -> Array:
	if action.has("targets") and action["targets"] is Array:
		return action["targets"]
	if action.has("target"):
		return [action["target"]]
	return []


func test_controlled_boss_targets_its_own_side() -> void:
	for status in ["controlled", "mind_swap"]:
		var r := _run_selection(status)
		var targets := _action_targets(r["action"])
		assert_false(targets.is_empty(), "%s: an action queued with targets" % status)
		for t in targets:
			assert_true(t == r["minion"] or t == r["boss"],
				"%s: controlled enemy must target its OWN side, not %s" % [status, str(t.combatant_name if t is Combatant else t)])
			assert_true(t != r["hero"], "%s: the player is safe this turn" % status)


func test_uncontrolled_boss_still_hunts_the_party() -> void:
	var r := _run_selection("")
	var targets := _action_targets(r["action"])
	assert_false(targets.is_empty(), "baseline action queued")
	for t in targets:
		assert_eq(t, r["hero"], "no status -> normal AI targets the party")


func test_tooltips_match_the_implementation() -> void:
	var a = JSON.parse_string(FileAccess.get_file_as_string("res://data/abilities.json"))
	assert_true("its own side" in str(a["control_override"].get("description", "")),
		"control_override tooltip describes the real effect")
	assert_true("its own side" in str(a["mind_swap"].get("description", "")),
		"mind_swap tooltip describes the real effect")
