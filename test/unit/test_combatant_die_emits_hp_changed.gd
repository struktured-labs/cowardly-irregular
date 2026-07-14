extends GutTest

## tick 283: Combatant.die() now emits hp_changed alongside died.
##
## Pre-fix die() was called from BattleManager's PERMAKILL ability
## path (line 3332) with NO hp_changed signal. UI listeners
## (BattleUIManager) update the HP bar via hp_changed — without it
## the bar stayed at the pre-permakill HP value until some other
## event triggered a redraw. So PERMAKILL appeared to leave the
## target alive on the HUD until you scrolled the action queue or
## attacked them.
##
## Ordering matches take_damage (tick where comment landed):
##   is_alive flipped BEFORE hp_changed emit so listeners see the
##   post-death state on the sample tick.


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


# ── hp_changed fires on die() ─────────────────────────────────────

func test_die_emits_hp_changed() -> void:
	var c := _make_combatant()
	watch_signals(c)
	c.die()
	assert_signal_emitted(c, "hp_changed",
		"die() must emit hp_changed so UI listeners see the lethal drop")


func test_die_emits_hp_changed_with_old_and_zero() -> void:
	var c := _make_combatant()
	c.current_hp = 47  # Mid-fight HP
	watch_signals(c)
	c.die()
	assert_signal_emitted_with_parameters(c, "hp_changed", [47, 0],
		"hp_changed(old_hp, new_hp) — old must be pre-die HP, new must be 0")


# ── died signal still fires (don't regress the other listener) ──

func test_die_still_emits_died() -> void:
	var c := _make_combatant()
	watch_signals(c)
	c.die()
	assert_signal_emitted(c, "died",
		"died signal must still fire for the other listeners (battle end check, etc.)")


# ── Ordering: is_alive flipped BEFORE hp_changed ──────────────────

func test_is_alive_false_when_hp_changed_fires() -> void:
	# A listener connected to hp_changed must observe is_alive=false
	# at signal-handler time (matches take_damage's tick-235 fix).
	# GDScript lambdas capture primitives by VALUE — use a single-cell
	# Array so the assignment reaches the outer scope.
	var c := _make_combatant()
	var seen: Array = [true]  # array as shared mutable cell
	c.hp_changed.connect(func(_old, _new):
		seen[0] = c.is_alive
	)
	c.die()
	assert_false(seen[0],
		"hp_changed listener must see is_alive=false (ordering: is_alive flip BEFORE emit)")


# ── current_hp set to 0 ───────────────────────────────────────────

func test_current_hp_zero_after_die() -> void:
	var c := _make_combatant()
	c.current_hp = 73
	c.die()
	assert_eq(c.current_hp, 0, "current_hp must be 0 after die()")
	assert_false(c.is_alive, "is_alive must be false after die()")


# ── Source pin: ordering invariant captured in code ────────────────

func test_source_pins_correct_ordering() -> void:
	var src: String = FileAccess.get_file_as_string(COMBATANT_SCRIPT)
	var fn_idx: int = src.find("func die()")
	assert_gt(fn_idx, -1, "die() must exist")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	# is_alive = false must come BEFORE hp_changed.emit
	var is_alive_idx: int = body.find("is_alive = false")
	var hp_emit_idx: int = body.find("hp_changed.emit")
	assert_gt(is_alive_idx, -1, "die() must set is_alive = false")
	assert_gt(hp_emit_idx, -1, "die() must emit hp_changed")
	assert_lt(is_alive_idx, hp_emit_idx,
		"is_alive = false MUST come before hp_changed.emit (UI listeners need post-death state)")
