extends GutTest

## struktured, 2026-09-25, on a laptop: "im holding L to commit and aint nothing happening". The
## queued hint advertises "HOLD <defer> Commit", and holding did nothing.
##
## ⛔ MECHANISM: 150395c46 (2026-09-12) put `if _nav_is_blocked(): return` at the top of
## Win98Menu._process so a held direction could not leak past an open submenu. The hold-to-commit
## timer sat BELOW that return. With a submenu open — and submenus AUTO-EXPAND whenever the cursor
## rests on an item that has one — the submenu takes the press and arms the ROOT's timer, the root's
## _process returns before reading it, and the release path assumes "already handled in _process".
## Holding did nothing at all; the guard was about navigation and swallowed the commit.
##
## 📌 test_commit_the_queue_is_discoverable pins the commit by calling _confirm_turn_with_queue()
## DIRECTLY, so it stayed green through this: it names the defect and never drives the hold. These
## arms drive the real press and let real time and _process do the rest.

const W98 := "res://src/ui/Win98Menu.gd"


func _root_with_two_queued() -> Win98Menu:
	var m = load(W98).new()
	m.is_root_menu = true
	m.battle_mode = true
	add_child_autofree(m)
	m.setup("Command", [
		{"id": "attack", "label": "Attack"},
		{"id": "abilities", "label": "Abilities", "submenu": [{"id": "fire", "label": "Fire"}]},
	], Vector2(10, 10), "fighter")
	# setup() finishes over frames and ends in _auto_expand_submenu(), which CLOSES any open submenu —
	# measured: a submenu opened before this settled was gone one frame later, unblocking the root.
	for i in range(5):
		await get_tree().process_frame
	m._can_accept_input = true
	m.set_max_queue_size(4)
	m.selected_index = 0
	for i in range(2):
		Win98Menu._last_advance_ms = -1000000
		m._handle_advance_input()
	return m


func _defer_event(pressed: bool) -> InputEventAction:
	var e := InputEventAction.new()
	e.action = "battle_defer"
	e.pressed = pressed
	return e


## Press on `target` and hold well past L_HOLD_CONFIRM_TIME while _process runs.
func _hold_defer(target: Win98Menu) -> void:
	Win98Menu._defer_axis_held = false
	target._input(_defer_event(true))
	await get_tree().create_timer(Win98Menu.L_HOLD_CONFIRM_TIME + 0.35).timeout


## The submenu the cursor would auto-expand, opened directly: the timer-driven route segfaulted godot in
## a hand-built harness (2026-09-25), and what this file tests is the root's hold, not the expander.
func _open_the_submenu(m: Win98Menu) -> Win98Menu:
	m.selected_index = 1
	m._open_submenu(1, m.menu_items[1])
	var sub: Win98Menu = m.submenu
	assert_not_null(sub, "PRECONDITION: the Abilities submenu opened")
	for i in range(5):
		await get_tree().process_frame
	if sub:
		sub._can_accept_input = true
	return sub


func after_each() -> void:
	Win98Menu._defer_axis_held = false
	Win98Menu._advance_axis_held = false


## CONTROL: with no submenu, holding commits. If this fails the harness is wrong, not the fix.
func test_control_holding_defer_commits_the_queue() -> void:
	var m := await _root_with_two_queued()
	assert_eq(m.get_queue_count(), 2, "CONTROL: two actions queued before the hold")
	var got: Array = []
	m.actions_submitted.connect(func(a): got.append(a))
	await _hold_defer(m)
	assert_eq(got.size(), 1, "CONTROL: holding defer with no submenu open must commit the queue")


func test_holding_defer_commits_with_a_submenu_open() -> void:
	var m := await _root_with_two_queued()
	var sub := await _open_the_submenu(m)
	assert_true(m._nav_is_blocked(),
		"PRECONDITION: an open submenu blocks the root's navigation — the state the bug needs")
	var got: Array = []
	m.actions_submitted.connect(func(a): got.append(a))
	await _hold_defer(sub)
	assert_true(got.size() == 1 or (is_instance_valid(m.submenu) and m._nav_is_blocked()),
		"PRECONDITION: the submenu stayed open through the hold — else a pass here proves nothing")
	assert_eq(got.size(), 1,
		"holding defer with a submenu open must commit the queue — it did nothing, which is the report")
	if got.size() == 1:
		assert_eq(got[0].size(), 2, "and commit EXACTLY the two queued, adding nothing")
	if is_instance_valid(sub):
		sub.queue_free()


## A TAP is still Undo with a submenu open — the fix must not turn every press into a commit.
func test_a_tap_with_a_submenu_open_still_undoes() -> void:
	var m := await _root_with_two_queued()
	var sub := await _open_the_submenu(m)
	var got: Array = []
	m.actions_submitted.connect(func(a): got.append(a))
	Win98Menu._defer_axis_held = false
	sub._input(_defer_event(true))
	sub._input(_defer_event(false))
	await get_tree().create_timer(Win98Menu.L_HOLD_CONFIRM_TIME + 0.35).timeout
	assert_eq(got.size(), 0, "a tap must not commit")
	assert_eq(m.get_queue_count(), 1, "a tap undoes the last queued action: two became one")
	if is_instance_valid(sub):
		sub.queue_free()
