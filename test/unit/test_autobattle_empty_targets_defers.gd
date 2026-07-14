extends GutTest

## tick 111 regression: when an autobattle rule's ability/item action
## carries an explicit `targets` key with an empty array, BattleManager
## must NOT fall back to the lowest_hp_enemy default. Pre-fix, this
## fallback caused:
##
## - A Cleric "regenerate when ally < 50%" rule, with no hurt allies,
##   would target the lowest_hp_enemy — turning a heal into an attack.
## - A "use Phoenix Down when ally is down" rule, with everyone alive,
##   would target the lowest_hp_enemy — throwing the item at the enemy.
##
## AutobattleSystem ALWAYS sets a `targets` key for ability + item
## actions (line ~353 / ~361 of AutobattleSystem). An empty list
## means "the rule's target_type didn't resolve to anyone". The fix
## is to honor that empty list as "defer" instead of silently
## re-targeting the enemy bench.

const BATTLE_MANAGER := "res://src/battle/BattleManager.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func _convert_body() -> String:
	var src := _read(BATTLE_MANAGER)
	var idx: int = src.find("func _convert_autobattle_action")
	assert_gt(idx, -1, "_convert_autobattle_action must exist")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	return src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)


func test_ability_branch_returns_empty_dict_for_explicit_empty_targets() -> void:
	var body := _convert_body()
	# The ability arm must check `action_data.has("targets") and
	# action_targets.size() == 0` BEFORE computing targets_to_use.
	assert_true(body.contains("if action_data.has(\"targets\") and action_targets.size() == 0:"),
		"ability conversion must short-circuit to {} when targets list is explicitly empty — avoid re-targeting heal at enemies")


func test_item_branch_returns_empty_dict_for_explicit_empty_targets() -> void:
	# Same fix for items so Phoenix Down rules don't get thrown at
	# enemies when nobody's KO'd.
	var body := _convert_body()
	# Two occurrences expected (one for ability, one for item).
	var count: int = 0
	var pos: int = 0
	while true:
		var p: int = body.find("if action_data.has(\"targets\") and action_targets.size() == 0:", pos)
		if p == -1:
			break
		count += 1
		pos = p + 1
	assert_eq(count, 2,
		"empty-targets guard must appear EXACTLY twice — once in the ability arm, once in the item arm")


func test_empty_targets_guard_precedes_targets_to_use_assignment() -> void:
	# Ordering: the empty-targets early-return must fire BEFORE the
	# targets_to_use fallback ([resolved_target]). If the order
	# inverts, the lowest_hp_enemy default still wins.
	var body := _convert_body()
	# Locate the first occurrence of each pattern in the ability arm.
	var guard_idx: int = body.find("if action_data.has(\"targets\") and action_targets.size() == 0:")
	var targets_to_use_idx: int = body.find("var targets_to_use = action_targets if has_direct_targets")
	assert_gt(guard_idx, -1, "empty-targets guard must exist")
	assert_gt(targets_to_use_idx, -1, "targets_to_use assignment must exist")
	assert_lt(guard_idx, targets_to_use_idx,
		"empty-targets guard must precede targets_to_use assignment in source — otherwise the fallback to lowest_hp_enemy still wins")


func test_attack_branch_unchanged() -> void:
	# Negative pin: the attack arm should NOT have the empty-targets
	# guard. Attack actions from AutobattleSystem don't carry a
	# `targets` key (they use singular `target`), so the guard
	# wouldn't be wrong but it'd be misleading. Keep attack behavior
	# strictly unchanged.
	var body := _convert_body()
	# Find the attack arm.
	var attack_idx: int = body.find("\"attack\":")
	var ability_idx: int = body.find("\"ability\":")
	assert_gt(attack_idx, -1, "attack arm must exist")
	assert_gt(ability_idx, -1, "ability arm must exist")
	var attack_body: String = body.substr(attack_idx, ability_idx - attack_idx)
	assert_false(attack_body.contains("action_data.has(\"targets\") and action_targets.size() == 0"),
		"attack arm must NOT have the empty-targets guard — attack uses singular `target`, not `targets`")


func test_resolved_target_fallback_path_still_present_for_no_targets_key() -> void:
	# Sanity: when an autobattle action genuinely has NO `targets`
	# key (older script formats, or attack actions), the
	# resolved_target fallback must still apply. Don't break the
	# pre-existing path.
	var body := _convert_body()
	assert_true(body.contains("var targets_to_use = action_targets if has_direct_targets else ([resolved_target] if resolved_target else [])"),
		"the existing resolved_target fallback path must remain — covers actions without a `targets` key (older scripts, attack actions)")
