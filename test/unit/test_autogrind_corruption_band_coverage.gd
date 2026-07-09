extends GutTest

## Regression coverage: the task-#8 corruption-band warning must fire on EVERY
## corruption increase, not just the efficiency path. Pre-fix, on_meta_boss_defeat
## (+1.5) and region-crack-lvl-3 (+0.5) bumped meta_corruption_level without the
## band check, so a meta-boss loss could vault corruption past warning+danger with
## no toast until full collapse. All increases now route through _add_meta_corruption.

var _system: Node
var _fired: Array = []


func before_each() -> void:
	_system = preload("res://src/autogrind/AutogrindSystem.gd").new()
	add_child_autofree(_system)
	_system.corruption_threshold_crossed.connect(_capture)
	_fired.clear()
	_system.meta_corruption_level = 0.0
	_system._corruption_bands_crossed.clear()


func _capture(band: String, level: float) -> void:
	_fired.append({"band": band, "level": level})


func test_add_meta_corruption_fires_band() -> void:
	_system.meta_corruption_level = 2.9
	_system._add_meta_corruption(0.2)  # → 3.1, crosses warning (3.0)
	var bands := []
	for f in _fired:
		bands.append(f["band"])
	assert_true("warning" in bands, "crossing 3.0 via the helper must fire the warning band")


func test_add_meta_corruption_ignores_nonpositive() -> void:
	_system.meta_corruption_level = 3.5
	_system._add_meta_corruption(0.0)
	_system._add_meta_corruption(-1.0)
	assert_eq(_system.meta_corruption_level, 3.5,
		"non-positive amounts must be a no-op (decreases have their own path, no band to cross upward)")
	assert_eq(_fired.size(), 0, "no band should fire on a no-op")


func test_meta_boss_defeat_crossing_band_warns() -> void:
	# THE regression: a meta-boss loss (+1.5) that vaults corruption past a band
	# must warn, not silently jump to near-collapse.
	_system.meta_corruption_level = 2.8
	_system.on_meta_boss_defeat({"name": "Test Meta-Boss"})
	# 2.8 + 1.5 = 4.3 → crosses BOTH warning (3.0) and danger (4.0)
	var bands := []
	for f in _fired:
		bands.append(f["band"])
	assert_true("warning" in bands,
		"meta-boss defeat vaulting past 3.0 must fire warning (was silent pre-fix)")
	assert_true("danger" in bands,
		"meta-boss defeat vaulting past 4.0 must fire danger (was silent pre-fix)")
	assert_almost_eq(_system.meta_corruption_level, 4.3, 0.001,
		"corruption still rises the same +1.5 — the fix only ADDS the warning")


func test_region_crack_level3_crossing_band_warns() -> void:
	# region-crack level 3 adds +0.5; if that crosses danger it must warn.
	_system.current_region_id = "test_region"
	_system.meta_corruption_level = 3.7
	_system.region_crack_levels["test_region"] = 3
	_system._apply_meta_adaptation(3)  # the crack-adaptation path that does +0.5
	# 3.7 + 0.5 = 4.2 → crosses danger (4.0)
	var bands := []
	for f in _fired:
		bands.append(f["band"])
	assert_true("danger" in bands,
		"region-crack-3 corruption bump crossing 4.0 must fire danger (was silent pre-fix)")


func test_source_ratchet_no_bare_corruption_increment() -> void:
	# Structural guard: the ONLY `meta_corruption_level +=` in the file must be
	# inside _add_meta_corruption. A future corruption source that does a bare
	# += would re-open the silent-band gap — this test fails if one appears.
	var src: String = load("res://src/autogrind/AutogrindSystem.gd").source_code
	var count := 0
	var idx := src.find("meta_corruption_level +=")
	while idx != -1:
		count += 1
		idx = src.find("meta_corruption_level +=", idx + 1)
	assert_eq(count, 1,
		"exactly ONE `meta_corruption_level +=` must exist (inside _add_meta_corruption); a new bare increment re-opens the silent-band gap — route it through the helper instead")


func test_helper_defined_and_efficiency_path_uses_it() -> void:
	var src: String = load("res://src/autogrind/AutogrindSystem.gd").source_code
	assert_true(src.contains("func _add_meta_corruption"),
		"_add_meta_corruption helper must exist")
	# _increase_efficiency must call the helper, not a bare += (it was the
	# original band-check site; regressing it to bare += would lose the check).
	var fn_start := src.find("func _increase_efficiency")
	assert_true(fn_start >= 0)
	var fn_end := src.find("\nfunc ", fn_start + 20)
	var body := src.substr(fn_start, fn_end - fn_start)
	assert_true(body.contains("_add_meta_corruption"),
		"_increase_efficiency must route corruption through the helper")
	assert_false(body.contains("meta_corruption_level +="),
		"_increase_efficiency must NOT do a bare corruption increment")
