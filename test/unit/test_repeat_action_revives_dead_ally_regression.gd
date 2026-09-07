extends GutTest

## 2026-07-14 (cowir-music msg 2539): "target no longer valid" when using
## Phoenix Down on a dead Bard via Y-repeat.
##
## Root: BattleManager._repeat_previous_actions retargeted ANY dead
## target to first alive enemy — Phoenix Down + revival-type abilities
## EXPECT dead targets, so the retarget torched their intent.
##
## Fix: _action_revives() flag gates the "invalidate dead target" branch.
## Item.effects.revive OR ability.type=='revival' OR
## ability.target_type=='dead_ally' OR ability.has(revive_percentage)
## keeps the dead target intact.


func test_action_revives_helper_declared() -> void:
	var src := FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	assert_true("func _action_revives(action: Dictionary) -> bool" in src,
		"BattleManager must declare _action_revives helper — repeat + retarget flow calls it")
	# All 4 revive shapes must be recognized.
	var i := src.find("func _action_revives")
	var next: int = src.find("\nfunc ", i + 1)
	var body := src.substr(i, (next - i) if next > -1 else 800)
	assert_true("effects" in body and "revive" in body,
		"revive item detection must consult item.effects.revive (Phoenix Down)")
	assert_true("\"revival\"" in body,
		"revival-type abilities must be recognized")
	assert_true("\"dead_ally\"" in body,
		"target_type=='dead_ally' abilities must be recognized (Raise)")
	assert_true("revive_percentage" in body,
		"abilities with revive_percentage must be recognized")


func test_repeat_single_target_gates_dead_invalidation() -> void:
	var src := FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	var i := src.find("var target_dead: bool = target_valid and target is Combatant and not target.is_alive")
	assert_gt(i, -1)
	var body := src.substr(i, 400)
	assert_true("_action_revives(action)" in body,
		"single-target retarget must consult _action_revives before invalidating dead targets")
	assert_true("target_dead and not " in body,
		"the guard must be `(target_dead AND NOT revives)` so revive actions keep their dead target")


func test_repeat_multi_target_admits_dead_ally_for_revives() -> void:
	var src := FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	var i := src.find("var revives: bool = _action_revives(action)")
	assert_gt(i, -1, "targets[] loop must compute a revives flag once")
	var body := src.substr(i, 800)
	assert_true("is_dead_ally_in_battle" in body,
		"multi-target retarget must recognize dead-ally-in-party as a valid revive target")
	assert_true("(revives and is_dead_ally_in_battle)" in body,
		"the admit branch must be `alive OR (revives AND dead_ally_in_party)`")


func test_phoenix_down_item_shape_still_authored_correctly() -> void:
	# Anti-regression: if items.json ever drops effects.revive, the whole
	# gate silently fails open. Pin the schema.
	var items = JSON.parse_string(FileAccess.get_file_as_string("res://data/items.json"))
	var pd: Dictionary = items.get("phoenix_down", {})
	assert_true(pd.get("effects", {}).get("revive", false) == true,
		"phoenix_down.effects.revive must be true — the retarget gate depends on it")
