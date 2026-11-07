extends GutTest

## struktured 2026-11-07: "'not enough MP' stopping you from doing something in a menu should be overridable by the player
## if they know more than you about the future. Like you hit the button 3+ times." An MP-short ability row used to be
## built `disabled` with no targets, and the cursor SKIPS disabled rows, so the player could not even land on it. Now a
## row short ONLY on MP is landable with its targets; presses 1-2 refuse and say how many remain, the third on the same
## row arms it (its data carries `forced`), and the Advance queue takes a forced cast past its MP shortfall. Execution
## re-checks MP, so a still-short cast fizzles without spending (battle's half). Silence and the rest stay hard.

const ABILITY := "acid_spray"   # all_enemies: buildable from a bare BattleCommandMenu (see the silence regression)


func _foe() -> Combatant:
	var e := Combatant.new()
	e.initialize({"name": "Slime", "max_hp": 50, "max_mp": 0, "attack": 5, "defense": 0, "magic": 0, "speed": 5})
	add_child_autofree(e)
	return e


func _caster(mp: int, silenced: bool = false) -> Combatant:
	var c := Combatant.new()
	c.initialize({"name": "Mage", "max_hp": 100, "max_mp": 999, "attack": 8, "defense": 0, "magic": 20, "speed": 10})
	add_child_autofree(c)
	c.learned_abilities.append(ABILITY)
	c.current_mp = mp
	if silenced:
		c.add_status("silence", 2)
	return c


func _row(c: Combatant) -> Dictionary:
	var foes: Array[Combatant] = [_foe()]
	return BattleCommandMenu.new(null)._build_ability_menu_item(ABILITY, c, foes, Transform2D.IDENTITY)


func _menu(row: Dictionary) -> Win98Menu:
	var m: Win98Menu = autofree(Win98Menu.new())
	m.menu_items = [row]
	m.selected_index = 0
	return m


func test_an_mp_short_row_is_landable_and_marked() -> void:
	var row := _row(_caster(0))
	assert_gt(JobSystem.get_ability_mp_cost(_caster(999), ABILITY), 0, "CONTROL: the ability costs MP")
	assert_true(bool(row.get("mp_short", false)), "a row short only on MP is marked mp_short")
	assert_false(bool(row.get("disabled", false)), "and is NOT disabled, so the cursor can land on it")
	assert_false(bool(row.get("cost_affordable", true)), "its cost still reads unaffordable")
	var ok := _row(_caster(999))
	assert_false(bool(ok.get("mp_short", false)), "CONTROL: an affordable row is not marked")


func test_three_presses_arm_it_and_the_first_two_say_how_many_remain() -> void:
	var row := _row(_caster(0))
	var m := _menu(row)
	assert_true(m._row_blocked(row), "CONTROL: before any press the row is blocked")
	assert_false(m._press_toward_force(row), "press 1 does not arm")
	assert_string_contains(m._reject_text(row), "twice more", "press 1 says two more")
	assert_false(m._press_toward_force(row), "press 2 does not arm")
	assert_string_contains(m._reject_text(row), "once more", "press 2 says one more")
	assert_true(m._press_toward_force(row), "press 3 arms it")
	assert_false(m._row_blocked(row), "an armed row proceeds like any other")
	assert_true(bool(row["data"].get("forced", false)), "and its action data carries forced")


func test_moving_the_cursor_or_waiting_resets_the_count() -> void:
	var row := _row(_caster(0))
	var m := _menu(row)
	m._press_toward_force(row)
	m._press_toward_force(row)
	m._reset_force()   # what _nav_step does on a cursor move
	assert_false(m._press_toward_force(row), "after a move, a press is press 1 again")
	m._press_toward_force(row)
	m._force_last_ms -= m.FORCE_WINDOW_MS + 1   # the window lapses
	assert_false(m._press_toward_force(row), "a press after the window starts over")
	assert_true(m._row_blocked(row), "and the row is still blocked")


func test_a_silenced_cast_cannot_be_forced() -> void:
	var row := _row(_caster(0, true))
	var m := _menu(row)
	assert_false(bool(row.get("mp_short", false)), "a silenced caster's row is not mp_short")
	for i in 5:
		assert_false(m._press_toward_force(row), "press %d never arms a silenced cast" % (i + 1))


func test_the_advance_queue_takes_a_forced_cast_past_its_shortfall() -> void:
	var m: Win98Menu = autofree(Win98Menu.new())
	m.set_queue_budget({"mp": 0}, func(_d): return {"mp": 10})
	m._queue_current_action({"id": "ability_x", "data": {"ability_id": ABILITY}, "label": "Acid Spray"})
	assert_eq(m._queued_actions.size(), 0, "CONTROL: an unforced MP-short cast is refused by the queue")
	m._queue_current_action({"id": "ability_x", "data": {"ability_id": ABILITY, "forced": true}, "label": "Acid Spray"})
	assert_eq(m._queued_actions.size(), 1, "a forced one is queued")
	assert_true(str(m._queued_actions[0]["label"]).ends_with("!"), "and marked forced in the queue")


## struktured: "of course they can't advance more than they are allowed to, no matter what." Forcing lifts the MP check
## ONLY: a full queue and an item-count limit refuse a forced cast exactly as an ordinary one.
func test_forcing_never_lifts_an_advance_limit() -> void:
	var m: Win98Menu = autofree(Win98Menu.new())
	m.set_queue_budget({"mp": 0, "ether": 1}, func(d): return {"mp": 10} if str(d.get("ability_id", "")) != "" else {"ether": 1})
	var forced := {"id": "ability_x", "data": {"ability_id": ABILITY, "forced": true}, "label": "Acid Spray"}
	m._queue_current_action(forced)
	assert_eq(m._queued_actions.size(), 1, "CONTROL: within the limits, the forced cast queues")
	m._max_queue_size = 1
	m._queue_current_action(forced.duplicate(true))
	assert_eq(m._queued_actions.size(), 1, "a full queue refuses a forced cast")
	m._max_queue_size = 4
	m._queue_current_action({"id": "item_e", "data": {"item_id": "ether"}, "label": "Ether"})
	var item_forced := {"id": "item_e", "data": {"item_id": "ether", "forced": true}, "label": "Ether"}
	m._queue_current_action(item_forced)
	assert_eq(m._queued_actions.size(), 2, "and forced cannot spend a second of a one-item stock")
