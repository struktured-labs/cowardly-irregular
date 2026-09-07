extends GutTest

## tick 209: BattleScene._spawn_elemental_indicator now staggers
## WEAK!/RESIST/IMMUNE! labels so multi-element hits (formation
## combos like Fire+Ice=Steam, weakness exploit chains, AoE
## attacks hitting multiple elements) don't pile labels on top of
## each other at the same y position.
##
## Pre-fix every elemental indicator spawned at `pos.y - 30`
## (where pos = sprite_position). When a multi-element ability
## dealt damage to multiple targets in quick succession (or
## triggered WEAK + IMMUNE on different aspects of the same
## creature), the indicator labels stacked on top of each other
## and the player couldn't read them.
##
## Same stacking insight as tick 205 (Toast) and tick 208 (damage
## popups), applied to a third notification surface. The labels
## are tagged via set_meta("elem_indicator", true) so the counter
## doesn't accidentally match other Labels at BattleScene root.

const BATTLE_SCENE := "res://src/battle/BattleScene.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


# ── Constants present ──────────────────────────────────────────────────

func test_stagger_step_constant_defined() -> void:
	var src := _read(BATTLE_SCENE)
	assert_true(src.contains("const ELEM_STAGGER_STEP := 18.0"),
		"ELEM_STAGGER_STEP must be 18.0 — same readable separation as tick 208")


func test_stagger_radius_constant_defined() -> void:
	var src := _read(BATTLE_SCENE)
	assert_true(src.contains("const ELEM_STAGGER_RADIUS_SQUARED := 40.0 * 40.0"),
		"ELEM_STAGGER_RADIUS_SQUARED must be (40px)² — squared to avoid sqrt")


# ── Helper function ────────────────────────────────────────────────────

func test_helper_function_present() -> void:
	var src := _read(BATTLE_SCENE)
	assert_true(src.contains("func _count_recent_elem_indicators_near(pos: Vector2) -> int:"),
		"_count_recent_elem_indicators_near helper must exist")


func test_helper_filters_by_meta_tag() -> void:
	# Pin: the helper filters by has_meta("elem_indicator") so it
	# doesn't accidentally count unrelated Labels (HP text, status
	# names, etc.) that might exist at BattleScene root.
	var src := _read(BATTLE_SCENE)
	var fn_idx: int = src.find("func _count_recent_elem_indicators_near")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx)
	assert_true(body.contains("child.has_meta(\"elem_indicator\")"),
		"helper must filter by has_meta(\"elem_indicator\") tag")
	assert_true(body.contains("child is Label"),
		"helper must also gate on `child is Label` (cheaper than has_meta for non-Labels)")
	assert_true(body.contains("is_instance_valid(child)"),
		"helper must guard with is_instance_valid")


func test_helper_uses_squared_distance() -> void:
	# Pin: no sqrt on the hot path.
	var src := _read(BATTLE_SCENE)
	var fn_idx: int = src.find("func _count_recent_elem_indicators_near")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx)
	assert_true(body.contains("child.position.distance_squared_to(pos) < ELEM_STAGGER_RADIUS_SQUARED"),
		"helper must use distance_squared_to vs ELEM_STAGGER_RADIUS_SQUARED")


# ── _spawn_elemental_indicator wires the stagger ──────────────────────

func test_spawn_offsets_pos_by_stagger() -> void:
	var src := _read(BATTLE_SCENE)
	var fn_idx: int = src.find("func _spawn_elemental_indicator")
	assert_gt(fn_idx, -1)
	# Next func is `_on_attack_missed` (or _count_recent_elem_indicators_near
	# now); body extends to whichever comes first.
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx)
	assert_true(body.contains("pos.y -= _count_recent_elem_indicators_near(pos) * ELEM_STAGGER_STEP"),
		"spawn must subtract stagger from pos.y (stack upward)")


func test_spawn_tags_the_label() -> void:
	# Pin: each spawned label gets the meta tag so the next spawn's
	# counter finds it.
	var src := _read(BATTLE_SCENE)
	var fn_idx: int = src.find("func _spawn_elemental_indicator")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx)
	assert_true(body.contains("label.set_meta(\"elem_indicator\", true)"),
		"spawn must tag the Label with set_meta(\"elem_indicator\", true)")


func test_spawn_tag_set_before_add_child() -> void:
	# Pin: ordering — set_meta MUST run before add_child, otherwise
	# the next spawn (if it happens immediately after add_child as
	# in formation combos) walks the tree and finds an untagged Label.
	var src := _read(BATTLE_SCENE)
	var fn_idx: int = src.find("func _spawn_elemental_indicator")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx)
	var set_meta_idx: int = body.find("label.set_meta(\"elem_indicator\", true)")
	var add_child_idx: int = body.find("add_child(label)")
	assert_gt(set_meta_idx, -1)
	assert_gt(add_child_idx, -1)
	assert_lt(set_meta_idx, add_child_idx,
		"set_meta must come BEFORE add_child (otherwise next spawn doesn't see the tag)")


# ── Pre-fix shape preservation guards ──────────────────────────────────

func test_immune_text_preserved() -> void:
	# Don't regress the indicator branch logic.
	var src := _read(BATTLE_SCENE)
	assert_true(src.contains("text = \"IMMUNE!\""),
		"IMMUNE! branch preserved")
	assert_true(src.contains("text = \"WEAK!\""),
		"WEAK! branch preserved")
	assert_true(src.contains("text = \"RESIST\""),
		"RESIST branch preserved")


func test_initial_y_offset_preserved() -> void:
	# Pin: the base -30 offset (above damage number) is preserved,
	# stagger ADDS to it (more negative = higher).
	var src := _read(BATTLE_SCENE)
	var fn_idx: int = src.find("func _spawn_elemental_indicator")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx)
	assert_true(body.contains("pos.y -= 30  # Offset above damage number"),
		"base -30 offset preserved")


# ── Cross-pins: prior stacking work preserved ──────────────────────────

func test_tick_208_damage_popup_stagger_preserved() -> void:
	var brd: String = FileAccess.get_file_as_string("res://src/battle/BattleResultsDisplay.gd")
	assert_true(brd.contains("const STAGGER_STEP := 18.0"),
		"tick 208 damage popup STAGGER_STEP preserved")


func test_tick_205_toast_stacking_preserved() -> void:
	var toast: String = FileAccess.get_file_as_string("res://src/ui/Toast.gd")
	assert_true(toast.contains("const STACK_ROW_HEIGHT := 48.0"),
		"tick 205 Toast STACK_ROW_HEIGHT preserved")
