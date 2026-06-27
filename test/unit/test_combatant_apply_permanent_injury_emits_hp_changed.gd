extends GutTest

## tick 284: apply_permanent_injury(stat=max_hp) now emits hp_changed
## when the clamp actually drops current_hp.
##
## Pre-fix permanent injury silently reduced current_hp below
## max_hp's new ceiling. UI HP bars stayed at the pre-injury value
## until the next take_damage / heal / scene reload sampled the
## state. Symptom: post-battle "fractured ribs" injury reduced
## max_hp from 100 → 88, current_hp clamped 100 → 88, but the HUD
## still showed 100/100.
##
## Same silent-signal bug class as tick 283's die() fix.

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


# ── hp_changed fires when injury clamps current_hp down ───────────

func test_hp_changed_fires_when_injury_clamps_hp() -> void:
	var c := _make_combatant()
	watch_signals(c)
	c.apply_permanent_injury({"stat": "max_hp", "penalty": 12})
	# Pre-injury: 100/100. Post: max_hp=88, current_hp clamped to 88.
	assert_signal_emitted(c, "hp_changed",
		"apply_permanent_injury(max_hp) must emit hp_changed when the clamp drops current_hp")
	assert_eq(c.current_hp, 88, "current_hp must be clamped to new max_hp")
	assert_eq(c.max_hp, 88, "max_hp must be reduced by the penalty")


func test_hp_changed_carries_correct_old_and_new() -> void:
	var c := _make_combatant()
	watch_signals(c)
	c.apply_permanent_injury({"stat": "max_hp", "penalty": 25})
	# Pre: 100/100. Post: 75/75. hp_changed should carry (100, 75).
	assert_signal_emitted_with_parameters(c, "hp_changed", [100, 75],
		"hp_changed must carry (old_hp, new_hp) on the injury clamp")


# ── No spurious emit when current_hp was already at or below cap ─

func test_no_emit_when_current_hp_already_below_new_max() -> void:
	var c := _make_combatant()
	c.current_hp = 30  # Already low
	watch_signals(c)
	c.apply_permanent_injury({"stat": "max_hp", "penalty": 12})
	# Pre: 30/100. Post: max_hp=88, current_hp stays at 30 (no clamp).
	assert_signal_not_emitted(c, "hp_changed",
		"hp_changed must NOT fire when current_hp was already below the new max_hp ceiling (no actual change)")
	assert_eq(c.current_hp, 30, "current_hp unchanged when already under new ceiling")
	assert_eq(c.max_hp, 88, "max_hp still reduced")


# ── Injury actually persists in permanent_injuries list ───────────

func test_injury_added_to_permanent_injuries_list() -> void:
	var c := _make_combatant()
	c.apply_permanent_injury({"stat": "max_hp", "penalty": 12, "description": "Fractured ribs"})
	assert_eq(c.permanent_injuries.size(), 1,
		"injury must be appended to permanent_injuries list")


# ── Non-HP injuries don't emit hp_changed ─────────────────────────

func test_attack_injury_does_not_emit_hp_changed() -> void:
	# Stat injuries other than max_hp shouldn't touch current_hp at all.
	var c := _make_combatant()
	watch_signals(c)
	c.apply_permanent_injury({"stat": "attack", "penalty": 5})
	assert_signal_not_emitted(c, "hp_changed",
		"attack injury must not emit hp_changed (only max_hp clamp does)")
	assert_eq(c.attack, c.base_attack - 5 if "base_attack" in c else c.attack,
		"attack must be reduced; current_hp untouched")
