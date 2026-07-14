extends GutTest

## tick 208: BattleResultsDisplay floating damage / heal / miss
## popups now stagger vertically when multiple spawn at the same
## target. Pre-fix every popup spawned at `pos + Vector2(±10, -30)`
## — the ±10 random x-offset wasn't enough to separate multi-hit
## attack popups (4-hit combos, multi-strike abilities, status
## tick storms), and they piled into one unreadable cluster.
##
## Fix: count live DamageNumber children within STAGGER_RADIUS
## of the spawn pos, then push the new popup up by count *
## STAGGER_STEP. The radius (40px) self-regulates: once a stacked
## popup is far enough above the sprite, it falls off the counter,
## so the stack stabilizes at a few visible levels.
##
## Same insight as tick 205's Toast stacking but in a different
## coordinate system (global sprite position vs viewport top).

const BATTLE_RESULTS := "res://src/battle/BattleResultsDisplay.gd"
const DAMAGE_NUMBER := "res://src/ui/DamageNumber.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


# ── Constants present ──────────────────────────────────────────────────

func test_stagger_step_constant_defined() -> void:
	var src := _read(BATTLE_RESULTS)
	assert_true(src.contains("const STAGGER_STEP := 18.0"),
		"STAGGER_STEP must be 18.0 — readable separation without flying off-screen")


func test_stagger_radius_constant_defined() -> void:
	var src := _read(BATTLE_RESULTS)
	assert_true(src.contains("const STAGGER_RADIUS_SQUARED := 40.0 * 40.0"),
		"STAGGER_RADIUS_SQUARED must be (40px)² — squared so we can avoid sqrt in the hot loop")


# ── _count_recent_popups_near helper ──────────────────────────────────

func test_count_helper_present() -> void:
	var src := _read(BATTLE_RESULTS)
	assert_true(src.contains("func _count_recent_popups_near(pos: Vector2) -> int:"),
		"_count_recent_popups_near helper must exist")


func test_count_helper_filters_to_damage_numbers() -> void:
	# Pin: only DamageNumber instances count toward the stack. Other
	# Node2D effects (heal glow, particles) shouldn't bump the offset.
	var src := _read(BATTLE_RESULTS)
	var fn_idx: int = src.find("func _count_recent_popups_near")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > -1 else src.substr(fn_idx)
	assert_true(body.contains("child is DamageNumber"),
		"helper must filter to DamageNumber children only")
	assert_true(body.contains("is_instance_valid(child)"),
		"helper must check is_instance_valid (defensive against queued_free children)")


func test_count_helper_uses_squared_distance() -> void:
	# Pin: distance_squared_to + comparison against STAGGER_RADIUS_SQUARED
	# avoids the sqrt — minor perf win on the hot path.
	var src := _read(BATTLE_RESULTS)
	var fn_idx: int = src.find("func _count_recent_popups_near")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > -1 else src.substr(fn_idx)
	assert_true(body.contains("child.position.distance_squared_to(pos) < STAGGER_RADIUS_SQUARED"),
		"helper must use distance_squared_to vs STAGGER_RADIUS_SQUARED (no sqrt)")


# ── spawn_damage_number wires the stagger ─────────────────────────────

func test_spawn_damage_number_applies_stagger() -> void:
	var src := _read(BATTLE_RESULTS)
	var fn_idx: int = src.find("func spawn_damage_number")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx)
	assert_true(body.contains("var stagger_y: float = _count_recent_popups_near(pos) * STAGGER_STEP"),
		"spawn_damage_number must compute stagger_y from helper count")
	assert_true(body.contains("dmg_num.position = pos + Vector2(randf_range(-10, 10), -30 - stagger_y)"),
		"spawn_damage_number must offset y by -30 - stagger_y")


func test_spawn_miss_number_applies_stagger() -> void:
	# Pin: miss popups also stagger. Multiple misses on the same target
	# (e.g., blind status causing repeated misses) shouldn't overlap.
	var src := _read(BATTLE_RESULTS)
	var fn_idx: int = src.find("func spawn_miss_number")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx)
	assert_true(body.contains("var stagger_y: float = _count_recent_popups_near(pos) * STAGGER_STEP"),
		"spawn_miss_number must compute stagger_y from helper count")
	assert_true(body.contains("dmg_num.position = pos + Vector2(randf_range(-10, 10), -30 - stagger_y)"),
		"spawn_miss_number must offset y by -30 - stagger_y")


# ── Negative pins: pre-fix shape gone ─────────────────────────────────

func test_old_unstaggered_position_gone() -> void:
	# The pre-fix shape was `dmg_num.position = pos + Vector2(randf_range(-10, 10), -30)`
	# WITHOUT the stagger subtraction. Verify it's gone from both
	# spawn_damage_number and spawn_miss_number.
	var src := _read(BATTLE_RESULTS)
	# Count how many times the OLD bare-(-30) pattern appears — should be 0.
	# Format string has `-30` followed immediately by `)` then maybe `\n` or whitespace.
	var bad_pattern := "Vector2(randf_range(-10, 10), -30)"
	# Count occurrences.
	var idx: int = 0
	var count: int = 0
	while true:
		var next_idx: int = src.find(bad_pattern, idx)
		if next_idx < 0:
			break
		count += 1
		idx = next_idx + 1
	assert_eq(count, 0,
		"pre-fix bare Vector2(randf_range(-10, 10), -30) must be gone")


# ── Runtime: 3 spawns at same pos yield 3 distinct y values ──────────

func test_runtime_three_spawns_have_distinct_y() -> void:
	# Construct a minimal mock _scene (any Node will do) and call
	# spawn_damage_number 3 times at the same pos.
	var scene := Node2D.new()
	add_child_autofree(scene)
	var BRD = load(BATTLE_RESULTS)
	var display = BRD.new(scene)

	# Pre-fill nothing — first spawn should be stagger=0.
	var pos := Vector2(640, 360)

	display.spawn_damage_number(pos, 10, false, false)
	display.spawn_damage_number(pos, 20, false, false)
	display.spawn_damage_number(pos, 30, false, false)

	# Filter to popups via has_method (avoids type-identity quirks in test contexts).
	var y_values: Array = []
	for child in scene.get_children():
		if child.has_method("setup_miss"):
			y_values.append(child.position.y)
	y_values.sort()
	assert_eq(y_values.size(), 3, "3 spawns produced 3 popups")
	if y_values.size() == 3:
		# At least one of the staggered popups must differ from the
		# base y (pos.y - 30 = 330). If stagger works, popups are at
		# 330, 312, 294 — at least one distinct value.
		var unique: Dictionary = {}
		for y in y_values:
			unique[y] = true
		assert_gte(unique.size(), 2,
			"stagger must produce at least 2 distinct y values for 3 same-pos spawns (got %s)" % str(y_values))
		# Stronger check: highest popup must be at least STAGGER_STEP above lowest.
		var spread: float = y_values[2] - y_values[0]
		assert_gte(spread, BRD.STAGGER_STEP,
			"y-spread of 3 staggered popups must be >= STAGGER_STEP (got %f)" % spread)


func test_runtime_far_apart_spawns_dont_stagger() -> void:
	# Spawn 3 popups but at different positions far apart. Each should
	# spawn at base offset (-30) since none are within STAGGER_RADIUS.
	var scene := Node2D.new()
	add_child_autofree(scene)
	var BRD = load(BATTLE_RESULTS)
	var display = BRD.new(scene)

	display.spawn_damage_number(Vector2(100, 100), 10, false, false)
	display.spawn_damage_number(Vector2(500, 500), 20, false, false)
	display.spawn_damage_number(Vector2(900, 900), 30, false, false)

	# Each popup y = its pos.y - 30 (no stagger since they're far apart).
	var ys: Array = []
	for child in scene.get_children():
		if child.get_class() == "Node2D":
			ys.append(child.position.y)
	ys.sort()
	# Expected: 70 (100-30), 470 (500-30), 870 (900-30).
	assert_eq(ys.size(), 3)
	if ys.size() == 3:
		assert_eq(ys[0], 70.0, "first popup at y=70 (no stagger)")
		assert_eq(ys[1], 470.0, "second at y=470 (no stagger)")
		assert_eq(ys[2], 870.0, "third at y=870 (no stagger)")


# ── Cross-pin: tick 205 Toast stacking pattern preserved ──────────────

func test_tick_205_toast_stacking_preserved() -> void:
	# Non-regression: this is a different stacking system from
	# Toast.gd but the same insight. Confirm Toast.gd still has
	# its STACK_ROW_HEIGHT.
	var toast_src: String = FileAccess.get_file_as_string("res://src/ui/Toast.gd")
	assert_true(toast_src.contains("const STACK_ROW_HEIGHT := 48.0"),
		"tick 205 Toast STACK_ROW_HEIGHT preserved")
