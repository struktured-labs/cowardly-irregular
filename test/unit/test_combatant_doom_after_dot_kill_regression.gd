extends GutTest

## Regression: Combatant.update_buff_durations() must not re-fire died()
## via the doom_counter path when the combatant was already killed
## earlier in the same update pass.
##
## Trigger surface: a combatant under both Death Sentence (doom_counter
## > 0) AND a damage-over-time status (poison/burn). If the DoT lethal
## tick fires, is_alive flips to false. The poison/burn blocks already
## guard on is_alive to prevent the DoT cascade. But the doom_counter
## block at the bottom of update_buff_durations did NOT — it would
## decrement and, if it reached 0 on this same tick, call die() a
## second time. died() emits the same-named signal each call.
##
## Most listeners (BattleManager._on_combatant_died) already dedupe
## (`combatant not in _ko_this_battle`) but other listeners
## (BattleEnemySpawner, BattleScene summon handlers) connect raw to
## .died and would double-count the death — KO count, gloat line, EXP
## triggers all subject to double-fire.
##
## Fix: add `and is_alive` to the doom_counter block's entry condition,
## matching the existing is_alive guard on poison/burn/regen.
##
## Tests:
##   • Behavioural: poisoned + 1-turn doom → update fires died ONCE
##     (not twice). Combatant ends up dead with consistent state.
##   • Doom can still fire from natural countdown when no DoT has
##     killed yet (regression-against-overreach).
##   • Source pin: the doom block has the is_alive guard.

const COMBATANT_PATH := "res://src/battle/Combatant.gd"


func _read(path: String) -> String:
	var text: String = FileAccess.get_file_as_string(path)
	assert_ne(text, "", "Expected %s to be readable" % path)
	return text


# ── Source pin ────────────────────────────────────────────────────────────────

func test_doom_block_gates_on_is_alive() -> void:
	var text := _read(COMBATANT_PATH)
	# Look for the doom_counter > 0 guard and assert the is_alive conjunct.
	var idx := text.find("if doom_counter > 0")
	assert_gt(idx, -1, "doom_counter > 0 guard must exist in update_buff_durations")
	var line_slice: String = text.substr(idx, 100)
	assert_true(line_slice.contains("is_alive"),
		"doom_counter block must gate on is_alive to prevent double died() after a DoT lethal tick")


# ── Behavioural ──────────────────────────────────────────────────────────────

func _make_combatant() -> Combatant:
	var c := Combatant.new()
	c.combatant_name = "DoomedTester"
	c.max_hp = 100
	c.max_mp = 50
	add_child_autofree(c)
	# Combatant._ready resets HP/MP after add_child.
	c.current_hp = 100
	c.current_mp = 50
	return c


func test_died_fires_once_when_poison_kills_and_doom_was_pending() -> void:
	# Pre-fix: poison killed → is_alive=false → died emitted. Then doom
	# block STILL ran (no is_alive guard), decrementing doom_counter
	# from 1 → 0 → die() called again → died emitted again.
	var c := _make_combatant()
	# Make poison lethal: max_hp 20 → 5% = 1 damage, but max(1, …). HP=1 dies.
	c.max_hp = 20
	c.current_hp = 1
	c.add_status("poison", 5)
	c.doom_counter = 1  # 1 turn from doom triggering
	# Array-as-counter so the lambda captures by reference (GDScript
	# lambdas capture ints by value — `count += 1` inside the lambda
	# would mutate a local copy and leave the outer var at 0).
	var death_emits: Array[int] = [0]
	c.died.connect(func(): death_emits[0] += 1)
	c.update_buff_durations()
	# Combatant must end up dead.
	assert_false(c.is_alive, "poisoned combatant with 1 HP must end up dead")
	# died must fire exactly once — NOT once for poison and once for doom.
	assert_eq(death_emits[0], 1,
		"died() must fire exactly once even when poison kills BEFORE doom would have triggered")


func test_doom_still_fires_naturally_when_no_dot_killed_first() -> void:
	# Regression-against-overreach: the is_alive guard must not break the
	# normal doom-triggers-death path when nothing else killed first.
	var c := _make_combatant()
	c.doom_counter = 1  # one turn left
	# Array-as-counter so the lambda captures by reference (GDScript
	# lambdas capture ints by value — `count += 1` inside the lambda
	# would mutate a local copy and leave the outer var at 0).
	var death_emits: Array[int] = [0]
	c.died.connect(func(): death_emits[0] += 1)
	c.update_buff_durations()
	assert_eq(int(c.doom_counter), 0,
		"doom_counter must still decrement from 1 to 0 when combatant is alive")
	assert_false(c.is_alive, "doom expiring at 0 must trigger die()")
	assert_eq(death_emits[0], 1, "normal doom death must fire died exactly once")


func test_doom_does_not_decrement_on_already_dead_combatant() -> void:
	# If the combatant is dead at the start of update_buff_durations, the
	# doom counter must not tick (no point — already dead, and ticking
	# would emit died() again if it happened to land on 0).
	var c := _make_combatant()
	c.is_alive = false
	c.current_hp = 0
	c.doom_counter = 3
	# Array-as-counter so the lambda captures by reference (GDScript
	# lambdas capture ints by value — `count += 1` inside the lambda
	# would mutate a local copy and leave the outer var at 0).
	var death_emits: Array[int] = [0]
	c.died.connect(func(): death_emits[0] += 1)
	c.update_buff_durations()
	# doom_counter must not have ticked (already dead).
	assert_eq(int(c.doom_counter), 3,
		"doom_counter must not tick when combatant is already dead")
	assert_eq(death_emits[0], 0,
		"died must not fire when calling update_buff_durations on an already-dead combatant")
