extends GutTest

## Seven more of the nine LIVE-but-unnamed AutogrindSystem funcs found by the 2026-08-22 audit.
## Each has real src consumers — BattleManager reads the adaptation ladder, AutogrindMonitor the
## affinity, MenuScene and the grid editor the profile name — and none had a test naming them.
## Boundaries are asserted at the rungs (5/10/20) because that is where an off-by-one lives.

var _system


func before_each() -> void:
	_system = preload("res://src/autogrind/AutogrindSystem.gd").new()
	add_child_autofree(_system)
	_system._test_disable_persistence = true


func test_meta_boss_never_spawns_while_disabled() -> void:
	_system.meta_bosses_enabled = false
	_system.meta_boss_spawn_chance = 1.0
	assert_false(_system.should_spawn_meta_boss(),
		"the disable flag must outrank the spawn chance entirely")


func test_meta_boss_spawns_at_certainty_when_enabled() -> void:
	# ARM+. randf() is [0,1) so chance 1.0 is deterministic — no flake, and without this
	# the disabled case above would pass on a function that always returns false.
	_system.meta_bosses_enabled = true
	_system.meta_boss_spawn_chance = 1.0
	assert_true(_system.should_spawn_meta_boss(), "an enabled spawn at chance 1.0 must fire")


func test_meta_boss_never_spawns_at_zero_chance() -> void:
	_system.meta_bosses_enabled = true
	_system.meta_boss_spawn_chance = 0.0
	assert_false(_system.should_spawn_meta_boss(), "chance 0.0 must never fire — randf() is >= 0")


func test_adaptation_is_zero_for_an_unvisited_region() -> void:
	assert_eq(_system.get_adaptation_level_for_region("nowhere"), 0,
		"a region with no learned pattern is not adapted")


func test_adaptation_ladder_at_its_boundaries() -> void:
	## The rungs are >=5, >=10, >=20; one below each must stay on the lower rung.
	for pair in [[4, 0], [5, 1], [9, 1], [10, 2], [19, 2], [20, 3], [100, 3]]:
		var battles: int = int(pair[0])
		var expected: int = int(pair[1])
		_system.learned_patterns["r"] = {"battles_analyzed": battles}
		assert_eq(_system.get_adaptation_level_for_region("r"), expected,
			"%d battles analysed must read as adaptation level %d" % [battles, expected])


func test_character_exp_accumulates_per_name() -> void:
	_system.track_character_exp("Fighter", 100)
	_system.track_character_exp("Fighter", 50)
	_system.track_character_exp("Mage", 30)
	assert_eq(int(_system.per_character_exp.get("Fighter", 0)), 150,
		"repeat gains for one character must sum, not overwrite")
	assert_eq(int(_system.per_character_exp.get("Mage", 0)), 30,
		"a second character must be tracked separately")


func test_automation_affinity_rises_toward_automation() -> void:
	var before: float = _system.get_automation_affinity()
	for i in range(50):
		_system.update_automation_affinity("autogrind")
	assert_gt(_system.get_automation_affinity(), before,
		"repeated autogrind signals must raise the affinity")


func test_automation_affinity_falls_back_toward_manual() -> void:
	# ARM+ for the direction: proves the EMA moves both ways, not just up.
	for i in range(200):
		_system.update_automation_affinity("autogrind")
	var high: float = _system.get_automation_affinity()
	for i in range(200):
		_system.update_automation_affinity("manual")
	assert_lt(_system.get_automation_affinity(), high,
		"manual play must pull the affinity back down")


func test_automation_affinity_stays_in_its_declared_range() -> void:
	for i in range(500):
		_system.update_automation_affinity("autogrind")
	var v: float = _system.get_automation_affinity()
	assert_true(v >= 0.0 and v <= 1.0,
		"affinity is documented 0.0-1.0; an EMA toward 1.0 must never overshoot")


func test_an_unknown_signal_does_not_raise_affinity() -> void:
	## The match has no default arm, so an unrecognised signal means s = 0.0 — pull DOWN.
	for i in range(50):
		_system.update_automation_affinity("autogrind")
	var high: float = _system.get_automation_affinity()
	_system.update_automation_affinity("not_a_real_signal")
	assert_lt(_system.get_automation_affinity(), high,
		"an unrecognised signal must not be treated as automation")


func test_csi_decays_with_time_away() -> void:
	_system._region_csi["cave"] = 1.0
	_system.decay_all_csi(10.0)
	assert_lt(float(_system._region_csi["cave"]), 1.0, "time away must decay CSI")


func test_csi_decay_clamps_at_zero() -> void:
	_system._region_csi["cave"] = 0.05
	_system.decay_all_csi(100000.0)
	assert_eq(float(_system._region_csi["cave"]), 0.0,
		"a long absence must floor CSI at 0.0, never drive it negative")


func test_csi_does_not_decay_without_elapsed_time() -> void:
	# ARM+. Without this, a decay that always zeroed the map would pass both tests above.
	_system._region_csi["cave"] = 1.0
	_system.decay_all_csi(0.0)
	assert_eq(float(_system._region_csi["cave"]), 1.0, "zero hours elapsed must change nothing")


func test_active_profile_name_reads_the_active_index() -> void:
	_system.autogrind_profiles = {
		"active": 1,
		"profiles": [{"name": "First", "rules": []}, {"name": "Second", "rules": []}]
	}
	assert_eq(_system.get_active_autogrind_profile_name(), "Second",
		"the name must follow the active index, not the first profile")


func test_active_profile_name_falls_back_when_the_index_is_stale() -> void:
	_system.autogrind_profiles = {"active": 9, "profiles": [{"name": "First", "rules": []}]}
	assert_eq(_system.get_active_autogrind_profile_name(), "Default",
		"an out-of-range active index must fall back, not crash or read out of bounds")
