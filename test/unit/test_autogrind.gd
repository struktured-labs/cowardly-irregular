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
