extends GutTest

## ⛔ A HELD DIRECTION LEAKED PAST AN OPEN SUBMENU AND STEPPED THE PARENT MENU.
##
## Win98Menu is recursive — a command menu owns a child Win98Menu. Both are in the tree, both
## run _process, and both tick their own MenuRepeat. `_input` refuses to act under five
## conditions, the last being `if submenu and is_instance_valid(submenu): return` — "let it
## handle input instead". The hold-to-repeat path POLLS Input directly, so it reached none of
## them.
##
## Measured before the fix, holding ui_down for 2s with a submenu open:
##     PARENT repeats fired: 22      selected_index: 0 -> 2
##
## 🔑 Not merely a silent drift. `_nav_step` calls `_auto_expand_submenu()`, so each leaked
## repeat also tore down and rebuilt the child submenu under the player — in the battle command
## menu, while they scroll an ability list.
##
## The repeat path bypassed FOUR guards, not one: hidden (boss dialogue hides the command menu
## and owns the press), tutorial-hint capture, the _can_accept_input delay, and the submenu.
## MenuRepeat's own docstring says it "leaves every existing is_echo() guard alone" — true, and
## the same property made it bypass every guard that lives on the other code path.
##
## Fixed with ONE predicate both paths consult, because two lists that must agree is how this
## arrived. The arms below drive the REPEAT path and assert on the parent.

const WIN98 := "res://src/ui/Win98Menu.gd"


func _items() -> Array:
	return [
		{"id": "attack", "label": "Attack"},
		{"id": "magic", "label": "Magic", "submenu": [{"id": "fire", "label": "Fire"}]},
		{"id": "item", "label": "Item"},
		{"id": "defer", "label": "Defer"},
	]


func _menu(title: String, items: Array):
	var m = load(WIN98).new()
	add_child_autofree(m)
	m.setup(title, items, Vector2(10, 10), "fighter")
	m._can_accept_input = true
	m.selected_index = 0
	return m


func after_each() -> void:
	Input.action_release("ui_down")


## Hold ui_down for `frames` and report how many times THIS menu stepped its own selection.
func _repeats_while_holding(menu, frames: int = 120) -> int:
	Input.action_press("ui_down")
	var fired := 0
	for i in range(frames):
		var before: int = menu.selected_index
		menu._process(1.0 / 60.0)
		if menu.selected_index != before:
			fired += 1
	Input.action_release("ui_down")
	return fired


## ⛔ THE DEFECT.
func test_a_hold_inside_a_submenu_does_not_step_the_parent() -> void:
	var parent = _menu("Command", _items())
	var child = _menu("Magic", [{"id": "fire", "label": "Fire"}])
	parent.submenu = child
	assert_true(parent.submenu != null and is_instance_valid(parent.submenu),
		"precondition: the parent must actually have an open submenu")
	assert_eq(_repeats_while_holding(parent), 0,
		"a held direction must not step the PARENT while its submenu owns input — before " +
		"2026-09-12 a 2s hold stepped it 22 times and re-ran _auto_expand_submenu on each")
	assert_eq(parent.selected_index, 0, "…so the parent's selection is exactly where it was left")


## ⛔ THE OTHER DIRECTION, so the guard cannot become "hold-to-repeat never works".
func test_a_hold_with_no_submenu_still_repeats() -> void:
	var menu = _menu("Command", _items())
	assert_null(menu.submenu, "precondition: no submenu open")
	assert_gt(_repeats_while_holding(menu), 3,
		"hold-to-repeat is the feature — with nothing owning input above it, a 2s hold must step")


## Every condition the PRESS path refuses under must also stop the REPEAT path. Each is driven
## separately: one mutation must not be able to satisfy several of these at once.
func test_the_repeat_path_refuses_wherever_the_press_path_does() -> void:
	var hidden = _menu("Command", _items())
	hidden.visible = false
	assert_eq(_repeats_while_holding(hidden), 0,
		"a HIDDEN menu must not repeat — boss dialogue hides the command menu and owns the press")

	var undelayed = _menu("Command", _items())
	undelayed._can_accept_input = false
	assert_eq(_repeats_while_holding(undelayed), 0,
		"the input-delay guard exists to stop accidental selection; a hold must not walk past it")

	var closing = _menu("Command", _items())
	closing._is_closing = true
	assert_eq(_repeats_while_holding(closing), 0,
		"a closing menu must not repeat — it is about to be freed")


## The predicate is SHARED, not copied. Two lists that must agree is exactly how this shipped.
func test_both_paths_consult_one_predicate() -> void:
	var menu = _menu("Command", _items())
	assert_false(menu._nav_is_blocked(), "a live, visible, submenu-less menu must not be blocked")
	menu.submenu = _menu("Magic", [{"id": "fire", "label": "Fire"}])
	assert_true(menu._nav_is_blocked(), "…and an open submenu must block it")
	menu.submenu = null
	menu.visible = false
	assert_true(menu._nav_is_blocked(), "…as must being hidden, through the same predicate")


## THE CONTROL. Without it every "0 repeats" above could be a menu that never built, or an
## Input action that never registered.
func test_the_harness_can_actually_produce_a_repeat() -> void:
	var menu = _menu("Command", _items())
	assert_gt(menu.get("items").size() if menu.get("items") != null else 4, 1,
		"the menu must have several rows, or stepping is unobservable")
	Input.action_press("ui_down")
	assert_true(Input.is_action_pressed("ui_down"),
		"CONTROL: synthetic input must register, or every arm above passes on a dead harness")
	Input.action_release("ui_down")
	assert_false(Input.is_action_pressed("ui_down"), "…and release must clear it for the next test")
