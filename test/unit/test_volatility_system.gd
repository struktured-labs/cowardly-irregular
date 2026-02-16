extends GutTest

## Tests for VolatilitySystem and Speculator job integration
## Verifies volatility bands, variance ranges, tail events, and data integrity

var _jobs: Dictionary
var _abilities: Dictionary
var _passives: Dictionary


func _load_json(path: String) -> Variant:
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		return null
	var json = JSON.new()
	var error = json.parse(file.get_as_text())
	file.close()
	if error != OK:
		return null
	return json.data


func before_all() -> void:
	_jobs = _load_json("res://data/jobs.json")
	if _jobs == null:
		_jobs = {}
	_abilities = _load_json("res://data/abilities.json")
	if _abilities == null:
		_abilities = {}
	_passives = _load_json("res://data/passives.json")
	if _passives == null:
		_passives = {}


## ---- VolatilitySystem Unit Tests ----

func test_volatility_system_creation() -> void:
	var vol = VolatilitySystem.new()
	assert_not_null(vol, "VolatilitySystem should be instantiable")
	assert_eq(vol.global_band, 0, "Default band should be Stable (0)")


func test_volatility_reset_battle() -> void:
	var vol = VolatilitySystem.new()
	vol.global_band = 3
	vol.set_local(self, 2.0)
	vol.reset_battle()
	assert_eq(vol.global_band, 0, "Band should reset to Stable after reset_battle")
	assert_eq(vol.local_volatility.size(), 0, "Local volatility should be cleared")


func test_volatility_shift_band() -> void:
	var vol = VolatilitySystem.new()
	vol.shift_band(1)
	assert_eq(vol.global_band, 1, "Band should shift up to Shifting")
	vol.shift_band(2)
	assert_eq(vol.global_band, 3, "Band should shift up to Fractured")
	vol.shift_band(1)
	assert_eq(vol.global_band, 3, "Band should clamp at 3 (Fractured)")
	vol.shift_band(-5)
	assert_eq(vol.global_band, 0, "Band should clamp at 0 (Stable)")


func test_volatility_band_names() -> void:
	var vol = VolatilitySystem.new()
	assert_eq(vol.get_band_name(), "Stable", "Band 0 should be Stable")
	vol.global_band = 1
	assert_eq(vol.get_band_name(), "Shifting", "Band 1 should be Shifting")
	vol.global_band = 2
	assert_eq(vol.get_band_name(), "Unstable", "Band 2 should be Unstable")
	vol.global_band = 3
	assert_eq(vol.get_band_name(), "Fractured", "Band 3 should be Fractured")


func test_variance_range_stable() -> void:
	var vol = VolatilitySystem.new()
	vol.global_band = 0
	var vrange = vol.get_variance_range(null)
	assert_almost_eq(vrange.x, 0.85, 0.01, "Stable min variance should be ~0.85")
	assert_almost_eq(vrange.y, 1.15, 0.01, "Stable max variance should be ~1.15")


func test_variance_range_fractured() -> void:
	var vol = VolatilitySystem.new()
	vol.global_band = 3
	var vrange = vol.get_variance_range(null)
	assert_almost_eq(vrange.x, 0.40, 0.01, "Fractured min variance should be ~0.40")
	assert_almost_eq(vrange.y, 1.60, 0.01, "Fractured max variance should be ~1.60")


func test_local_volatility_default() -> void:
	var vol = VolatilitySystem.new()
	assert_eq(vol.get_local(null), 1.0, "Default local volatility should be 1.0")


func test_local_volatility_set() -> void:
	var vol = VolatilitySystem.new()
	vol.set_local(self, 2.0)
	assert_eq(vol.get_local(self), 2.0, "Local volatility should be settable")


func test_local_volatility_widens_variance() -> void:
	var vol = VolatilitySystem.new()
	vol.global_band = 0
	vol.set_local(self, 2.0)
	var vrange = vol.get_variance_range(self)
	# With local=2.0, variance width = 0.15 * 2.0 = 0.30
	assert_lt(vrange.x, 0.75, "High local volatility should widen min variance")
	assert_gt(vrange.y, 1.25, "High local volatility should widen max variance")


func test_local_volatility_narrows_variance() -> void:
	var vol = VolatilitySystem.new()
	vol.global_band = 0
	vol.set_local(self, 0.5)
	var vrange = vol.get_variance_range(self)
	# With local=0.5, variance width = 0.15 * 0.5 = 0.075
	assert_gt(vrange.x, 0.90, "Low local volatility should narrow min variance")
	assert_lt(vrange.y, 1.10, "Low local volatility should narrow max variance")


func test_ctb_jitter_scales_with_band() -> void:
	var vol = VolatilitySystem.new()
	vol.global_band = 0
	assert_eq(vol.get_ctb_jitter(), 1.0, "Stable jitter should be 1.0")
	vol.global_band = 1
	assert_eq(vol.get_ctb_jitter(), 2.0, "Shifting jitter should be 2.0")
	vol.global_band = 2
	assert_eq(vol.get_ctb_jitter(), 4.0, "Unstable jitter should be 4.0")
	vol.global_band = 3
	assert_eq(vol.get_ctb_jitter(), 8.0, "Fractured jitter should be 8.0")


func test_tail_event_probability_increases_with_band() -> void:
	var vol = VolatilitySystem.new()
	var pct_0 = vol.get_tail_event_pct()
	vol.global_band = 3
	var pct_3 = vol.get_tail_event_pct()
	assert_gt(pct_3, pct_0, "Fractured tail event % should be higher than Stable")


## ---- Speculator Job Data Integrity ----

func test_speculator_job_exists() -> void:
	assert_has(_jobs, "speculator", "Speculator job should exist in jobs.json")


func test_speculator_job_type() -> void:
	var spec = _jobs.get("speculator", {})
	assert_eq(spec.get("type", -1), 1, "Speculator should be type 1 (Advanced)")


func test_speculator_abilities_exist() -> void:
	var spec = _jobs.get("speculator", {})
	var spec_abilities = spec.get("abilities", [])
	assert_eq(spec_abilities.size(), 6, "Speculator should have 6 abilities")
	for ability_id in spec_abilities:
		assert_has(_abilities, ability_id, "Ability '%s' should exist in abilities.json" % ability_id)


func test_speculator_passive_exists() -> void:
	var spec = _jobs.get("speculator", {})
	var spec_passives = spec.get("passive_abilities", [])
	assert_eq(spec_passives.size(), 1, "Speculator should have 1 passive")
	assert_eq(spec_passives[0], "market_sense", "Speculator passive should be market_sense")
	assert_has(_passives, "market_sense", "market_sense should exist in passives.json")


func test_speculator_stat_modifiers() -> void:
	var spec = _jobs.get("speculator", {})
	var stats = spec.get("stat_modifiers", {})
	assert_eq(stats.get("max_hp", 0), 95, "Speculator max_hp should be 95")
	assert_eq(stats.get("speed", 0), 14, "Speculator speed should be 14")
	assert_eq(stats.get("magic", 0), 14, "Speculator magic should be 14")


func test_speculator_visual_config() -> void:
	var spec = _jobs.get("speculator", {})
	var visual = spec.get("visual", {})
	assert_eq(visual.get("sprite_type", ""), "tech", "Speculator sprite_type should be tech")
	assert_eq(visual.get("headgear", ""), "glasses", "Speculator headgear should be glasses")


## ---- Speculator Ability Data ----

func test_leverage_position_ability() -> void:
	var ab = _abilities.get("leverage_position", {})
	assert_eq(ab.get("type", ""), "support", "leverage_position should be support type")
	assert_eq(ab.get("effect", ""), "volatility_up_self", "leverage_position effect should be volatility_up_self")
	assert_eq(ab.get("mp_cost", 0), 10, "leverage_position MP cost should be 10")
	assert_gt(ab.get("recoil_pct", 0.0), 0.0, "leverage_position should have recoil")


func test_press_the_edge_ability() -> void:
	var ab = _abilities.get("press_the_edge", {})
	assert_eq(ab.get("effect", ""), "press_the_edge", "press_the_edge effect should match")
	assert_eq(ab.get("mp_cost", 0), 15, "press_the_edge MP cost should be 15")


func test_circuit_breaker_ability() -> void:
	var ab = _abilities.get("circuit_breaker", {})
	assert_eq(ab.get("effect", ""), "circuit_breaker", "circuit_breaker effect should match")
	assert_eq(ab.get("mp_cost", 0), 10, "circuit_breaker MP cost should be 10")


func test_forecast_ability() -> void:
	var ab = _abilities.get("forecast", {})
	assert_eq(ab.get("effect", ""), "forecast", "forecast effect should match")
	assert_eq(ab.get("mp_cost", 0), 5, "forecast should be cheap at 5 MP")


func test_hedge_position_ability() -> void:
	var ab = _abilities.get("hedge_position", {})
	assert_eq(ab.get("effect", ""), "volatility_down", "hedge_position effect should be volatility_down")
	assert_eq(ab.get("target_type", ""), "single_ally", "hedge_position should target single ally")


func test_overexpose_ability() -> void:
	var ab = _abilities.get("overexpose", {})
	assert_eq(ab.get("effect", ""), "volatility_up_enemy", "overexpose effect should be volatility_up_enemy")
	assert_eq(ab.get("target_type", ""), "single_enemy", "overexpose should target single enemy")
