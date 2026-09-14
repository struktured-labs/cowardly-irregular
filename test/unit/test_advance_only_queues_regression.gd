extends GutTest

## ⛔ ADVANCE ALSO COMMITTED, AND CONFIRM AT A FULL QUEUE SILENTLY DROPPED AN ACTION.
##
## Work order 2026-09-14, the Advance / 5-action system. Two defects in one path:
##
##   1. Win98Menu._handle_advance_input submitted once the queue reached max-1, so the R press on
##      the last slot queued AND ended the turn. There was no way to fill the queue and then look
##      at it. Advance now ONLY queues; a full queue refuses with a deny cue and a readout shake.
##
##   2. Confirm always went through _submit_actions, which appends the HIGHLIGHTED item. At a full
##      queue that is one past the limit, and BattleManager._apply_full_bank_rule sliced the
##      overflow off without a word — the turn that resolved was not the one on screen. At a full
##      queue Confirm now commits EXACTLY the queue.
##
## advance_commits_at_limit (GameState + settings.json + a Settings row, default OFF) restores (1)
## for anyone who wants Advance and Confirm on one button.
##
## It also carries the contract battle builds its aura on: root queue_changed(count, max_size),
## sent after every mutation and with 0 BEFORE the submit signals — never after, because those
## dispatch turn end and the next PC's menu can exist before control returns.

const WIN98 := "res://src/ui/Win98Menu.gd"
const GdSource := preload("res://test/unit/helpers/gd_source.gd")

var _saved_setting: bool = false


func before_each() -> void:
	_saved_setting = bool(GameState.advance_commits_at_limit)
	GameState.advance_commits_at_limit = false


func after_each() -> void:
	GameState.advance_commits_at_limit = _saved_setting


func _items() -> Array:
	return [
		{"id": "attack", "label": "Attack"},
		{"id": "guard", "label": "Guard"},
		{"id": "item", "label": "Item"},
	]


func _menu(max_size: int = 4, expand_left: bool = false):
	var m = load(WIN98).new()
	m.is_root_menu = true
	m.battle_mode = true
	m.expand_left = expand_left
	add_child_autofree(m)
	m.setup("Command", _items(), Vector2(10, 10), "fighter")
	m._can_accept_input = true
	m.selected_index = 0
	m.set_max_queue_size(max_size)
	return m


## Record every signal the root emits, in ORDER, so arms can assert sequence and not just totals.
func _record(m) -> Array:
	var log: Array = []
	m.queue_changed.connect(func(c, mx): log.append(["qc", c, mx]))
	m.actions_submitted.connect(func(a): log.append(["submitted", a.size(), a]))
	m.item_selected.connect(func(id, _d): log.append(["selected", id]))
	return log


## One Advance press. The debounce is a static, so it is cleared before EVERY press — without this
## the second press in the same millisecond is ignored and every count below is wrong.
func _advance(m) -> void:
	Win98Menu._last_advance_ms = -1000000
	m._handle_advance_input()


func _press(m, action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	m._input(ev)


func _submits(log: Array) -> Array:
	return log.filter(func(e): return e[0] == "submitted" or e[0] == "selected")


## ⛔ DEFECT 1. The press that fills the queue must not commit it.
func test_advance_only_queues_it_never_commits() -> void:
	var m = _menu(4)
	var log := _record(m)
	for i in range(4):
		_advance(m)
	assert_eq(m.get_queue_count(), 4, "four Advance presses must queue four actions")
	assert_eq(_submits(log).size(), 0,
		"the 4th press used to queue AND end the turn — Advance must only ever queue")


## A full queue refuses, and the refusal is not a mutation.
func test_advance_at_a_full_queue_is_refused_and_says_so() -> void:
	var bar := Control.new()
	bar.name = "InputHintBar"
	var hint := Label.new()
	hint.name = "HintLabel"
	bar.add_child(hint)
	add_child_autofree(bar)
	var m = _menu(4)
	for i in range(4):
		_advance(m)
	var log := _record(m)
	_advance(m)
	assert_eq(m.get_queue_count(), 4, "a 5th press at max 4 must not grow the queue")
	assert_eq(_submits(log).size(), 0, "…and must not commit it either")
	assert_eq(log.filter(func(e): return e[0] == "qc").size(), 0,
		"a refusal changes nothing, so it must not emit queue_changed — battle would redraw for nothing")
	assert_true(hint.text.find("Queue full") > -1,
		"the refusal must SAY why, or it reads as a dead button: got '%s'" % hint.text)


## THE OTHER DIRECTION: the setting restores the old one-button behaviour exactly.
func test_the_setting_restores_commit_at_the_limit() -> void:
	GameState.advance_commits_at_limit = true
	var m = _menu(4)
	var log := _record(m)
	for i in range(3):
		_advance(m)
	assert_eq(_submits(log).size(), 0, "with the setting ON the first three presses still only queue")
	_advance(m)
	var sub := _submits(log)
	assert_eq(sub.size(), 1, "with the setting ON the press that fills the queue commits it")
	if sub.size() == 1:
		assert_eq(sub[0][1], 4, "…as the full four actions")


## ⛔ DEFECT 2. Confirm at a full queue commits exactly the queue, not the queue plus the highlight.
func test_confirm_at_a_full_queue_commits_exactly_the_queue() -> void:
	var m = _menu(4)
	for i in range(4):
		_advance(m)
	m.selected_index = 1  # a DIFFERENT item highlighted — the one that used to be appended
	var log := _record(m)
	_press(m, "ui_accept")
	var sub := _submits(log)
	assert_eq(sub.size(), 1, "Confirm at a full queue must commit")
	if sub.size() != 1:
		return
	assert_eq(sub[0][1], 4,
		"exactly the four queued — it used to send five and BattleManager silently dropped one")
	for a in sub[0][2]:
		assert_ne(a.id, "guard", "the highlighted item must NOT ride along with a full queue")


## The d-pad-left confirm on a left-expanding menu is the same commit — the battle menu expands left.
func test_dpad_left_confirm_commits_exactly_the_queue_too() -> void:
	var m = _menu(4, true)
	for i in range(4):
		_advance(m)
	m.selected_index = 1
	var log := _record(m)
	_press(m, "ui_left")
	var sub := _submits(log)
	assert_eq(sub.size(), 1, "d-pad left must commit a full queue on a left-expanding menu")
	if sub.size() == 1:
		assert_eq(sub[0][1], 4, "…as exactly the queue")


## THE OTHER DIRECTION: below full, Confirm still adds the highlighted item — that is what it is for.
func test_confirm_below_full_still_adds_the_highlighted_item() -> void:
	var m = _menu(4)
	_advance(m)
	_advance(m)
	m.selected_index = 1
	var log := _record(m)
	_press(m, "ui_accept")
	var sub := _submits(log)
	assert_eq(sub.size(), 1, "Confirm below full must commit")
	if sub.size() == 1:
		assert_eq(sub[0][1], 3, "two queued plus the highlighted one")
		assert_eq(sub[0][2][2].id, "guard", "…and the added one is the item on screen")


## ⛔ The CONTRACT battle builds on: every mutation, and 0 before the submit signals.
func test_queue_changed_reports_every_mutation_and_zero_before_commit() -> void:
	var m = _menu(4)
	var log := _record(m)
	_advance(m)
	_advance(m)
	m._undo_last_action()
	m._cancel_all_queued()
	_advance(m)
	_press(m, "ui_accept")
	var counts: Array = log.filter(func(e): return e[0] == "qc").map(func(e): return e[1])
	assert_eq(counts, [1, 2, 1, 0, 1, 0],
		"queue, queue, undo, cancel-all, queue, commit — one emit each, in order")
	for e in log.filter(func(e): return e[0] == "qc"):
		assert_eq(e[2], 4, "max_size must ride along on every emit")
	var zero_at := -1
	var submit_at := -1
	for i in range(log.size()):
		if log[i][0] == "qc" and log[i][1] == 0 and zero_at < 0 and i > 3:
			zero_at = i
		if log[i][0] == "submitted" or log[i][0] == "selected":
			submit_at = i
	assert_gt(submit_at, -1, "CONTROL: the commit must actually have been observed")
	assert_lt(zero_at, submit_at,
		"the 0 must arrive BEFORE the submit signal — after it, the next PC's menu can already exist " +
		"and a late 0 would clear the wrong actor's aura")


## Close owes battle a 0 only once — a commit already paid it.
func test_close_mid_queue_emits_zero_and_commit_does_not_double_it() -> void:
	var open = _menu(4)
	var log_a := _record(open)
	_advance(open)
	_advance(open)
	open.force_close()
	assert_eq(log_a.filter(func(e): return e[0] == "qc" and e[1] == 0).size(), 1,
		"a menu closed with actions queued must still send its 0")

	var committed = _menu(4)
	var log_b := _record(committed)
	_advance(committed)
	_press(committed, "ui_accept")
	assert_eq(log_b.filter(func(e): return e[0] == "qc" and e[1] == 0).size(), 1,
		"commit sends 0 and then closes — the close must not send a second one")


## At a full bank the fifth action is reachable by Advance alone — refusing must not delete it.
func test_the_full_bank_fifth_action_is_reachable_by_advance() -> void:
	var m = _menu(5)  # BattleCommandMenu sets FULL_BANK_ACTIONS at +4 AP
	for i in range(5):
		_advance(m)
	assert_eq(m.get_queue_count(), 5, "all five must queue at a full bank")
	_advance(m)
	assert_eq(m.get_queue_count(), 5, "…and only the sixth is refused")


## The hint bar must not advertise "Add" when Confirm no longer adds.
func test_the_hint_bar_says_commit_not_add_when_full() -> void:
	var bar := Control.new()
	bar.name = "InputHintBar"
	var hint := Label.new()
	hint.name = "HintLabel"
	bar.add_child(hint)
	add_child_autofree(bar)
	var m = _menu(4)
	_advance(m)
	assert_true(hint.text.find("Add+Commit") > -1, "CONTROL: below full the bar still says Add+Commit")
	for i in range(3):
		_advance(m)
	assert_eq(hint.text.find("Add+Commit"), -1, "at full, Confirm commits exactly the queue — no 'Add'")
	assert_true(hint.text.find("Commit") > -1, "…and it must still name the commit: '%s'" % hint.text)


## ⛔ The refusal message must hand back to the QUEUE, not to the empty-queue legend. Measured before
## the fix: 5/5 queued, a refused press, one move — and the bar read "[L] Defer · [R] Advance · …",
## telling the player they had nothing queued with a full turn loaded.
func test_moving_after_a_refusal_restores_the_queue_not_the_empty_legend() -> void:
	var bar := Control.new()
	bar.name = "InputHintBar"
	var hint := Label.new()
	hint.name = "HintLabel"
	bar.add_child(hint)
	add_child_autofree(bar)
	var m = _menu(4)
	for i in range(4):
		_advance(m)
	_advance(m)
	assert_true(hint.text.find("Queue full") > -1, "CONTROL: the refusal must be showing first")
	_press(m, "ui_down")
	assert_eq(hint.text.find("Queue full"), -1, "…and a move must clear it")
	assert_true(hint.text.find("queued 4/4") > -1,
		"the bar must come back to the QUEUE — the empty legend here says nothing is queued: '%s'" % hint.text)


## The only tutorial that teaches Advance must mention the fifth action and the new commit button.
func test_the_tutorial_teaches_the_fifth_action_and_confirm() -> void:
	var body: String = str(TutorialHints.HINTS["advance_defer"]["body"])
	assert_true(body.find("5 at a full bank") > -1,
		"the aura shows a 5th slot — the tutorial must not say the queue stops at 4: '%s'" % body)
	assert_true(body.find("{confirm}") > -1,
		"Confirm is now the commit, named through the derived {confirm} token, never a letter")


## Default OFF, persisted through settings.json. Read from stripped function BODIES, not raw source,
## because exercising it for real would write user://settings.json.
func test_the_setting_defaults_off_and_persists() -> void:
	var fresh = load("res://src/meta/GameState.gd").new()
	assert_false(bool(fresh.advance_commits_at_limit), "the new default must be OFF")
	fresh.free()
	var src := GdSource.code_of("res://src/save/SaveSystem.gd")
	var save_body := _func_body(src, "func save_settings")
	var load_body := _func_body(src, "func load_settings")
	## ⛔ NON-EMPTY, asserted. load_settings is the LAST function in SaveSystem.gd, so there is no
	## following func and find() returns -1 — which made substr() return "" and read as "the wiring
	## is missing". A Python check of the same logic hid it: code[at:-1] slices to the end.
	assert_gt(save_body.length(), 100, "POSITIVE CONTROL: save_settings body must be read")
	assert_gt(load_body.length(), 100, "POSITIVE CONTROL: load_settings body must be read — it is the last func")
	assert_true(save_body.find('settings["advance_commits_at_limit"] = GameState.advance_commits_at_limit') > -1,
		"save_settings must write the setting")
	assert_true(load_body.find("GameState.advance_commits_at_limit = bool(settings[\"advance_commits_at_limit\"])") > -1,
		"load_settings must read it back")


## A function body bounded by the next top-level func, or by end of file when it is the last one.
func _func_body(src: String, header: String) -> String:
	var at := src.find(header)
	if at < 0:
		return ""
	var stop := src.find("\nfunc ", at + header.length())
	return src.substr(at, stop - at) if stop > at else src.substr(at)
