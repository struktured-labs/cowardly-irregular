extends GutTest

## Cadence #9 integration test for cowir-battle's night-scaling seam
## (BattleEnemySpawner.apply_night_scaling_to_stats, msg 2656). Verifies:
## 1. create_scaled_enemy_data routes through the canonical helper — so live
##    (BattleScene._spawn_from_data → spawn_from_data) and headless
##    (_resolve_headless_battle → Combatant.new) BOTH read the same scaled dict.
## 2. Behavior at identity multiplier: no stat changes (defensive default).
## 3. When the multiplier flips off 1.0, both stats-dict and top-level shapes
##    get scaled through NIGHT_SCALED_STATS (max_hp/attack/defense/magic).
## 4. speed and max_mp are EXCLUDED (per cowir-battle's design).

var _system: Node
var _saved_gc: Dictionary = {}


func before_each() -> void:
	_system = preload("res://src/autogrind/AutogrindSystem.gd").new()
	add_child_autofree(_system)
	_system._test_disable_persistence = true
	# Snapshot GameState.game_constants so mutation can't leak into other suites.
	if GameState and "game_constants" in GameState:
		_saved_gc = GameState.game_constants.duplicate(true)


func after_each() -> void:
	if GameState and "game_constants" in GameState:
		GameState.game_constants.clear()
		for k in _saved_gc:
			GameState.game_constants[k] = _saved_gc[k]


func test_identity_multiplier_leaves_stats_unchanged() -> void:
	# Default state: night_monster_multiplier absent/1.0 → helper no-ops.
	# create_scaled_enemy_data must still apply adaptation but night must not touch.
	_system.monster_adaptation_level = 0.0  # zero adaptation → identity too
	var base := {"stats": {"max_hp": 100, "attack": 20, "defense": 10, "magic": 5, "speed": 8, "max_mp": 30}}
	var scaled: Dictionary = _system.create_scaled_enemy_data(base)
	var s: Dictionary = scaled["stats"]
	assert_eq(s["max_hp"], 100, "identity night mult + zero adaptation → max_hp unchanged")
	assert_eq(s["attack"], 20, "identity night mult + zero adaptation → attack unchanged")
	assert_eq(s["speed"], 8, "speed must never scale (helper excludes it)")
	assert_eq(s["max_mp"], 30, "max_mp must never scale (helper excludes it)")


func test_night_multiplier_scales_nested_stats_dict() -> void:
	if GameState == null or not GameState.has_method("is_night"):
		pending("GameState.is_night() not present yet — cowir-main hasn't shipped the clock")
		return
	# Force is_night true (mock via game_constants override if available), set multiplier.
	# Since is_night's implementation is cowir-main's surface, we lean on the multiplier
	# check: with a real multiplier + is_night true (when it exists), stats scale.
	GameState.game_constants["night_monster_multiplier"] = 1.5
	_system.monster_adaptation_level = 0.0
	var base := {"stats": {"max_hp": 100, "attack": 20, "defense": 10, "magic": 5, "speed": 8, "max_mp": 30}}
	var scaled: Dictionary = _system.create_scaled_enemy_data(base)
	var s: Dictionary = scaled["stats"]
	if bool(GameState.is_night()):
		assert_eq(int(s["max_hp"]), 150, "night mult 1.5 → max_hp 100 → 150")
		assert_eq(int(s["attack"]), 30, "night mult 1.5 → attack 20 → 30")
		assert_eq(int(s["defense"]), 15, "night mult 1.5 → defense 10 → 15")
		assert_eq(int(s["magic"]), 8, "night mult 1.5 → magic 5 → int(7.5) = 8 (rounded)")
		assert_eq(int(s["speed"]), 8, "speed excluded from NIGHT_SCALED_STATS")
		assert_eq(int(s["max_mp"]), 30, "max_mp excluded from NIGHT_SCALED_STATS")
	else:
		# Daytime run — the helper defensively no-ops even with mult set. Still valid contract test.
		assert_eq(int(s["max_hp"]), 100, "day + night mult set → still no-op (is_night gate)")


func test_top_level_stats_also_scale() -> void:
	# Backward-compat shape: some autogrind paths supply top-level max_hp/attack/etc.
	# The night helper must reach those too so ALL enemy_data shapes are scaled uniformly.
	if GameState == null or not GameState.has_method("is_night"):
		pending("GameState.is_night() not present yet")
		return
	GameState.game_constants["night_monster_multiplier"] = 2.0
	_system.monster_adaptation_level = 0.0
	var base := {"max_hp": 50, "attack": 15, "defense": 8, "magic": 3}
	var scaled: Dictionary = _system.create_scaled_enemy_data(base)
	if bool(GameState.is_night()):
		assert_eq(int(scaled["max_hp"]), 100, "night mult 2.0 → top-level max_hp 50 → 100")
		assert_eq(int(scaled["attack"]), 30, "top-level attack 15 → 30")
	else:
		assert_eq(int(scaled["max_hp"]), 50, "day + mult set → no-op")


func test_night_scaling_stacks_with_adaptation_at_identity_stays_safe() -> void:
	# At identity multiplier + heavy adaptation, only adaptation applies — night is inert.
	# This proves the stacking axes are independent when night hasn't been activated.
	_system.monster_adaptation_level = 5.0  # +75% from adaptation alone
	var base := {"stats": {"max_hp": 100, "attack": 20, "defense": 10, "magic": 5}}
	var scaled: Dictionary = _system.create_scaled_enemy_data(base)
	var s: Dictionary = scaled["stats"]
	assert_eq(int(s["max_hp"]), 175, "adaptation alone (+75%) → max_hp 100 → 175")
	# Whatever the multiplier is: default identity → nothing extra applied on top.
	# When struktured rules on the stack, this test needs updating alongside.


func test_call_site_present_in_create_scaled_enemy_data() -> void:
	# Source-ratchet: a future refactor of create_scaled_enemy_data can't silently drop
	# the night-scaling call without failing this test. Same class of guard as the
	# picker-vs-evaluator sync ratchets.
	var src: String = load("res://src/autogrind/AutogrindSystem.gd").source_code
	var fn_start := src.find("func create_scaled_enemy_data")
	assert_true(fn_start >= 0)
	var fn_end := src.find("\nfunc ", fn_start + 20)
	var body := src.substr(fn_start, fn_end - fn_start)
	assert_true(body.contains("BattleEnemySpawner.apply_night_scaling_to_stats"),
		"create_scaled_enemy_data must route through BattleEnemySpawner.apply_night_scaling_to_stats — else live/headless divergence returns when the multiplier flips off 1.0 (msg 2655 parity design)")


func test_source_ratchet_uses_battle_enemy_spawner_const() -> void:
	# Ratchet the NIGHT_SCALED_STATS reference: if cowir-battle renames the const
	# on their side, this fails and we refactor together instead of silently
	# missing top-level scaling.
	var src: String = load("res://src/autogrind/AutogrindSystem.gd").source_code
	assert_true(src.contains("BattleEnemySpawner.NIGHT_SCALED_STATS"),
		"top-level enemy_data scaling must iterate BattleEnemySpawner.NIGHT_SCALED_STATS — kept in sync with the canonical exclusion list (max_mp + speed deliberately excluded)")
