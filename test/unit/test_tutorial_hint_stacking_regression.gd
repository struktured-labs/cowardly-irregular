extends GutTest

## Regression: render smoke 2026-07-31 — battle_smoke.png showed a tutorial panel with
## faded text behind it and "Press any button to dismiss" drawn twice. BattleScene fires
## first_battle (2389) and first_boss (2391) on consecutive lines with no await, so on a
## first-ever boss fight both were unseen and BOTH rendered, stacked. TutorialHints.show()
## guarded only on ALREADY-SEEN hints, never on one currently on screen.
##
## Contract pinned here:
##   1. A second show() while a hint is active does NOT present a second panel.
##   2. The deferred hint is NOT marked seen — show_hint marks before it draws, so
##      dropping it outright would lose the content permanently.
##   3. Dismissing the active hint replays the deferred one.
##   4. CONTROL: with nothing active, show() presents immediately — proves these
##      assertions can fail, rather than a guard that blocks everything scoring green.

const A := "first_battle"
const B := "first_boss"


func _reset() -> void:
	TutorialHint._shown_hints.erase(A)
	TutorialHint._shown_hints.erase(B)
	TutorialHint._active_count = 0
	TutorialHints._pending.clear()
	if GameState:
		GameState.game_constants.erase("tutorial_" + A)
		GameState.game_constants.erase("tutorial_" + B)


func before_each() -> void:
	_reset()


func after_each() -> void:
	_reset()


func _visible_hints(parent: Node) -> Array:
	var out: Array = []
	for c in parent.get_children():
		if c is TutorialHint and c.visible and not c.is_queued_for_deletion():
			out.append(c)
	return out


func _parent() -> Node:
	var parent := Node.new()
	add_child_autofree(parent)
	return parent


func test_control_single_hint_presents_immediately() -> void:
	var parent := _parent()
	TutorialHints.show(parent, A)
	assert_eq(TutorialHint._active_count, 1, "CONTROL: one show() with nothing active must present")
	assert_eq(_visible_hints(parent).size(), 1, "CONTROL: exactly one visible panel")


func test_second_hint_same_frame_does_not_stack() -> void:
	var parent := _parent()
	TutorialHints.show(parent, A)
	TutorialHints.show(parent, B)
	assert_eq(_visible_hints(parent).size(), 1,
		"first_battle + first_boss in one frame must not render two stacked panels")
	assert_eq(TutorialHint._active_count, 1, "only one hint may hold the input gate")
	assert_eq(TutorialHints._pending.size(), 1, "the second hint must be queued, not dropped")


func test_deferred_hint_is_not_marked_seen_while_queued() -> void:
	var parent := _parent()
	TutorialHints.show(parent, A)
	TutorialHints.show(parent, B)
	assert_false(TutorialHint._shown_hints.get(B, false),
		"a queued hint marked seen would be lost forever — show_hint marks BEFORE it draws")


func test_dismissing_active_hint_replays_the_deferred_one() -> void:
	var parent := _parent()
	TutorialHints.show(parent, A)
	TutorialHints.show(parent, B)
	var live: Array = _visible_hints(parent)
	assert_eq(live.size(), 1, "precondition: exactly one panel before dismissal")
	live[0]._dismiss()
	assert_eq(TutorialHints._pending.size(), 0, "queue must drain on dismissal")
	assert_eq(TutorialHint._active_count, 1, "the deferred hint must now be on screen")
	assert_true(TutorialHint._shown_hints.get(B, false),
		"and marked seen only now, having actually drawn")


func test_queue_drops_a_deferred_hint_whose_parent_died() -> void:
	var parent := _parent()
	var doomed := Node.new()
	add_child(doomed)
	TutorialHints.show(parent, A)
	TutorialHints.show(doomed, B)
	doomed.free()
	var live: Array = _visible_hints(parent)
	live[0]._dismiss()
	assert_eq(TutorialHints._pending.size(), 0, "a dead parent must be dropped, not re-parented")
	assert_eq(TutorialHint._active_count, 0, "and nothing may be presented for it")
