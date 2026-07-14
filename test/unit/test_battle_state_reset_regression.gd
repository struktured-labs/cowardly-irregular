extends GutTest

## Review find 2026-07-03 (critical): BattleManager.current_state was
## NEVER reset to INACTIVE — after the first battle it sat at
## VICTORY/DEFEAT for the rest of the session, so every
## "!= INACTIVE means in-battle" gate (level-up toasts, spotlight
## reconcile) read in-battle forever. Out-of-battle quest-EXP
## level-ups toasted nothing, silently.


func test_cleanup_returns_state_to_inactive() -> void:
	var saved_state = BattleManager.current_state
	var saved_pp: Array = BattleManager.player_party.duplicate()
	var saved_ep: Array = BattleManager.enemy_party.duplicate()
	BattleManager.player_party.clear()
	BattleManager.enemy_party.clear()
	BattleManager.current_state = BattleManager.BattleState.VICTORY
	BattleManager._cleanup_battle()
	assert_eq(BattleManager.current_state, BattleManager.BattleState.INACTIVE,
		"cleanup must return the state machine to INACTIVE or every != INACTIVE gate lies for the rest of the session")
	BattleManager.current_state = saved_state
	for c in saved_pp:
		BattleManager.player_party.append(c)
	for c in saved_ep:
		BattleManager.enemy_party.append(c)


func test_headless_rewards_are_authored_not_stat_derived() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/autogrind/HeadlessBattleResolver.gd")
	assert_true(src.contains("get(\"exp_reward\", 25)"),
		"headless EXP must read authored exp_reward — full-parity ruling")
	assert_true(src.contains("get(\"gold_reward\""),
		"headless gold must read authored gold_reward — same parity")
	assert_false(src.contains("exp += int(enemy.max_hp * 0.5"),
		"the stat-derived EXP formula is the parity regression")
