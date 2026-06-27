extends GutTest

## tick 288: Combatant.heal() now guards hp_changed.emit on actual
## change.
##
## Pre-fix heal() emitted hp_changed even when current_hp was already
## at max_hp (the min(max_hp, current_hp + amount) clamp pinned it,
## healed = 0 returned to the caller). UI listeners ran the redraw
## path uselessly each turn that a healer cast a heal on an already-
## full-HP target.
##
## Matches tick-286 ap_changed and tick-283/284 hp_changed guard
## pattern (emit only on actual change).


const COMBATANT_SCRIPT := "res://src/battle/Combatant.gd"


func _make_combatant() -> Combatant:
	var script: GDScript = load(COMBATANT_SCRIPT)
	var c: Combatant = script.new()
	c.combatant_name = "Test"
	c.max_hp = 100
	c.current_hp = 100  # at full
	c.is_alive = true
	add_child_autofree(c)
	return c


# ── No emit when healing a full-HP target ─────────────────────────

func test_heal_at_full_hp_does_not_emit() -> void:
	var c := _make_combatant()
	watch_signals(c)
	var healed: int = c.heal(20)
	assert_eq(healed, 0, "heal at full HP returns 0 (no change)")
	assert_signal_not_emitted(c, "hp_changed",
		"hp_changed must NOT fire when heal is a no-op (current_hp already at max_hp)")


# ── Heal below max still emits normally ───────────────────────────

func test_heal_below_max_still_emits() -> void:
	var c := _make_combatant()
	c.current_hp = 50
	watch_signals(c)
	var healed: int = c.heal(30)
	assert_eq(healed, 30, "heal from 50 → 80 returns 30")
	assert_signal_emitted_with_parameters(c, "hp_changed", [50, 80],
		"hp_changed must fire with (50, 80)")


# ── Heal that clamps to max still emits (partial change > 0) ─────

func test_heal_clamped_to_max_still_emits_when_actual_change() -> void:
	var c := _make_combatant()
	c.current_hp = 80
	watch_signals(c)
	var healed: int = c.heal(50)
	assert_eq(healed, 20, "heal clamped to max: 80 → 100, returns 20")
	assert_signal_emitted_with_parameters(c, "hp_changed", [80, 100],
		"hp_changed must fire even when clamped, because there was actual change")


# ── Heal with amount=0 doesn't emit (no actual change) ───────────

func test_heal_zero_amount_does_not_emit() -> void:
	var c := _make_combatant()
	c.current_hp = 50
	watch_signals(c)
	var healed: int = c.heal(0)
	assert_eq(healed, 0, "heal(0) returns 0")
	assert_signal_not_emitted(c, "hp_changed",
		"hp_changed must NOT fire on heal(0)")


# ── Heal of dead target follows existing dead-guard ──────────────

func test_heal_dead_target_no_emit() -> void:
	# Existing contract (line 256): if not is_alive, return 0. No
	# clamp, no current_hp mutation, no signal. The new guard mustn't
	# regress this path.
	var c := _make_combatant()
	c.is_alive = false
	c.current_hp = 0
	watch_signals(c)
	var healed: int = c.heal(50)
	assert_eq(healed, 0, "heal on dead target returns 0")
	assert_signal_not_emitted(c, "hp_changed",
		"dead target heal still no-ops without emit")
