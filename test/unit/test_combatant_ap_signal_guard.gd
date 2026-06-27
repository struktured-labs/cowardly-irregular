extends GutTest

## tick 286: spend_ap / gain_ap now guard ap_changed.emit on actual
## change.
##
## Pre-fix two spurious-emit cases:
##   gain_ap(1) when current_ap == 4 (cap)  → clamp leaves AP at 4
##                                            but ap_changed still fired
##   spend_ap(0) when current_ap == anything → 0-amount no-op also fired
##
## Each cap-reached turn the UI listener (BattleUIManager AP segment
## redraw) was repainting needlessly. Tighter signal contract matches
## the tick-283/284 hp_changed pattern (emit only on actual change).


const COMBATANT_SCRIPT := "res://src/battle/Combatant.gd"


func _make_combatant() -> Combatant:
	var script: GDScript = load(COMBATANT_SCRIPT)
	var c: Combatant = script.new()
	c.combatant_name = "Test"
	c.max_hp = 100
	c.current_hp = 100
	c.is_alive = true
	c.current_ap = 0
	add_child_autofree(c)
	return c


# ── gain_ap at cap doesn't fire ap_changed ────────────────────────

func test_gain_ap_at_cap_does_not_emit() -> void:
	var c := _make_combatant()
	c.current_ap = 4  # at +4 cap
	watch_signals(c)
	c.gain_ap(1)
	assert_signal_not_emitted(c, "ap_changed",
		"gain_ap(1) when already at +4 cap must NOT emit (no actual change)")
	assert_eq(c.current_ap, 4, "current_ap unchanged at cap")


# ── gain_ap below cap still emits normally ────────────────────────

func test_gain_ap_below_cap_still_emits() -> void:
	var c := _make_combatant()
	c.current_ap = 2
	watch_signals(c)
	c.gain_ap(1)
	assert_signal_emitted_with_parameters(c, "ap_changed", [2, 3],
		"gain_ap from 2 → 3 must emit with (2, 3)")


# ── spend_ap(0) is a no-op for the signal ─────────────────────────

func test_spend_ap_zero_amount_no_emit() -> void:
	var c := _make_combatant()
	c.current_ap = 2
	watch_signals(c)
	var ok: bool = c.spend_ap(0)
	assert_true(ok, "spend_ap(0) still returns true (can_brave passes)")
	assert_signal_not_emitted(c, "ap_changed",
		"spend_ap(0) must NOT emit (no actual change)")
	assert_eq(c.current_ap, 2, "current_ap unchanged")


# ── spend_ap with real cost still emits ───────────────────────────

func test_spend_ap_real_cost_still_emits() -> void:
	var c := _make_combatant()
	c.current_ap = 3
	watch_signals(c)
	c.spend_ap(2)
	assert_signal_emitted_with_parameters(c, "ap_changed", [3, 1],
		"spend_ap(2) from 3 → 1 must emit with (3, 1)")


# ── spend_ap blocked by can_brave still doesn't emit ──────────────

func test_spend_ap_blocked_by_can_brave() -> void:
	var c := _make_combatant()
	c.current_ap = -3
	watch_signals(c)
	var ok: bool = c.spend_ap(5)  # would go to -8, below -4 floor
	assert_false(ok, "spend_ap blocked when amount would dip below -4 floor")
	assert_signal_not_emitted(c, "ap_changed",
		"blocked spend_ap must NOT emit")


# ── Cap floor: gain_ap on actual rise from -4 emits ───────────────

func test_gain_ap_from_floor_emits_normally() -> void:
	var c := _make_combatant()
	c.current_ap = -4
	watch_signals(c)
	c.gain_ap(1)
	assert_signal_emitted_with_parameters(c, "ap_changed", [-4, -3],
		"gain_ap rising from floor must emit")
