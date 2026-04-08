extends GutTest

## Unit tests for AutogrindSystem
## Tests interrupt conditions, enemy scaling, efficiency/corruption growth, region crack

var _system: Node
var _party: Array[Combatant] = []


func before_each() -> void:
	# Create a fresh AutogrindSystem instance for isolated testing
	_system = preload("res://src/autogrind/AutogrindSystem.gd").new()
	add_child_autofree(_system)

	# Reset state (after _ready which loads profiles)
	_system.is_grinding = false
	_system.battles_completed = 0
	_system.total_exp_gained = 0
	_system.total_items_gained.clear()
	_system.efficiency_multiplier = 1.0
	_system.monster_adaptation_level = 0.0
	_system.meta_corruption_level = 0.0
	_system.meta_boss_spawn_chance = 0.0
	_system.consecutive_wins = 0
	_system.current_region_id = ""
	_system.region_crack_levels.clear()
	_system.permadeath_staking_enabled = false
	_system.permadead_characters.clear()
	_system.collapse_count = 0
	_system.fatigue_events_triggered = 0
	_system.items_consumed.clear()
	_system.per_character_exp.clear()
	_system.interrupt_rules = {
		"hp_threshold": 20.0,
		"party_death": true,
		"item_depleted": true,
		"corruption_limit": 4.5,
		"max_battles": 100
	}

	# Create test party
	_party.clear()
	for i in range(4):
		var member = Combatant.new()
		member.initialize({
			"name": "TestChar%d" % i,
			"max_hp": 100,
			"max_mp": 50,
			"attack": 20,
			"defense": 15,
			"magic": 10,
			"speed": 12
		})
		member.add_item("potion", 3)
		add_child_autofree(member)
		_party.append(member)

	_system.grind_party = _party


## _check_interrupt_conditions() tests

func test_interrupt_check_no_issues() -> void:
	var reason = _system._check_interrupt_conditions()
	assert_eq(reason, "", "No interrupt with healthy party and items")


func test_interrupt_check_hp_threshold() -> void:
	_party[0].current_hp = 10  # 10% HP, below 20% threshold
	var reason = _system._check_interrupt_conditions()
	assert_ne(reason, "", "Should interrupt when HP below threshold")
	assert_true(reason.contains("HP threshold"), "Reason should mention HP threshold")


func test_interrupt_check_hp_threshold_off() -> void:
	_system.interrupt_rules["hp_threshold"] = 0.0  # OFF
	_party[0].current_hp = 10  # Low HP
	var reason = _system._check_interrupt_conditions()
	assert_eq(reason, "", "Should NOT interrupt when HP threshold is OFF")


func test_interrupt_check_party_death() -> void:
	_party[1].is_alive = false
	var reason = _system._check_interrupt_conditions()
	assert_ne(reason, "", "Should interrupt when party member dies")
	assert_true(reason.contains("Party member died"), "Reason should mention party death")


func test_interrupt_check_party_death_off() -> void:
	_system.interrupt_rules["party_death"] = false
	_party[1].is_alive = false
	var reason = _system._check_interrupt_conditions()
	assert_eq(reason, "", "Should NOT interrupt when party death rule is OFF")


func test_interrupt_check_items_depleted() -> void:
	# Remove all healing items from all members
	for member in _party:
		member.inventory.clear()
	var reason = _system._check_interrupt_conditions()
	assert_ne(reason, "", "Should interrupt when healing items depleted")
	assert_true(reason.contains("items depleted"), "Reason should mention items")


func test_interrupt_check_corruption_limit() -> void:
	_system.meta_corruption_level = 4.5
	var reason = _system._check_interrupt_conditions()
	assert_ne(reason, "", "Should interrupt at corruption limit")
	assert_true(reason.contains("Corruption"), "Reason should mention corruption")


func test_interrupt_check_max_battles() -> void:
	_system.battles_completed = 100
	var reason = _system._check_interrupt_conditions()
	assert_ne(reason, "", "Should interrupt at max battles")
	assert_true(reason.contains("Max battles"), "Reason should mention max battles")


## _create_adapted_enemy() tests

func test_create_adapted_enemy_no_adaptation() -> void:
	_system.monster_adaptation_level = 0.0
	_system.grind_enemy_template = {
		"id": "slime", "name": "Slime",
		"max_hp": 80, "attack": 10, "defense": 8, "magic": 5
	}
	var scaled = _system._create_adapted_enemy()
	assert_eq(scaled["max_hp"], 80, "No scaling at adaptation 0")
	assert_eq(scaled["attack"], 10, "No scaling at adaptation 0")


func test_create_adapted_enemy_with_adaptation() -> void:
	_system.monster_adaptation_level = 2.0  # +30% stats
	_system.grind_enemy_template = {
		"id": "slime", "name": "Slime",
		"max_hp": 100, "attack": 10, "defense": 10, "magic": 10
	}
	var scaled = _system._create_adapted_enemy()
	# 2.0 * 0.15 = 0.30 bonus -> 130% of base
	assert_eq(scaled["max_hp"], 130, "HP should be scaled 130%")
	assert_eq(scaled["attack"], 13, "Attack should be scaled 130%")
	assert_eq(scaled["defense"], 13, "Defense should be scaled 130%")
	assert_eq(scaled["magic"], 13, "Magic should be scaled 130%")


func test_create_adapted_enemy_corruption_effects() -> void:
	_system.monster_adaptation_level = 0.0
	_system.meta_corruption_level = 3.0
	_system.grind_enemy_template = {
		"id": "slime", "name": "Slime",
		"max_hp": 80, "attack": 10, "defense": 8, "magic": 5
	}
	var scaled = _system._create_adapted_enemy()
	assert_true(scaled.has("corruption_effects"), "Should have corruption effects at corruption >= 2.0")
	assert_true(scaled["corruption_effects"].has("reality_bending"), "Should have reality_bending at corruption >= 2.0")
	assert_true(scaled["corruption_effects"].has("time_distortion"), "Should have time_distortion at corruption >= 3.0")


func test_create_adapted_enemy_no_corruption_effects_below_threshold() -> void:
	_system.monster_adaptation_level = 0.0
	_system.meta_corruption_level = 1.5
	_system.grind_enemy_template = {
		"id": "slime", "name": "Slime",
		"max_hp": 80, "attack": 10, "defense": 8, "magic": 5
	}
	var scaled = _system._create_adapted_enemy()
	assert_false(scaled.has("corruption_effects"), "Should NOT have corruption effects below 2.0")


## Battle result processing tests

func test_victory_increments_stats() -> void:
	_system.is_grinding = true
	_system._process_battle_results({"victory": true, "exp_gained": 100, "items_gained": {"potion": 1}})
	assert_eq(_system.consecutive_wins, 1, "Wins should increment")
	assert_gt(_system.total_exp_gained, 0, "EXP should be gained")
	assert_true(_system.total_items_gained.has("potion"), "Items should be tracked")


func test_efficiency_increases() -> void:
	var old_eff = _system.efficiency_multiplier
	_system._increase_efficiency()
	assert_gt(_system.efficiency_multiplier, old_eff, "Efficiency should increase")


func test_corruption_increases() -> void:
	_system._increase_efficiency()
	assert_gt(_system.meta_corruption_level, 0.0, "Corruption should increase after efficiency gain")


## Region crack tests

func test_region_crack_penalty_no_crack() -> void:
	_system.current_region_id = "test_region"
	_system.region_crack_levels["test_region"] = 0
	var penalty = _system._get_region_crack_penalty()
	assert_eq(penalty, 0.0, "No penalty at crack level 0")


func test_region_crack_penalty_level_1() -> void:
	_system.current_region_id = "test_region"
	_system.region_crack_levels["test_region"] = 1
	var penalty = _system._get_region_crack_penalty()
	assert_almost_eq(penalty, 0.15, 0.01, "15% penalty at crack level 1")


func test_region_crack_penalty_max_cap() -> void:
	_system.current_region_id = "test_region"
	_system.region_crack_levels["test_region"] = 10  # Very high level
	var penalty = _system._get_region_crack_penalty()
	assert_almost_eq(penalty, 0.75, 0.01, "Penalty capped at 75%")


func test_region_crack_triggers_after_wins() -> void:
	_system.current_region_id = "test_region"
	_system.region_crack_levels["test_region"] = 0
	_system.consecutive_wins = 19  # One more win needed
	_system.wins_to_crack_region = 20
	_system.is_grinding = true
	_system._process_battle_results({"victory": true, "exp_gained": 100, "items_gained": {}})
	assert_eq(_system.region_crack_levels["test_region"], 1, "Region should crack after 20 wins")


## Efficiency growth rate test

func test_efficiency_growth_rate() -> void:
	# Run 10 efficiency increases
	for i in range(10):
		_system._increase_efficiency()
	# Efficiency should be 1.0 + 10 * 0.1 = 2.0
	assert_almost_eq(_system.efficiency_multiplier, 2.0, 0.01, "Efficiency should grow by 0.1 per battle")


## Defeat test

func test_defeat_resets_wins() -> void:
	_system.is_grinding = true
	_system.consecutive_wins = 5
	_system._process_battle_results({"victory": false, "exp_gained": 0, "items_gained": {}})
	assert_eq(_system.consecutive_wins, 0, "Consecutive wins should reset on defeat")


## JP tracking regression tests (Task #2)

func test_victory_accumulates_jp() -> void:
	# Regression: on_battle_victory must increment _grind_stats["total_jp"]
	_system.is_grinding = true
	_system.current_region_id = ""  # No region = yield 1.0
	_system._grind_stats = {
		"start_time": 0.0, "total_exp": 0, "total_gold": 0,
		"total_jp": 0, "total_encounters": 0, "elapsed_seconds": 0.0
	}
	_system.on_battle_victory(100)
	assert_gt(_system._grind_stats["total_jp"], 0, "JP should be tracked after battle victory")


func test_jp_is_at_least_1_per_battle() -> void:
	# Regression: jp_gained must never be 0 (maxi(1,...) guard)
	_system.is_grinding = true
	_system.current_region_id = "test_region"
	_system.region_crack_levels["test_region"] = 5  # High crack = low yield
	_system._grind_stats = {
		"start_time": 0.0, "total_exp": 0, "total_gold": 0,
		"total_jp": 0, "total_encounters": 0, "elapsed_seconds": 0.0
	}
	_system.on_battle_victory(0)  # Zero EXP battle
	assert_gte(_system._grind_stats["total_jp"], 1, "JP should be at least 1 per victory")


## Adaptive AI pattern learning regression tests (Task #2)

func test_update_learned_patterns_stores_ability_frequency() -> void:
	# Regression: update_learned_patterns must accumulate ability usage counts
	var summary = {
		"ability_frequency": {"fire": 3, "cure": 1},
		"target_priority": {"lowest_hp": 2},
		"common_opener": "fire"
	}
	_system.update_learned_patterns("forest", summary)
	var patterns = _system.get_learned_patterns_for_region("forest")
	assert_eq(patterns["ability_frequency"].get("fire", 0), 3, "Fire ability count should be stored")
	assert_eq(patterns["ability_frequency"].get("cure", 0), 1, "Cure ability count should be stored")
	assert_eq(patterns["battles_analyzed"], 1, "Battle count should increment")


func test_update_learned_patterns_accumulates_across_battles() -> void:
	# Regression: multiple calls must accumulate not overwrite
	var summary1 = {
		"ability_frequency": {"fire": 3},
		"target_priority": {"lowest_hp": 1},
		"common_opener": "fire"
	}
	var summary2 = {
		"ability_frequency": {"fire": 2, "blizzard": 1},
		"target_priority": {"lowest_hp": 2},
		"common_opener": "blizzard"
	}
	_system.update_learned_patterns("cave", summary1)
	_system.update_learned_patterns("cave", summary2)
	var patterns = _system.get_learned_patterns_for_region("cave")
	assert_eq(patterns["ability_frequency"].get("fire", 0), 5, "Fire counts should accumulate (3+2)")
	assert_eq(patterns["ability_frequency"].get("blizzard", 0), 1, "Blizzard from second battle")
	assert_eq(patterns["battles_analyzed"], 2, "Two battles analyzed")


func test_determine_counter_strategy_fire() -> void:
	# Regression: fire-heavy ability usage must produce fire_resist strategy
	var summary = {
		"ability_frequency": {"fire": 10},
		"target_priority": {},
		"common_opener": "fire"
	}
	_system.update_learned_patterns("plains", summary)
	var strategy = _system.get_counter_strategy("plains")
	assert_eq(strategy, "fire_resist", "Fire-heavy enemies should trigger fire_resist counter")


func test_create_scaled_enemy_embeds_counter_strategy() -> void:
	# Regression: create_scaled_enemy_data must embed counter_strategy when learned
	_system.current_region_id = "test_region"
	var summary = {
		"ability_frequency": {"cure": 5},
		"target_priority": {},
		"common_opener": "cure"
	}
	_system.update_learned_patterns("test_region", summary)
	var base_data = {
		"id": "slime", "name": "Slime",
		"stats": {"max_hp": 50, "attack": 8, "defense": 6, "magic": 4, "speed": 8, "max_mp": 20}
	}
	var scaled = _system.create_scaled_enemy_data(base_data)
	assert_true(scaled.has("counter_strategy"), "Scaled enemy must carry counter_strategy when region has patterns")
	assert_eq(scaled["counter_strategy"], "focus_healer", "Healer-heavy enemies should embed focus_healer counter")


## ═══════════════════════════════════════════════════════════════════════
## Task #3 Regression Tests: Meta-boss spawning, system collapse,
##   permadeath persistence, post-collapse debuff
## ═══════════════════════════════════════════════════════════════════════

func test_build_meta_boss_returns_dict_with_required_keys() -> void:
	# Regression: _spawn_meta_boss was a stub that stopped grind without returning data.
	# Now build_meta_boss_enemy_data must return a usable enemy dictionary.
	_system.meta_corruption_level = 2.5
	var boss_data = _system.build_meta_boss_enemy_data(false)
	assert_true(boss_data is Dictionary, "build_meta_boss_enemy_data must return a Dictionary")
	assert_true(boss_data.has("name"), "Boss data must have 'name'")
	assert_true(boss_data.has("max_hp"), "Boss data must have 'max_hp'")
	assert_gt(boss_data["max_hp"], 0, "Boss HP must be > 0")
	assert_true(boss_data.get("is_meta_boss", false), "Boss data must flag is_meta_boss=true")


func test_build_collapse_boss_is_stronger() -> void:
	# Regression: collapse boss must be harder than regular meta boss at same corruption.
	_system.meta_corruption_level = 3.0
	var regular = _system.build_meta_boss_enemy_data(false)
	var collapse = _system.build_meta_boss_enemy_data(true)
	assert_gte(collapse["max_hp"], regular["max_hp"], "Collapse boss must have >= HP than regular meta boss")
	assert_true(collapse.get("is_collapse_boss", false), "Collapse boss must flag is_collapse_boss=true")


func test_meta_boss_scales_with_corruption() -> void:
	# Regression: meta boss stats should scale with corruption level.
	_system.meta_corruption_level = 0.0
	var low_corr = _system.build_meta_boss_enemy_data(false)
	_system.meta_corruption_level = 5.0
	var high_corr = _system.build_meta_boss_enemy_data(false)
	assert_gte(high_corr["max_hp"], low_corr["max_hp"],
		"Meta boss HP must increase with corruption level")


func test_spawn_meta_boss_returns_data_not_empty() -> void:
	# Regression: _spawn_meta_boss formerly returned nothing (void stub).
	# It must now return the boss dictionary.
	_system.meta_corruption_level = 2.0
	var result = _system._spawn_meta_boss()
	assert_true(result is Dictionary and not result.is_empty(),
		"_spawn_meta_boss must return a non-empty Dictionary")
	assert_true(result.has("name"), "_spawn_meta_boss result must have a name")


func test_on_meta_boss_victory_reduces_corruption() -> void:
	# Regression: winning meta-boss fight must reduce corruption.
	_system.is_grinding = true
	_system.meta_corruption_level = 3.0
	_system._grind_stats = {
		"start_time": 0.0, "total_exp": 0, "total_gold": 0,
		"total_jp": 0, "total_encounters": 0, "elapsed_seconds": 0.0
	}
	var boss_data = {"name": "Test Boss", "exp_reward": 100, "max_hp": 400}
	_system.on_meta_boss_victory(boss_data)
	assert_lt(_system.meta_corruption_level, 3.0, "Corruption must decrease after meta-boss victory")


func test_on_meta_boss_defeat_increases_corruption() -> void:
	# Regression: losing to meta-boss must raise corruption significantly.
	_system.is_grinding = true
	_system.meta_corruption_level = 1.0
	# Set threshold high so collapse doesn't fire
	_system.corruption_threshold = 99.0
	var boss_data = {"name": "Test Boss", "max_hp": 400}
	_system.on_meta_boss_defeat(boss_data)
	assert_gt(_system.meta_corruption_level, 1.0, "Corruption must increase after meta-boss defeat")


func test_system_collapse_increments_collapse_count() -> void:
	# Regression: system collapse must track how many times it has fired.
	_system.collapse_count = 0
	_system.meta_corruption_level = 5.0
	_system._trigger_system_collapse()
	assert_eq(_system.collapse_count, 1, "collapse_count must increment on each collapse")


func test_system_collapse_lowers_threshold() -> void:
	# Regression: each collapse makes the next one easier to trigger.
	_system.corruption_threshold = 5.0
	_system._trigger_system_collapse()
	assert_lt(_system.corruption_threshold, 5.0, "corruption_threshold must decrease after collapse")
	assert_gte(_system.corruption_threshold, 2.0, "corruption_threshold must never go below 2.0")


func test_system_collapse_min_threshold_floor() -> void:
	# Regression: threshold must not go below 2.0 regardless of collapse count.
	_system.corruption_threshold = 2.0
	_system._trigger_system_collapse()
	assert_gte(_system.corruption_threshold, 2.0, "threshold floor is 2.0")


func test_apply_post_collapse_penalty_resets_corruption() -> void:
	# Regression: after a collapse boss fight, corruption must be zeroed.
	_system.meta_corruption_level = 5.5
	_system.max_efficiency = 10.0
	_system.efficiency_multiplier = 8.0
	_system.apply_post_collapse_penalty()
	assert_eq(_system.meta_corruption_level, 0.0, "Corruption must be 0 after post-collapse penalty")


func test_apply_post_collapse_penalty_debuffs_max_efficiency() -> void:
	# Regression: post-collapse must cap max_efficiency for next 10 battles.
	_system.max_efficiency = 10.0
	_system.efficiency_multiplier = 3.0
	_system.apply_post_collapse_penalty()
	assert_lt(_system.max_efficiency, 10.0, "max_efficiency must be reduced post-collapse")
	assert_eq(_system.post_collapse_debuff_battles, 10, "Debuff must last 10 battles")


func test_tick_post_collapse_debuff_counts_down() -> void:
	# Regression: each call to tick_post_collapse_debuff must decrement the counter.
	_system.post_collapse_debuff_battles = 3
	_system.tick_post_collapse_debuff()
	assert_eq(_system.post_collapse_debuff_battles, 2, "Debuff counter must decrement by 1")


func test_tick_post_collapse_debuff_restores_max_efficiency_at_zero() -> void:
	# Regression: when debuff expires, max_efficiency must return to 10.0.
	_system.max_efficiency = 5.0
	_system.post_collapse_debuff_battles = 1
	_system.tick_post_collapse_debuff()
	assert_eq(_system.post_collapse_debuff_battles, 0, "Debuff must reach 0")
	assert_eq(_system.max_efficiency, 10.0, "max_efficiency must be restored to 10.0 when debuff expires")


func test_tick_post_collapse_debuff_noop_when_inactive() -> void:
	# Regression: tick must be a no-op when no debuff is active (counter == 0).
	_system.post_collapse_debuff_battles = 0
	_system.max_efficiency = 7.0  # Intentionally odd value
	_system.tick_post_collapse_debuff()
	assert_eq(_system.post_collapse_debuff_battles, 0, "Counter must stay 0")
	assert_eq(_system.max_efficiency, 7.0, "max_efficiency must not change when debuff inactive")


func test_permadead_characters_initially_empty() -> void:
	# Regression: fresh system must have no permadead characters.
	assert_eq(_system.permadead_characters.size(), 0, "No permadead characters on fresh system")


func test_is_character_permadead_returns_false_for_live() -> void:
	# Regression: living characters must not be flagged permadead.
	assert_false(_system.is_character_permadead("TestChar0"),
		"Living character must not be permadead")


func test_permadeath_kills_lowest_hp_member() -> void:
	# Regression: _trigger_permadeath must kill the lowest-HP alive member, not all members.
	_system.is_grinding = true
	_system.permadeath_staking_enabled = true
	# Set different HP values
	_party[0].current_hp = 80
	_party[1].current_hp = 5  # Lowest HP — should die
	_party[2].current_hp = 60
	_party[3].current_hp = 70
	_system._trigger_permadeath()
	# Only the lowest-HP member should be dead
	assert_false(_party[1].is_alive, "Lowest HP member should be permanently killed")
	# At least some party members should remain alive
	var alive_count := 0
	for m in _party:
		if m.is_alive:
			alive_count += 1
	assert_gt(alive_count, 0, "At least some party members should survive a partial permadeath")


func test_is_character_permadead_after_trigger() -> void:
	# Regression: after permadeath trigger, victim must be flagged in permadead_characters.
	_system.is_grinding = true
	_system.permadeath_staking_enabled = true
	_party[0].current_hp = 1  # This one dies
	_party[1].current_hp = 80
	_party[2].current_hp = 80
	_party[3].current_hp = 80
	_system._trigger_permadeath()
	assert_true(_system.is_character_permadead(_party[0].combatant_name),
		"Permadead victim must appear in permadead_characters list")


func test_enable_permadeath_staking_boosts_growth_rate() -> void:
	# Regression: enabling permadeath staking must increase efficiency_growth_rate by 50%.
	_system.efficiency_growth_rate = 0.1
	_system.enable_permadeath_staking(true)
	assert_almost_eq(_system.efficiency_growth_rate, 0.15, 0.001,
		"Permadeath staking must set growth rate to 0.15 (50% boost)")


func test_enable_permadeath_staking_false_restores_growth_rate() -> void:
	# Regression: disabling permadeath staking must restore growth rate.
	_system.efficiency_growth_rate = 0.15
	_system.enable_permadeath_staking(false)
	assert_almost_eq(_system.efficiency_growth_rate, 0.1, 0.001,
		"Disabling permadeath staking must restore growth rate to 0.1")


func test_on_battle_victory_ticks_debuff() -> void:
	# Regression: on_battle_victory must call tick_post_collapse_debuff.
	_system.is_grinding = true
	_system.current_region_id = ""
	_system._grind_stats = {
		"start_time": 0.0, "total_exp": 0, "total_gold": 0,
		"total_jp": 0, "total_encounters": 0, "elapsed_seconds": 0.0
	}
	_system.post_collapse_debuff_battles = 5
	_system.on_battle_victory(100)
	assert_eq(_system.post_collapse_debuff_battles, 4, "on_battle_victory must tick debuff counter")
