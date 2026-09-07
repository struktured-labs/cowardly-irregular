extends GutTest

## struktured 2026-09-06: "when I default with L2 it seems like it accidentally defaults the
## next player to act as well too easily" — turbo was OFF (settings checked), so this was real.
##
## Mechanism: battle_defer is bound to the L2 ANALOG AXIS (axis 4, deadzone 0.5). An analog
## ramp emits a BURST of is_action_pressed events with no echo flag. The 120ms debounce lived
## on the MENU INSTANCE — and defer destroys that instance, so PC2's fresh menu (debounce 0)
## accepted the tail of the same squeeze once its 80ms accept-gate opened. Fix: the debounce
## clocks are STATIC, plus a static release-edge gate that only counts the FIRST press until
## a genuine release (self-healed by _process when the release lands between menus).

const SRC := "res://src/ui/Win98Menu.gd"


func test_debounce_clocks_are_static_so_they_survive_the_menu_swap() -> void:
	var saved_defer := Win98Menu._last_defer_ms
	var saved_advance := Win98Menu._last_advance_ms
	var a := Win98Menu.new()
	var b := Win98Menu.new()
	Win98Menu._last_defer_ms = 123456
	assert_eq(a._last_defer_ms, 123456, "instance a must read the shared clock")
	assert_eq(b._last_defer_ms, 123456,
		"instance b (the NEXT member's menu) must see PC1's defer timestamp — the bug was that it started at 0")
	a.free()
	b.free()
	Win98Menu._last_defer_ms = saved_defer
	Win98Menu._last_advance_ms = saved_advance


func test_source_declares_the_clocks_static() -> void:
	# The behavioral test above passes even for instance vars IF both instances happen to share
	# defaults — the declaration is the load-bearing word.
	var src := FileAccess.get_file_as_string(SRC)
	assert_gt(src.length(), 5000, "CONTROL: read a real file")
	assert_true(src.contains("static var _last_defer_ms"), "defer clock must be static")
	assert_true(src.contains("static var _last_advance_ms"), "advance clock must be static")
	assert_true(src.contains("static var _defer_axis_held"), "the release-edge gate must be static")


func test_press_branch_gates_on_the_release_edge() -> void:
	var src := FileAccess.get_file_as_string(SRC)
	var i: int = src.find('event.is_action_pressed("battle_defer") and not event.is_echo()')
	assert_gt(i, -1, "the defer press branch must exist WITH the echo guard (keyboard L auto-repeat)")
	var window: String = src.substr(i, 400)
	assert_true(window.contains("_defer_axis_held"),
		"the press branch must consult the release-edge gate — an axis burst has no echo flag")
	var r: int = src.find('event.is_action_released("battle_defer")')
	assert_gt(r, -1, "CONTROL: the release branch must exist")
	assert_true(src.substr(r, 200).contains("_defer_axis_held = false"),
		"the release branch must clear the gate, or defer locks after one use")


func test_advance_has_the_same_release_edge_gate() -> void:
	# struktured 2026-09-06: "is that same issue possible with advancing too?" — yes, on the
	# 4th advance, which auto-submits and opens the NEXT member's menu. Same gate, same shape.
	var src := FileAccess.get_file_as_string(SRC)
	assert_true(src.contains("static var _advance_axis_held"), "advance needs its own static gate")
	var i: int = src.find('event.is_action_pressed("battle_advance") and not event.is_echo()')
	assert_gt(i, -1, "the advance press branch must carry the echo guard")
	assert_true(src.substr(i, 400).contains("_advance_axis_held"), "and consult the gate before handling")
	assert_true(src.contains('event.is_action_released("battle_advance")'), "a release branch must clear it")
	var p: int = src.find("func _process(")
	assert_true(src.substr(p, 700).contains('not Input.is_action_pressed("battle_advance")'),
		"and _process must self-heal it when the release lands between menus")


func test_gate_self_heals_when_release_lands_between_menus() -> void:
	var src := FileAccess.get_file_as_string(SRC)
	var i: int = src.find("func _process(")
	assert_gt(i, -1, "CONTROL: _process must exist")
	var e: int = src.find("\nfunc ", i + 1)
	var body: String = src.substr(i, e - i)
	assert_true(body.contains('not Input.is_action_pressed("battle_defer")'),
		"a release with no menu alive must not stick the gate — _process must poll it clear")
