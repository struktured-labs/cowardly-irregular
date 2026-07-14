extends GutTest

## tick 301: take_damage now guards hp_changed.emit on actual change.
##
## Three real take_damage(0) call paths existed:
##
##  1. take_elemental_damage with 0.5x resistance and 1 base damage
##     → int(1 * 0.5) = 0 → take_damage(0)
##  2. Scriptweaver sets damage_multiplier to 0 (or very low) →
##     int(actual_damage * 0) = 0 → take_damage(0)
##  3. 100% block / mitigation passive → take_damage(0)
##
## Pre-fix all three cases emitted hp_changed(old_hp, old_hp) — a
## redundant signal that triggered UI redraw + log update. Same
## spurious-emit class as tick 286 (ap_changed) and tick 288 (heal).


const COMBATANT_SCRIPT := "res://src/battle/Combatant.gd"


func _make_combatant() -> Combatant:
	var script: GDScript = load(COMBATANT_SCRIPT)
	var c: Combatant = script.new()
	c.combatant_name = "Test"
	c.max_hp = 100
	c.current_hp = 100
	c.defense = 0  # Skip the defense math for cleaner test
	c.is_alive = true
	add_child_autofree(c)
	return c


# ── take_damage with damage_multiplier=0 doesn't emit ───────────

func test_minimum_multiplier_truncates_to_zero_no_emit() -> void:
	# Real path: damage_multiplier is clampf'd to [0.1, 10.0]. With
	# multiplier=0.1 and amount=1, the formula produces:
	#   max(1, ...) = 1, then int(1 * 0.1) = 0.
	# Confirms the guard catches this multiplier-truncation case.
	var prior = GameState.game_constants.get("damage_multiplier", null)
	GameState.game_constants["damage_multiplier"] = 0.0  # clamped to 0.1
	var c := _make_combatant()
	watch_signals(c)
	c.take_damage(1)  # smallest possible amount → 1 → *0.1 → 0
	assert_signal_not_emitted(c, "hp_changed",
		"damage_multiplier-truncated-to-zero must not emit (no actual change)")
	assert_eq(c.current_hp, 100, "current_hp unchanged")
	# Restore.
	if prior == null:
		GameState.game_constants.erase("damage_multiplier")
	else:
		GameState.game_constants["damage_multiplier"] = prior


# ── take_damage(0) still applies 1 damage (existing min-1 design) ─

func test_zero_input_still_deals_min_1() -> void:
	# Documented: line 209 max(1, actual_damage) — JRPG convention,
	# every hit lands as at least 1 unless the upstream blocked it.
	# The guard does NOT change this. Pin so a future "0-min" tweak
	# is intentional.
	var c := _make_combatant()
	c.take_damage(0)
	assert_eq(c.current_hp, 99,
		"take_damage(0) still deals 1 damage (line 209 min-1 floor)")


# ── take_damage with real damage still emits ──────────────────────

func test_real_damage_still_emits() -> void:
	var c := _make_combatant()
	watch_signals(c)
	c.take_damage(10)
	assert_signal_emitted(c, "hp_changed",
		"take_damage with real damage must still emit hp_changed")
	assert_eq(c.current_hp, 90)


# ── Lethal hit still emits (regression check) ─────────────────────

func test_lethal_hit_still_emits() -> void:
	# tick 235 / tick 283 invariant: hp_changed must fire exactly once
	# on a lethal hit. The take_damage path also calls die() which
	# guards on (old_hp != 0) — so on this lethal call, take_damage
	# emits the actual transition (100 → 0) and die() skips the
	# already-emitted hp_changed.
	var c := _make_combatant()
	var hp_count: Array = [0]
	c.hp_changed.connect(func(_o, _n): hp_count[0] += 1)
	c.take_damage(999)
	assert_eq(c.current_hp, 0, "current_hp dropped to 0")
	assert_false(c.is_alive, "is_alive flipped to false")
	assert_eq(hp_count[0], 1,
		"hp_changed must fire EXACTLY once on lethal hit (take_damage emits, die() guard skips redundant)")


# ── Already-dead target (current_hp=0) → no spurious emit ────────

func test_already_dead_target_zero_damage_no_emit() -> void:
	var c := _make_combatant()
	c.current_hp = 0
	c.is_alive = false
	watch_signals(c)
	c.take_damage(0)
	assert_signal_not_emitted(c, "hp_changed",
		"take_damage(0) on already-dead target must NOT emit (no change)")


# ── Damage that clamps to actual change still emits ──────────────

func test_damage_partial_clamp_still_emits() -> void:
	# 10 HP combatant takes 30 damage → drops to 0 (real change).
	# Even though it was clamped, the actual change was > 0.
	var c := _make_combatant()
	c.current_hp = 10
	watch_signals(c)
	c.take_damage(30)
	assert_signal_emitted_with_parameters(c, "hp_changed", [10, 0],
		"take_damage with clamp-but-real-change must emit (10, 0)")


# ── Source pin: guard is in place ────────────────────────────────

func test_source_pin_emit_guard() -> void:
	var src: String = FileAccess.get_file_as_string(COMBATANT_SCRIPT)
	var fn_idx: int = src.find("func take_damage")
	assert_gt(fn_idx, -1, "take_damage must exist")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	# Pin the guard line. Catches accidental revert that removes
	# the if + un-indents the emit.
	assert_true(body.contains("if current_hp != old_hp:") and body.contains("hp_changed.emit(old_hp, current_hp)"),
		"take_damage must guard hp_changed.emit on `current_hp != old_hp`")
