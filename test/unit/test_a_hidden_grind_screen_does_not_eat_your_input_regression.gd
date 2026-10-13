extends GutTest
## AutogrindMonitor gates its _input on `visible` — its OWN flag. The screen is add_child'd to
## AutogrindUI, which sets `visible = false` for the WHOLE grind (AutogrindUI:2518, :2543), so the
## monitor's own flag stays true while nothing is on screen: measured, a child of a hidden parent
## reports visible == true and is_visible_in_tree() == false.
## Reachable: the Tier-1 Dashboard's "Adjust Rules" -> GameLoop:7707 -> open_rules_editor(), whose
## editor.closed callback ends `elif _is_grinding: _show_monitor()`. The editor is deliberately
## parented to AutogrindUI's PARENT to dodge exactly this (its comment at :3211 says so); the
## monitor is the one screen still inside the hidden node.
## So after adjusting rules mid-grind, a screen the player cannot see was emitting pause / exit /
## tier_cycle from their button presses, beside the Dashboard that is actually on screen.
const MonitorScript = preload("res://src/ui/autogrind/AutogrindMonitor.gd")

var _parent: Control
var _monitor: Control
var _fired: Array[String] = []


func before_each() -> void:
	_fired = []
	_parent = Control.new()
	add_child_autofree(_parent)
	_monitor = MonitorScript.new()
	_parent.add_child(_monitor)
	_monitor.visible = true
	for sig in ["pause_requested", "exit_requested", "tier_cycle_requested"]:
		if _monitor.has_signal(sig):
			_monitor.connect(sig, func(): _fired.append(sig))


func after_each() -> void:
	if is_instance_valid(_monitor):
		_monitor.queue_free()


func _press(keycode: int) -> void:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.pressed = true
	_monitor._input(ev)


func test_a_screen_hidden_by_its_parent_ignores_input() -> void:
	_parent.visible = false
	await wait_frames(2)
	assert_true(_monitor.visible, "FLOOR: the monitor's OWN flag is still true -- that is the trap")
	assert_false(_monitor.is_visible_in_tree(), "FLOOR: and it is not on screen")
	_press(KEY_P)
	assert_eq(_fired, [], "a screen the player cannot see must not act on their button press")


## CONTROL: the guard must not simply refuse everything, or the arm above passes on a dead handler.
func test_a_visible_screen_still_acts() -> void:
	_parent.visible = true
	await wait_frames(2)
	assert_true(_monitor.is_visible_in_tree(), "FLOOR: this arm needs the screen actually on screen")
	_press(KEY_P)
	assert_eq(_fired, ["pause_requested"], "CONTROL: when it IS on screen the press must still work")


## CONTROL: its own flag must still gate it, so hiding the monitor directly keeps working.
func test_hiding_the_screen_itself_still_gates() -> void:
	_parent.visible = true
	_monitor.visible = false
	await wait_frames(2)
	_press(KEY_P)
	assert_eq(_fired, [], "CONTROL: the direct hide that already worked must keep working")
