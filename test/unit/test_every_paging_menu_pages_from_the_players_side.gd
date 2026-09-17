extends GutTest

## One trigger pull must move each paging menu's cursor by exactly PAGE_ROWS — asked of the MENU,
## not of MenuPaging.
##
## ⛔ THE DEFECT THIS OWNS SHIPPED, AND EVERY EXISTING GUARD SAID IT WORKED. `page_delta` became a
## CONSUMING read when the analog latch landed; ten menus called it twice in one handler, so on a
## TRIGGER the branch was entered and the cursor moved `0 * PAGE_ROWS`. On a shoulder BUTTON both
## reads agree, because buttons are deliberately not latched — so the two routes anyone tests with
## kept working while the trigger route did nothing in ten menus at once.
##
## ⛔ WHY THE EXISTING ARMS COULD NOT SEE IT: they were about the HELPER, and the helper was
## correct. `test_a_page_delta_is_read_once_regression` owns the PROPERTY (the second read is
## consumed) at the call site; @cowir-music's jukebox file owns the CONSEQUENCE for one menu. This
## file is that consequence for the other seven, because a consequence arm is scoped to a ROUTE and
## a SURFACE, not to a feature (@cowir-autogrind's Advance-path finding, same evening).
##
## 🔑 EVERY ARM CARRIES A LIVENESS CONTROL, and that is measured rather than ceremonial: my first
## fixture filled `_row_nodes` for Bestiary and PartyChat, which gate on `_entries` and `_chats`.
## Both menus returned moved=0 — the fixture, not the menu. A cursor that does not move is
## ambiguous between "paging is broken" and "the handler early-returned", so each menu proves a
## plain d-pad step moves it by 1 BEFORE the page jump is asked about.

const RAMP := [0.35, 0.55, 0.75, 0.95]
const FILL := 40

## bound = the member the page jump is clamped against; fill = what must be non-empty to get past
## the handler's own early return. Menus with neither populate themselves headless.
const MENUS := [
	{"name": "AbilitiesMenu", "path": "res://src/ui/AbilitiesMenu.gd", "sel": "selected_index",
		"fill": {"_abilities_list": "dict"}},
	{"name": "BestiaryMenu", "path": "res://src/ui/BestiaryMenu.gd", "sel": "_selected",
		"fill": {"_entries": "dict", "_row_nodes": "node"}},
	{"name": "SettingsMenu", "path": "res://src/ui/SettingsMenu.gd", "sel": "selected_index",
		"fill": {}},
	{"name": "BossSelectorMenu", "path": "res://src/ui/BossSelectorMenu.gd", "sel": "selected_index",
		"fill": {}},
	{"name": "FastTravelMenu", "path": "res://src/ui/FastTravelMenu.gd", "sel": "_selected",
		"fill": {"_rows": "dict"}},
	{"name": "TeleportMenu", "path": "res://src/ui/TeleportMenu.gd", "sel": "_selected",
		"fill": {}},
	{"name": "CutsceneGallery", "path": "res://src/ui/CutsceneGallery.gd", "sel": "_selected_item_idx",
		"fill": {}},
	{"name": "PartyChatMenu", "path": "res://src/ui/PartyChatMenu.gd", "sel": "_selection",
		"fill": {"_chats": "dict", "_row_nodes": "node"}},
	{"name": "ItemsMenu", "path": "res://src/ui/ItemsMenu.gd", "sel": "selected_item_index",
		"fill": {"_item_list": "dict"}},
]


func after_each() -> void:
	_release()


func _motion(axis: int, value: float) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.axis = axis
	e.axis_value = value
	return e


## Clear the engine action state AND MenuPaging's static latch, which outlives any one menu.
func _release() -> void:
	Input.action_release("battle_defer")
	Input.action_release("battle_advance")
	Input.action_release("ui_down")
	for axis in [JOY_AXIS_TRIGGER_LEFT, JOY_AXIS_TRIGGER_RIGHT]:
		MenuPaging.page_delta(_motion(axis, 0.0))


## Resolved rather than assumed, and this is a DIAGNOSIS fix, not a hole being closed — measured
## both ways by renaming TeleportMenu's handler:
##
##     unhardened   EC=1, "every listed menu must reach the page assertion; 8 of 9 did"
##     hardened     EC=1, "TeleportMenu defines no input handler this arm can call"
##
## Both catch it. A GDScript error aborts its ENCLOSING FUNCTION ONLY, and the call sits inside
## _assert_live, so the abort kills the helper, which returns false, and the loop continues to the
## count floor. The sibling stick arm made the same call INLINE in the test body and therefore went
## silently green on the same shape. Same rung, opposite outcome, decided by where the call sits.
func _handler(m: Node) -> String:
	for h in ["_input", "_unhandled_input", "_gui_input"]:
		if m.has_method(h):
			return h
	return ""


func _send(m: Node, ev: InputEvent) -> void:
	m.call(_handler(m), ev)


func _row(i: int) -> Dictionary:
	return {"id": "probe_%d" % i, "name": "Probe %d" % i,
		"data": {"name": "Probe %d" % i, "type": "item", "category": 0, "mp_cost": 0}}


func _open(spec: Dictionary) -> Node:
	_release()
	var m: Node = load(spec["path"]).new()
	add_child_autofree(m)
	await get_tree().process_frame
	for member in spec["fill"]:
		var arr = m.get(member)
		if arr is Array:
			for i in range(FILL):
				if spec["fill"][member] == "node":
					var c := Control.new()
					add_child_autofree(c)
					arr.append(c)
				else:
					arr.append(_row(i))
	return m


## Proves the handler is REACHED and the fixture is sufficient. Without it a still cursor reads as
## a paging defect when it is an early return three lines above the paging branch.
func _assert_live(m: Node, spec: Dictionary) -> bool:
	assert_ne(_handler(m), "",
		"%s defines no input handler this arm can call — calling a nonexistent method aborts the "
		% spec["name"] + "test function and leaves every assert already run reporting green")
	var start: int = MenuPaging.PAGE_ROWS
	m.set(spec["sel"], start)
	var e := InputEventJoypadButton.new()
	e.button_index = JOY_BUTTON_DPAD_DOWN
	e.pressed = true
	Input.action_press("ui_down", 1.0)
	_send(m, e)
	Input.action_release("ui_down")
	var moved: int = absi(int(m.get(spec["sel"])) - start)
	assert_eq(moved, 1,
		"LIVENESS: %s did not step one row on a d-pad press — its handler early-returned or the "
		% spec["name"] + "fixture is short, so a still cursor below would not mean what it says")
	return moved == 1


func _pull(m: Node, action: String, axis: int) -> void:
	Input.action_press(action, 1.0)
	for v in RAMP:
		_send(m, _motion(axis, v))


func test_one_trigger_pull_moves_every_menu_exactly_one_page() -> void:
	var checked := 0
	for spec in MENUS:
		var m: Node = await _open(spec)
		if not _assert_live(m, spec):
			continue
		var start: int = MenuPaging.PAGE_ROWS * 2
		m.set(spec["sel"], start)
		_pull(m, "battle_advance", JOY_AXIS_TRIGGER_RIGHT)
		var moved: int = absi(int(m.get(spec["sel"])) - start)
		assert_eq(moved, MenuPaging.PAGE_ROWS,
			"%s moved %d rows on one trigger pull, not %d — a second read of page_delta returns 0 "
			% [spec["name"], moved, MenuPaging.PAGE_ROWS] + "on an axis, so the branch runs and pages nothing")
		checked += 1
	assert_eq(checked, MENUS.size(),
		"every listed menu must reach the page assertion; %d of %d did" % [checked, MENUS.size()])


func test_the_other_trigger_pages_the_other_way() -> void:
	for spec in MENUS:
		var m: Node = await _open(spec)
		if not _assert_live(m, spec):
			continue
		var start: int = MenuPaging.PAGE_ROWS * 2
		m.set(spec["sel"], start)
		_pull(m, "battle_defer", JOY_AXIS_TRIGGER_LEFT)
		var moved: int = absi(int(m.get(spec["sel"])) - start)
		assert_eq(moved, MenuPaging.PAGE_ROWS,
			"%s paged %d rows on the other trigger, not %d" % [spec["name"], moved, MenuPaging.PAGE_ROWS])


## CONTROL, and the reason the defect survived nine deploys: buttons are NOT latched, so both reads
## agree and this route worked throughout. A red HERE is a new defect, not the one above.
func test_the_shoulder_button_route_was_never_broken() -> void:
	for spec in MENUS:
		var m: Node = await _open(spec)
		if not _assert_live(m, spec):
			continue
		var start: int = MenuPaging.PAGE_ROWS * 2
		m.set(spec["sel"], start)
		var e := InputEventJoypadButton.new()
		e.button_index = JOY_BUTTON_RIGHT_SHOULDER
		e.pressed = true
		Input.action_press("battle_advance", 1.0)
		_send(m, e)
		var moved: int = absi(int(m.get(spec["sel"])) - start)
		assert_eq(moved, MenuPaging.PAGE_ROWS,
			"%s paged %d rows on the shoulder button, not %d — this route was never broken, so a "
			% [spec["name"], moved, MenuPaging.PAGE_ROWS] + "red here is a NEW defect")
