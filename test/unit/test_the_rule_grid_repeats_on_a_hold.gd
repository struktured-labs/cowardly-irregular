extends GutTest

## struktured 2026-08-22 asked for hold-to-repeat in menus. It reached SIX of the thirty menus that
## carry a cursor, and the autobattle grid was not one — while being the only long list in the game
## with NO fast route at all:
##
##     EquipmentMenu          windowed · no paging · HAS hold-to-repeat  (added Aug for this reason)
##     Abilities/Items/Job/QuestLog   windowed · page · no hold-to-repeat
##     AutobattleGridEditor   windowed · MAX_RULES = 32 · no paging · NO hold-to-repeat
##
## It cannot page — both shoulders add a condition and an action — so one row per press was the
## whole vocabulary for a 32-row list. Hold-to-repeat needs no shoulders: MenuRepeat polls
## ui_up/ui_down, which is exactly why it is available here and paging is not.
##
## ⛔ THE LOAD-BEARING HALF IS THE REFUSAL, NOT THE WALK. MenuRepeat polls Input directly and
## inherits NONE of _input's early returns — Win98Menu measured a 2s hold stepping the parent 22
## times behind an open submenu. This editor has EIGHT gates before row navigation, so the hold
## path consults one shared `_row_nav_blocked()` rather than a second copy of the list.

const GridScript = preload("res://src/ui/autobattle/AutobattleGridEditor.gd")
const SRC := "res://src/ui/autobattle/AutobattleGridEditor.gd"

## Past MenuRepeat.INITIAL_DELAY, so one tick arms the hold and the next fires.
const PAST_DELAY := 0.5


func after_each() -> void:
	Input.action_release("ui_up")
	Input.action_release("ui_down")


func _editor(rule_count: int = 20) -> Node:
	var ed: Node = GridScript.new()
	add_child_autofree(ed)
	var rules: Array = ed.get("rules")
	for i in range(rule_count):
		rules.append({"conditions": [], "actions": []})
	ed.set("cursor_row", 0)
	ed.visible = true
	return ed


func _hold(ed: Node, action: String, ticks: int = 3) -> int:
	var before: int = int(ed.get("cursor_row"))
	Input.action_press(action, 1.0)
	for i in range(ticks):
		ed._process(PAST_DELAY)
	Input.action_release(action)
	return int(ed.get("cursor_row")) - before


## ⛔ EXISTENCE FIRST. Every arm below calls _process and _row_nav_blocked directly; if either were
## removed those calls abort BEFORE their first assert, GUT scores Risky, and Risky is not Failing.
func test_the_hold_mechanism_exists() -> void:
	var ed := _editor()
	assert_true(ed.has_method("_process"), "no _process — the arms here would go Risky, not red")
	assert_true(ed.has_method("_nav_step_row"), "the shared row-step owner must exist by that name")
	assert_true(ed.has_method("_row_nav_blocked"), "the shared refusal must exist by that name")


func test_holding_down_walks_the_grid() -> void:
	var ed := _editor(20)
	assert_gt(_hold(ed, "ui_down"), 0,
		"a held direction must step the grid on its own — 32 rules at one row per press, with no "
		+ "page jump, is the walk this exists to shorten")


func test_holding_up_walks_the_other_way() -> void:
	var ed := _editor(20)
	ed.set("cursor_row", 10)
	assert_lt(_hold(ed, "ui_up"), 0, "a held up must step backwards")


func test_the_hold_clamps_at_the_ends() -> void:
	var ed := _editor(5)
	ed.set("cursor_row", 0)
	_hold(ed, "ui_up", 6)
	assert_eq(int(ed.get("cursor_row")), 0, "a hold at the top must not run negative")
	_hold(ed, "ui_down", 30)
	assert_eq(int(ed.get("cursor_row")), 4, "a hold at the bottom must clamp to the last rule")


## THE LOAD-BEARING ARM. Each state the press path refuses, the hold path must refuse too — and the
## control proves the fixture can move at all, so a still cursor means refusal rather than a dead
## fixture. Gates DERIVED from _row_nav_blocked's own source, so a ninth gate is covered here
## without editing this list.
func test_a_hold_refuses_every_state_the_press_path_refuses() -> void:
	var live := _editor(20)
	assert_gt(_hold(live, "ui_down"), 0,
		"CONTROL: an unblocked editor must move under a hold, or every refusal below is vacuous")

	var body := _blocker_body()
	assert_ne(body, "", "_row_nav_blocked must be readable as source")
	for member in ["_keyboard", "_share_picker", "_option_picker", "_simulate_panel",
			"_rule_composer_overlay"]:
		assert_true(body.contains(member), "%s must be one of the refusals" % member)
		var ed := _editor(20)
		var blocker := Control.new()
		add_child_autofree(blocker)
		blocker.visible = true
		ed.set(member, blocker)
		assert_eq(_hold(ed, "ui_down"), 0,
			"a hold stepped the grid with %s open — the press path refuses it and the poll did not" % member)

	for flag in ["is_editing", "_portrait_focused"]:
		assert_true(body.contains(flag), "%s must be one of the refusals" % flag)
		var ed2 := _editor(20)
		ed2.set(flag, true)
		assert_eq(_hold(ed2, "ui_down"), 0,
			"a hold stepped the grid while %s — the press path refuses it and the poll did not" % flag)


## The press path and the hold path must gate on the SAME members. A gate added to _input and not to
## the blocker is the drift this file exists to prevent, and it is invisible to every behavioural arm.
func test_control_both_paths_gate_on_the_same_members() -> void:
	var src := FileAccess.get_file_as_string(SRC)
	assert_ne(src, "", "the editor must be readable as source")
	var body := _blocker_body()
	var missing: Array = []
	for member in ["_keyboard", "_share_picker", "_option_picker", "_simulate_panel",
			"_rule_composer_overlay", "is_editing", "_portrait_focused"]:
		if not body.contains(member):
			missing.append(member)
	assert_eq(missing, [],
		"_input gates row navigation on these and _row_nav_blocked does not, so a HELD direction "
		+ "walks the grid in a state a PRESS refuses: %s" % [missing])


func _blocker_body() -> String:
	var src := FileAccess.get_file_as_string(SRC)
	var at := src.find("func _row_nav_blocked")
	if at < 0:
		return ""
	var end := src.find("\nfunc ", at + 1)
	return src.substr(at, (end - at) if end > -1 else 1200)
