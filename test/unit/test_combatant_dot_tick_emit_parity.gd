extends GutTest

## tick 302: poison/burn DOT ticks now guard hp_changed.emit on
## actual change — parity with the regen HOT tick at line ~511
## which already gated on `healed > 0`.
##
## Closes the spurious-emit pattern audit on hp_changed:
##   tick 283: die() guard
##   tick 284: apply_permanent_injury clamp
##   tick 288: heal() emit guard
##   tick 301: take_damage() emit guard
##   tick 302: DOT poison/burn parity (this tick)
##
## Real spurious-emit cases for DOTs:
##   - max_hp == 0 (boss with zeroed-out max_hp via Scriptweaver):
##     max(0, 0 - 1) == 0, current_hp was already 0. Emit (0, 0).
##   - mid-tick revive race where is_alive=true but current_hp=0
##     for one frame: same shape.


const COMBATANT_SCRIPT := "res://src/battle/Combatant.gd"


func _make_combatant() -> Combatant:
	var script: GDScript = load(COMBATANT_SCRIPT)
	var c: Combatant = script.new()
	c.combatant_name = "Test"
	c.max_hp = 100
	c.current_hp = 100
	c.is_alive = true
	add_child_autofree(c)
	return c


# ── poison guard ──────────────────────────────────────────────────

func test_poison_tick_with_zero_change_no_emit() -> void:
	# Force the edge case: current_hp=0, is_alive=true (impossible in
	# normal play but the bug-class window does open during mid-tick
	# revive races). Poison damage stays 0 → 0 (clamped).
	var c := _make_combatant()
	c.current_hp = 0  # spurious-state setup
	c.add_status("poison", 3)
	watch_signals(c)
	c.update_buff_durations()
	assert_signal_not_emitted(c, "hp_changed",
		"poison tick with no actual HP change must NOT emit hp_changed")
	# status_tick_damage is also gated under the same guard.
	assert_signal_not_emitted(c, "status_tick_damage",
		"status_tick_damage paired emit must skip too (popup wouldn't make sense)")


func test_poison_tick_with_real_damage_still_emits() -> void:
	# Normal path: poison ticks for 5% max_hp → real damage → emits.
	var c := _make_combatant()
	c.add_status("poison", 3)
	watch_signals(c)
	c.update_buff_durations()
	assert_signal_emitted(c, "hp_changed",
		"poison tick with real damage must still emit")
	assert_signal_emitted(c, "status_tick_damage",
		"status_tick_damage must fire alongside hp_changed")


# ── burn guard ────────────────────────────────────────────────────

func test_burn_tick_with_zero_change_no_emit() -> void:
	var c := _make_combatant()
	c.current_hp = 0
	c.add_status("burning", 3)
	watch_signals(c)
	c.update_buff_durations()
	assert_signal_not_emitted(c, "hp_changed",
		"burn tick with no actual HP change must NOT emit hp_changed")


func test_burn_tick_with_real_damage_still_emits() -> void:
	var c := _make_combatant()
	c.add_status("burning", 3)
	watch_signals(c)
	c.update_buff_durations()
	assert_signal_emitted(c, "hp_changed")
	assert_signal_emitted(c, "status_tick_damage")


# ── Parity pin: regen still guards (cross-pin against tick 283) ──

func test_regen_still_guards_on_healed_gt_zero() -> void:
	# regen had the guard pre-tick-302 — pin so a future refactor
	# doesn't accidentally drop it (parity would break the other way).
	var src: String = FileAccess.get_file_as_string(COMBATANT_SCRIPT)
	var fn_idx: int = src.find("func update_buff_durations")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	# regen block has its own "if healed > 0:" guard.
	assert_true(body.contains("if healed > 0:"),
		"regen tick must keep `if healed > 0:` guard (pre-existing parity anchor)")


# ── Source pin: poison + burn now have matching guards ───────────

func test_poison_burn_now_guard_on_actual_change() -> void:
	var src: String = FileAccess.get_file_as_string(COMBATANT_SCRIPT)
	# Poison guard
	assert_true(src.contains("if current_hp != old_hp_poison:"),
		"poison tick must guard on current_hp != old_hp_poison")
	# Burn guard
	assert_true(src.contains("if current_hp != old_hp_burn:"),
		"burn tick must guard on current_hp != old_hp_burn")
