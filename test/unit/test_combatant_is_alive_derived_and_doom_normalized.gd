extends GutTest

## tick 158 regression: Combatant.from_dict must seal two more
## inconsistency surfaces:
##
##   1. is_alive derived from current_hp on load — not trusted
##      from save. Pre-fix:
##        - current_hp=0, is_alive=true → "alive at 0 HP" until
##          next take_damage flips the bool
##        - current_hp=50, is_alive=false → "dead but healable"
##      Everywhere else in the codebase the pairing is enforced
##      (die: is_alive=false + current_hp=0; revive: is_alive=true
##      + current_hp>=1). Load now derives is_alive directly from
##      current_hp > 0.
##
##   2. doom_counter int() coerce + normalize negatives to -1.
##      The codebase uses -1 as the "not doomed" sentinel and
##      > 0 / == 0 checks for active countdown. A save with -5
##      isn't directly harmful (> 0 returns false same as -1)
##      but muddles the contract.

const COMBATANT := "res://src/battle/Combatant.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


# ── Source pins ──────────────────────────────────────────────────────────

func test_is_alive_derived_from_current_hp() -> void:
	var src := _read(COMBATANT)
	# Pin: derivation, not raw assignment.
	assert_true(src.contains("is_alive = current_hp > 0"),
		"is_alive must be DERIVED from current_hp, not trusted from save")
	# Negative pin: the old raw assign must be gone.
	assert_false(src.contains("is_alive = data[\"is_alive\"]"),
		"old raw `is_alive = data[...]` assignment must be gone — the bool from save is no longer trusted")


func test_is_alive_unconditional_not_guarded_on_data_has() -> void:
	# Pin: the derivation must NOT be inside `if data.has("is_alive")`.
	# A save that LACKS the field would otherwise leave is_alive at
	# its constructor default (true), even if current_hp loaded as 0.
	var src := _read(COMBATANT)
	# Find the is_alive derive line.
	var derive_idx: int = src.find("is_alive = current_hp > 0")
	assert_gt(derive_idx, -1, "derive line must exist")
	# The 200 chars BEFORE this line must NOT contain
	# `if data.has("is_alive")`.
	var window_start: int = max(0, derive_idx - 200)
	var window: String = src.substr(window_start, derive_idx - window_start)
	assert_false(window.contains("if data.has(\"is_alive\")"),
		"is_alive derivation must NOT be guarded on data.has — unconditional so saves lacking the field still get a consistent value")


func test_doom_counter_int_coerce_and_negative_normalize() -> void:
	var src := _read(COMBATANT)
	assert_true(src.contains("var raw_doom: int = int(data[\"doom_counter\"])"),
		"doom_counter must int() coerce — JSON returns float")
	assert_true(src.contains("doom_counter = -1 if raw_doom < 0 else raw_doom"),
		"any saved negative doom_counter must normalize to the -1 sentinel")
	assert_false(src.contains("doom_counter = data[\"doom_counter\"]\n"),
		"old direct `doom_counter = data[...]` assign must be gone")


func test_is_alive_derivation_runs_AFTER_current_hp_load() -> void:
	# Critical ordering: current_hp must be loaded BEFORE the
	# is_alive derivation reads it. Otherwise derivation uses the
	# constructor default (full HP) and produces the wrong bool.
	var src := _read(COMBATANT)
	var current_hp_load: int = src.find("if data.has(\"current_hp\"):")
	var is_alive_derive: int = src.find("is_alive = current_hp > 0")
	assert_gt(current_hp_load, -1)
	assert_gt(is_alive_derive, -1)
	assert_lt(current_hp_load, is_alive_derive,
		"current_hp must be loaded BEFORE is_alive derivation reads it")


# ── Runtime behavior ────────────────────────────────────────────────────

func test_runtime_zero_hp_forces_is_alive_false() -> void:
	# Save corruption case: is_alive=true but current_hp=0.
	# Post-fix: is_alive becomes false regardless.
	var CombatantScript = load(COMBATANT)
	var c = CombatantScript.new()
	add_child_autofree(c)
	c.from_dict({
		"max_hp": 100,
		"current_hp": 0,
		"is_alive": true,  # corrupted
	})
	assert_eq(c.current_hp, 0, "sanity: current_hp=0 loaded")
	assert_false(c.is_alive,
		"is_alive must derive false from current_hp=0, regardless of saved bool")


func test_runtime_positive_hp_forces_is_alive_true() -> void:
	# Symmetric: is_alive=false but current_hp>0 → is_alive becomes true.
	var CombatantScript = load(COMBATANT)
	var c = CombatantScript.new()
	add_child_autofree(c)
	c.from_dict({
		"max_hp": 100,
		"current_hp": 50,
		"is_alive": false,  # corrupted
	})
	assert_true(c.is_alive,
		"is_alive must derive true from positive current_hp, regardless of saved bool")


func test_runtime_save_without_is_alive_field_still_derives() -> void:
	# Pin: even when the save data lacks the is_alive key, the
	# derivation must run.
	var CombatantScript = load(COMBATANT)
	var c = CombatantScript.new()
	add_child_autofree(c)
	c.from_dict({"max_hp": 100, "current_hp": 0})  # no is_alive
	assert_false(c.is_alive,
		"is_alive must derive even when the field is absent from save data")


func test_runtime_negative_doom_normalizes_to_minus_1() -> void:
	var CombatantScript = load(COMBATANT)
	var c = CombatantScript.new()
	add_child_autofree(c)
	c.from_dict({"doom_counter": -5})
	assert_eq(c.doom_counter, -1,
		"any negative doom_counter must normalize to the -1 sentinel")


func test_runtime_zero_doom_preserved() -> void:
	# Zero is the kill-trigger value (transient — combatant dies
	# this tick). Round-trip should preserve it as 0, not promote
	# to -1 (negative-only normalize).
	var CombatantScript = load(COMBATANT)
	var c = CombatantScript.new()
	add_child_autofree(c)
	c.from_dict({"doom_counter": 0})
	assert_eq(c.doom_counter, 0,
		"doom_counter=0 must round-trip preserved (kill-trigger semantic)")


func test_runtime_positive_doom_preserved() -> void:
	var CombatantScript = load(COMBATANT)
	var c = CombatantScript.new()
	add_child_autofree(c)
	c.from_dict({"doom_counter": 3})
	assert_eq(c.doom_counter, 3,
		"positive doom_counter must round-trip — countdown value preserved")


# ── Non-regression ──────────────────────────────────────────────────────

func test_runtime_consistent_save_round_trips_alive() -> void:
	var CombatantScript = load(COMBATANT)
	var c = CombatantScript.new()
	add_child_autofree(c)
	c.from_dict({"max_hp": 100, "current_hp": 100, "is_alive": true})
	assert_true(c.is_alive,
		"consistent alive save round-trips correctly")


func test_runtime_consistent_save_round_trips_dead() -> void:
	var CombatantScript = load(COMBATANT)
	var c = CombatantScript.new()
	add_child_autofree(c)
	c.from_dict({"max_hp": 100, "current_hp": 0, "is_alive": false})
	assert_false(c.is_alive,
		"consistent dead save round-trips correctly")
