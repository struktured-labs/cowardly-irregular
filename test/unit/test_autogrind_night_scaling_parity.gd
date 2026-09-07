extends GutTest

## Cadence #9 integration test for cowir-battle's night-scaling seam
## (BattleEnemySpawner.apply_night_scaling_to_stats). Verifies:
## 1. create_scaled_enemy_data routes through the canonical helper — so live
##    (BattleScene._spawn_from_data → spawn_from_data) and headless
##    (_resolve_headless_battle → Combatant.new) BOTH read the same scaled dict.
## 2. Behavior at identity multiplier: no stat changes (defensive default).
## 3. When the multiplier flips off 1.0, both stats-dict and top-level shapes
##    get scaled through NIGHT_SCALED_STATS.
## 4. speed and max_mp are EXCLUDED (per cowir-battle's design).
## 5. Cadence #12 (v3.33.197): clock is now live. day_phase is forced into
##    known bands so both day (no-op) and night (scaled) branches are asserted
##    every run — previously each test only exercised whichever branch happened
##    to be active at test time.

const DAY_PHASE_DAY: float = 0.30
const DAY_PHASE_NIGHT: float = 0.70

var _system: Node
var _saved_gc: Dictionary = {}
var _saved_day_phase: float = 0.0
var _saved_paused: bool = false


func before_each() -> void:
	_system = preload("res://src/autogrind/AutogrindSystem.gd").new()
	add_child_autofree(_system)
	_system._test_disable_persistence = true
	# Snapshot GameState.game_constants so mutation can't leak into other suites.
	if GameState and "game_constants" in GameState:
		_saved_gc = GameState.game_constants.duplicate(true)
	# Freeze day_phase across tests — pause the clock so tests that don't touch
	# it are still isolated from real-time drift.
	if GameState:
		if "day_phase" in GameState:
			_saved_day_phase = GameState.day_phase
		if "playtime_paused" in GameState:
			_saved_paused = GameState.playtime_paused
			GameState.playtime_paused = true


func after_each() -> void:
	if GameState and "game_constants" in GameState:
		GameState.game_constants.clear()
		for k in _saved_gc:
			GameState.game_constants[k] = _saved_gc[k]
	if GameState:
		if "day_phase" in GameState:
			GameState.day_phase = _saved_day_phase
		if "playtime_paused" in GameState:
			GameState.playtime_paused = _saved_paused


func _force_night() -> bool:
	# Returns true iff we could put GameState into the "night" band and it stuck.
	# Skips assertions gracefully if the autoload/API isn't present in a stripped env.
	if GameState == null or not GameState.has_method("is_night"):
		return false
	if not ("day_phase" in GameState):
		return false
	GameState.day_phase = DAY_PHASE_NIGHT
	return bool(GameState.is_night())


func _force_day() -> bool:
	if GameState == null or not GameState.has_method("is_night"):
		return false
	if not ("day_phase" in GameState):
		return false
	GameState.day_phase = DAY_PHASE_DAY
	return not bool(GameState.is_night())


func test_identity_multiplier_leaves_stats_unchanged() -> void:
	# Default state: night_monster_multiplier absent/1.0 → helper no-ops
	# regardless of day/night band. create_scaled_enemy_data must still apply
	# adaptation but night must not touch.
	_system.monster_adaptation_level = 0.0
	var base := {"stats": {"max_hp": 100, "attack": 20, "defense": 10, "magic": 5, "speed": 8, "max_mp": 30}}
	var scaled: Dictionary = _system.create_scaled_enemy_data(base)
	var s: Dictionary = scaled["stats"]
	assert_eq(s["max_hp"], 100, "identity night mult + zero adaptation → max_hp unchanged")
	assert_eq(s["attack"], 20, "identity night mult + zero adaptation → attack unchanged")
	assert_eq(s["speed"], 8, "speed must never scale (helper excludes it)")
	assert_eq(s["max_mp"], 30, "max_mp must never scale (helper excludes it)")


func test_night_band_scales_nested_stats_dict() -> void:
	if not _force_night():
		pending("GameState clock unavailable in this env")
		return
	GameState.game_constants["night_monster_multiplier"] = 1.5
	_system.monster_adaptation_level = 0.0
	var base := {"stats": {"max_hp": 100, "attack": 20, "defense": 10, "magic": 5, "speed": 8, "max_mp": 30}}
	var scaled: Dictionary = _system.create_scaled_enemy_data(base)
	var s: Dictionary = scaled["stats"]
	assert_eq(int(s["max_hp"]), 150, "night mult 1.5 → max_hp 100 → 150 (nested shape)")
	assert_eq(int(s["attack"]), 30, "night mult 1.5 → attack 20 → 30")
	assert_eq(int(s["defense"]), 15, "night mult 1.5 → defense 10 → 15")
	assert_eq(int(s["magic"]), 8, "night mult 1.5 → magic 5 → helper rounds 7.5 to 8")
	assert_eq(int(s["speed"]), 8, "speed excluded from NIGHT_SCALED_STATS")
	assert_eq(int(s["max_mp"]), 30, "max_mp excluded from NIGHT_SCALED_STATS")


func test_day_band_ignores_multiplier_nested_stats() -> void:
	# Complementary branch to the night test above — same mult, day band,
	# no scaling. Proves the is_night() gate is honored, not just the multiplier.
	if not _force_day():
		pending("GameState clock unavailable in this env")
		return
	GameState.game_constants["night_monster_multiplier"] = 1.5
	_system.monster_adaptation_level = 0.0
	var base := {"stats": {"max_hp": 100, "attack": 20, "defense": 10, "magic": 5, "speed": 8}}
	var scaled: Dictionary = _system.create_scaled_enemy_data(base)
	var s: Dictionary = scaled["stats"]
	assert_eq(int(s["max_hp"]), 100, "day band + night mult set → no-op (is_night() gate closes helper)")
	assert_eq(int(s["attack"]), 20, "day band + night mult set → attack no-op")


func test_night_band_scales_top_level_stats() -> void:
	if not _force_night():
		pending("GameState clock unavailable in this env")
		return
	GameState.game_constants["night_monster_multiplier"] = 2.0
	_system.monster_adaptation_level = 0.0
	var base := {"max_hp": 50, "attack": 15, "defense": 8, "magic": 3}
	var scaled: Dictionary = _system.create_scaled_enemy_data(base)
	assert_eq(int(scaled["max_hp"]), 100, "night mult 2.0 → top-level max_hp 50 → 100")
	assert_eq(int(scaled["attack"]), 30, "night mult 2.0 → top-level attack 15 → 30")


func test_day_band_ignores_multiplier_top_level_stats() -> void:
	if not _force_day():
		pending("GameState clock unavailable in this env")
		return
	GameState.game_constants["night_monster_multiplier"] = 2.0
	_system.monster_adaptation_level = 0.0
	var base := {"max_hp": 50, "attack": 15, "defense": 8, "magic": 3}
	var scaled: Dictionary = _system.create_scaled_enemy_data(base)
	assert_eq(int(scaled["max_hp"]), 50, "day band + night mult set → top-level max_hp no-op")
	assert_eq(int(scaled["attack"]), 15, "day band + night mult set → top-level attack no-op")


func test_night_scaling_stacks_with_adaptation_at_identity_stays_safe() -> void:
	# At identity multiplier + heavy adaptation, only adaptation applies.
	# Proves the two axes are independent when night hasn't been activated.
	_system.monster_adaptation_level = 5.0  # +75% from adaptation alone
	var base := {"stats": {"max_hp": 100, "attack": 20, "defense": 10, "magic": 5}}
	var scaled: Dictionary = _system.create_scaled_enemy_data(base)
	var s: Dictionary = scaled["stats"]
	assert_eq(int(s["max_hp"]), 175, "adaptation alone (+75%) → max_hp 100 → 175")


func test_call_site_present_in_create_scaled_enemy_data() -> void:
	var src: String = load("res://src/autogrind/AutogrindSystem.gd").source_code
	var fn_start := src.find("func create_scaled_enemy_data")
	assert_true(fn_start >= 0)
	var fn_end := src.find("\nfunc ", fn_start + 20)
	var body := src.substr(fn_start, fn_end - fn_start)
	assert_true(body.contains("BattleEnemySpawner.apply_night_scaling_to_stats"),
		"create_scaled_enemy_data must route through BattleEnemySpawner.apply_night_scaling_to_stats — else live/headless divergence returns when the multiplier flips off 1.0 (msg 2655 parity design)")


func test_source_ratchet_uses_battle_enemy_spawner_const() -> void:
	var src: String = load("res://src/autogrind/AutogrindSystem.gd").source_code
	assert_true(src.contains("BattleEnemySpawner.NIGHT_SCALED_STATS"),
		"top-level enemy_data scaling must iterate BattleEnemySpawner.NIGHT_SCALED_STATS — kept in sync with the canonical exclusion list (max_mp + speed deliberately excluded)")
