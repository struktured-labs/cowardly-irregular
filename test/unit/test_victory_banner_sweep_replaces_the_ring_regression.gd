extends GutTest

## Room-to-breathe HUD pass (struktured 2026-10-03): "the victory Circle with victory text in the
## middle is also amateur imho — we need VISUALS". VictoryOverlay._spawn_ring's expanding bordered
## circle (corner_radius_all(90)) is replaced by _spawn_sweep_band: a tinted band that sweeps the
## full screen width through the impact point, settling the title into the SAME dock position the
## unmerged results-card branch (origin/lane/the-results-card-arrives-as-one-panel) depends on.

const OVERLAY := "res://src/battle/VictoryOverlay.gd"


func _src() -> String:
	return FileAccess.get_file_as_string(OVERLAY)


func test_the_old_ring_shape_is_gone() -> void:
	var src := _src()
	assert_false(src.contains("func _spawn_ring("), "the old ring-building function must be removed")
	assert_false(src.contains("corner_radius_all(90)"), "no circular/ring StyleBoxFlat should remain")


func test_a_sweeping_band_replaces_it() -> void:
	var src := _src()
	assert_true(src.contains("func _spawn_sweep_band("), "a band-sweep function must exist")
	assert_true(src.contains("_spawn_sweep_band(at, tint, grade)"),
		"_spawn_impact must call the new sweep instead of the old ring loop")
	assert_false(src.contains("for i in range(int(GRADE_RINGS[grade])):"),
		"_spawn_impact must no longer loop GRADE_RINGS to build rings")


func test_impact_signature_is_unchanged_for_the_slam_call_site() -> void:
	# _build_slam must still call _spawn_impact(impact_at, grade, tint) exactly as before —
	# the title punch-in/dock timing this call anchors must be untouched.
	var src := _src()
	assert_true(src.contains("_spawn_impact(impact_at, grade, tint)"),
		"the _build_slam call site into _spawn_impact must keep its original signature")


func test_title_dock_contract_is_untouched() -> void:
	# The unmerged results-card branch depends on this EXACT contract: _title_rest,
	# _title_clear_at, and the docked Vector2 math inside _build_slam. If any of these
	# literals/identifiers disappear, that branch will fail to fold later.
	var src := _src()
	assert_true(src.contains("_title_rest = Rect2(center, title.size)"), "title rest rect math must survive")
	assert_true(src.contains("_title_clear_at = 0.40 + float(GRADE_HOLD[grade]) + 0.3"), "title clear-at timing must survive")
	assert_true(src.contains("var docked := Vector2(center.x, 28.0)"), "the docked position math must survive untouched")


func test_sweep_band_nodes_free_themselves_through_a_weakref() -> void:
	# Same lesson as test_a_victory_snap_never_holds_a_node_that_frees_itself.gd: any
	# self-freeing node's snap must hold a WeakRef, not the node directly.
	var src := _src()
	assert_true(src.contains("weakref(band)"))
	assert_true(src.contains("weakref(band2)"))


func test_sweep_band_respects_engine_time_scale_like_the_rest_of_the_file() -> void:
	# Every tween in this file is built via _track(create_tween()), which rides the SceneTree
	# process callback (already Engine.time_scale-scaled) — no raw OS.get_ticks / manual delta
	# math that would bypass that scaling. Pin that the new code follows the same idiom.
	var src := _src()
	var band_fn_start := src.find("func _spawn_sweep_band(")
	assert_gt(band_fn_start, -1, "CONTROL: the sweep function must exist")
	var band_fn_end := src.find("\n\n\n", band_fn_start)
	if band_fn_end == -1:
		band_fn_end = src.length()
	var body := src.substr(band_fn_start, band_fn_end - band_fn_start)
	assert_true(body.contains("_track(create_tween())"),
		"the sweep must use the file's standard _track(create_tween()) idiom")
	assert_false(body.contains("OS.get_ticks_msec") or body.contains("get_process_delta_time() *"),
		"the sweep must not hand-roll timing that could bypass Engine.time_scale")


# ===========================================================================
# MUTATION: reverting to the old ring call must red the "ring is gone" check
# ===========================================================================

func test_MUTATION_a_reverted_ring_call_would_red_the_gone_check() -> void:
	# Simulates what test_the_old_ring_shape_is_gone would see if _spawn_impact were
	# reverted to loop GRADE_RINGS and call _spawn_ring again — proving that check is not
	# vacuously true no matter what the file contains.
	var reverted_src := "func _spawn_ring(at, tint, delay, grade):\n\tvar ring := Panel.new()\n" \
		+ "\tstyle.set_corner_radius_all(90)\n" \
		+ "func _spawn_impact(at, grade, tint):\n\tfor i in range(int(GRADE_RINGS[grade])):\n\t\t_spawn_ring(at, tint, 0.06 * i, grade)\n"
	assert_true(reverted_src.contains("func _spawn_ring("), "CONTROL: the mutated text must contain the thing the real check forbids")
	assert_true(reverted_src.contains("corner_radius_all(90)"), "CONTROL: the mutated text must contain the ring stylebox call")
	# The real assertions, run against the MUTATED text instead of the real file:
	var ring_gone: bool = not reverted_src.contains("func _spawn_ring(")
	var corner_gone: bool = not reverted_src.contains("corner_radius_all(90)")
	assert_false(ring_gone, "a reverted ring implementation must fail the 'ring is gone' assertion")
	assert_false(corner_gone, "a reverted ring implementation must fail the 'no circular stylebox' assertion")
