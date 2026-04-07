extends GutTest

## Tests for HeadlessBattleResolver edge cases


func _make_combatant(name: String, hp: int = 100, atk: int = 15, def: int = 10, spd: int = 10, mp: int = 20) -> Combatant:
	var c = Combatant.new()
	c.initialize({
		"name": name,
		"max_hp": hp,
		"max_mp": mp,
		"attack": atk,
		"defense": def,
		"magic": 5,
		"speed": spd
	})
	add_child_autofree(c)
	return c


func _make_dead_combatant(name: String) -> Combatant:
	var c = _make_combatant(name, 100)
	c.current_hp = 0
	c.is_alive = false
	return c


## Edge case: empty party

func test_empty_player_party_returns_defeat() -> void:
	var resolver = HeadlessBattleResolver.new()
	var enemy = _make_combatant("Slime", 30)
	var result = resolver.resolve_battle([], [enemy])
	assert_false(result["victory"], "Empty party should lose")
	assert_eq(result["rounds"], 0, "Should be 0 rounds")


func test_all_dead_player_party_returns_defeat() -> void:
	var resolver = HeadlessBattleResolver.new()
	var dead1 = _make_dead_combatant("Dead1")
	var dead2 = _make_dead_combatant("Dead2")
	var enemy = _make_combatant("Slime", 30)
	var result = resolver.resolve_battle([dead1, dead2], [enemy])
	assert_false(result["victory"], "All-dead party should lose")
	assert_eq(result["rounds"], 0, "Should be 0 rounds")


func test_empty_enemy_party_returns_victory() -> void:
	var resolver = HeadlessBattleResolver.new()
	var player = _make_combatant("Fighter", 100, 20)
	var result = resolver.resolve_battle([player], [])
	assert_true(result["victory"], "No enemies should be victory")
	assert_eq(result["exp_gained"], 0, "No enemies = 0 EXP")
	assert_eq(result["rounds"], 0, "Should be 0 rounds")


## Normal battle resolution

func test_basic_battle_resolves() -> void:
	var resolver = HeadlessBattleResolver.new()
	var player = _make_combatant("Fighter", 200, 30, 15, 12)
	var enemy = _make_combatant("Slime", 20, 5, 3, 5)
	var result = resolver.resolve_battle([player], [enemy])
	assert_true(result["victory"], "Strong player should beat weak slime")
	assert_gt(result["exp_gained"], 0, "Should gain EXP")
	assert_gt(result["gold_gained"], 0, "Should gain gold")
	assert_gt(result["rounds"], 0, "Should take at least 1 round")


func test_weak_player_can_lose() -> void:
	var resolver = HeadlessBattleResolver.new()
	var player = _make_combatant("Weakling", 10, 1, 1, 1)
	var enemy = _make_combatant("Boss", 500, 50, 30, 20)
	var result = resolver.resolve_battle([player], [enemy])
	assert_false(result["victory"], "Weak player should lose to boss")


func test_max_rounds_cap() -> void:
	# Two combatants that can't kill each other (high def, low atk)
	var resolver = HeadlessBattleResolver.new()
	var player = _make_combatant("Tank", 9999, 1, 999, 1)
	var enemy = _make_combatant("Wall", 9999, 1, 999, 1)
	var result = resolver.resolve_battle([player], [enemy])
	assert_eq(result["rounds"], HeadlessBattleResolver.MAX_ROUNDS, "Should cap at MAX_ROUNDS")
	assert_false(result["victory"], "Timeout should be defeat")


## Status effect tests

func test_stunned_combatant_skips_turn() -> void:
	var resolver = HeadlessBattleResolver.new()
	var result = resolver._check_status_skip(_make_stunned_combatant())
	assert_eq(result, "skip", "Stunned should skip")


func test_stun_removed_after_skip() -> void:
	var c = _make_stunned_combatant()
	var resolver = HeadlessBattleResolver.new()
	resolver._check_status_skip(c)
	assert_false(c.has_status("stun"), "Stun should be removed after skip")


func _make_stunned_combatant() -> Combatant:
	var c = _make_combatant("Stunned", 100)
	c.add_status("stun", 1)
	return c


func test_confused_attack_targets_anyone() -> void:
	var resolver = HeadlessBattleResolver.new()
	resolver._player_party = [_make_combatant("Ally", 100)]
	resolver._enemy_party = [_make_combatant("Foe", 100)]
	var c = _make_combatant("Confused", 100)
	var action = resolver._confused_attack(c)
	assert_eq(action["type"], "attack", "Confused should attack")
	assert_true(action.has("target"), "Should have a target")


## Result structure

func test_result_has_gold_gained() -> void:
	var resolver = HeadlessBattleResolver.new()
	var player = _make_combatant("Fighter", 200, 30)
	var enemy = _make_combatant("Slime", 20, 5, 3)
	var result = resolver.resolve_battle([player], [enemy])
	assert_true(result.has("gold_gained"), "Result should include gold_gained")


func test_result_has_battle_log() -> void:
	var resolver = HeadlessBattleResolver.new()
	var player = _make_combatant("Fighter", 200, 30)
	var enemy = _make_combatant("Slime", 20, 5, 3)
	var result = resolver.resolve_battle([player], [enemy])
	assert_true(result.has("log"), "Result should include battle log")
	assert_gt(result["log"].size(), 0, "Log should have entries")
