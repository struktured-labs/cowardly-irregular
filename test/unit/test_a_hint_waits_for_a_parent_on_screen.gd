extends GutTest

## The .780 gate logged "Invalid assignment of 'text' … on Nil" at TutorialHint.show_hint: a hint presented to a parent
## outside the tree never ran _ready, so its labels did not exist, and show_hint had already marked it seen, so the hint
## was lost for good (cowir-main 22814/22815; the bare scene in test_formation_advance_does_not_corrupt_the_queue).

const HINT := "spotlight_locked_intro"


func before_each() -> void:
	_forget()


func after_each() -> void:
	_forget()


func _forget() -> void:
	TutorialHint._shown_hints.erase(HINT)
	GameState.game_constants.erase("tutorial_" + HINT)


func _hints_under(n: Node) -> Array:
	var out: Array = []
	for c in n.get_children():
		if c is TutorialHint:
			out.append(c)
	return out


func test_the_hint_exists_in_the_catalog() -> void:
	assert_true(TutorialHints.HINTS.has(HINT), "CONTROL: the hint this file shows is still in the catalog")


func test_a_detached_parent_gets_no_hint_and_loses_none() -> void:
	var detached := Node.new()
	autofree(detached)
	TutorialHints.show(detached, HINT)
	assert_eq(_hints_under(detached).size(), 0, "no hint is built under a parent that is not on screen")
	assert_false(TutorialHint._shown_hints.has(HINT), "and the hint is not consumed, so a later trigger still shows it")
	assert_false(GameState.game_constants.get("tutorial_" + HINT, false), "nor marked seen in the save")


func test_a_parent_on_screen_still_shows_it() -> void:
	var host := Node.new()
	add_child_autofree(host)
	TutorialHints.show(host, HINT)
	var hints := _hints_under(host)
	assert_eq(hints.size(), 1, "CONTROL: a parent in the tree gets its hint")
	if hints.is_empty():
		return
	var h: TutorialHint = hints[0]
	assert_eq(h._title_label.text, str(TutorialHints.HINTS[HINT]["title"]), "and the hint was built and filled")
	assert_true(TutorialHint._shown_hints.get(HINT, false), "and is marked seen once shown")
	h.queue_free()
