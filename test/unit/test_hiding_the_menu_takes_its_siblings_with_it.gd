extends GutTest

## Found by rendering a battle frame and looking at it: a tooltip — "Run this character's autobattle
## script for this turn" — floating over the battlefield with NO command menu under it.
##
## Win98Menu builds three nodes as SIBLINGS rather than children, each added to `get_parent()` for
## draw order: `_tooltip_label` (:572), `_target_highlight` (:402) and `submenu` (:1345). None of
## them inherits the menu's `visible`. `set_command_menu_visible(false)` closed the submenu — its own
## comment says "Submenus are SIBLINGS of the root; hiding only the root left a live-battle ability
## list taking confirm" — and that fix stopped at the one sibling that had bitten someone. The other
## two were left on screen.
##
## Measured before the fix, driving the real menu: menu.visible=false, tooltip.visible=TRUE.
## Reachable on two ordinary paths, not just a smoke: `_show_boss_dialogue` hides the menu for boss
## speech, and opening the autobattle editor mid-battle hides it via GameLoop.

const SCENE := "res://src/battle/BattleScene.tscn"
const BattleState := preload("res://test/unit/helpers/battle_state.gd")
const SoundState := preload("res://test/unit/helpers/sound_state.gd")

var _guard: RefCounted = null


func before_each() -> void:
	_guard = BattleState.new()
	_guard.snapshot()


func after_each() -> void:
	if _guard != null:
		_guard.restore()


func after_all() -> void:
	SoundState.restore()


func _scene_with_menu() -> Array:
	var scene = load(SCENE).instantiate()
	add_child_autofree(scene)
	await wait_frames(6)
	if scene.party_members.is_empty():
		return [scene, null]
	scene._show_win98_command_menu(scene.party_members[0])
	await wait_frames(4)
	return [scene, scene.active_win98_menu]


## CONTROL: the tooltip really is a sibling. This is WHY visibility does not inherit, and without it
## the arms below read as an ordinary show/hide bug rather than the sibling class.
func test_control_the_tooltip_is_a_sibling_not_a_child() -> void:
	var pair: Array = await _scene_with_menu()
	var scene = pair[0]
	var menu = pair[1]
	assert_not_null(menu, "PRECONDITION: a command menu must spawn, or every arm here measures nothing")
	if menu == null:
		return
	menu._update_tooltip()
	await wait_frames(1)
	var tip = menu._tooltip_label
	assert_true(tip != null and is_instance_valid(tip), "PRECONDITION: the default row must carry a tooltip")
	if tip == null or not is_instance_valid(tip):
		return
	assert_ne(tip.get_parent(), menu,
		"the tooltip is added to the menu's PARENT for draw order, so it cannot inherit the menu's visibility")
	assert_eq(tip.get_parent(), scene, "and its parent is the scene, where it draws over the battlefield")


## The defect, through the real public entry point the boss-dialogue and editor paths both call.
func test_hiding_the_menu_takes_its_tooltip_with_it() -> void:
	var pair: Array = await _scene_with_menu()
	var scene = pair[0]
	var menu = pair[1]
	if menu == null:
		fail_test("PRECONDITION: no menu")
		return
	menu._update_tooltip()
	await wait_frames(1)
	var tip = menu._tooltip_label
	if tip == null or not is_instance_valid(tip):
		fail_test("PRECONDITION: no tooltip to lose")
		return
	assert_true(tip.visible, "PRECONDITION: the tooltip must be up before hiding can take it down")
	scene.set_command_menu_visible(false)
	await wait_frames(1)
	assert_false(menu.visible, "CONTROL: the menu itself must actually hide")
	assert_false(tip.visible,
		"the tooltip must leave with the menu, or it floats over the battlefield with nothing under it")


## MUST PASS ON BOTH TREES: a fix that simply hides the tooltip forever would satisfy the arm above.
func test_showing_the_menu_brings_its_tooltip_back() -> void:
	var pair: Array = await _scene_with_menu()
	var scene = pair[0]
	var menu = pair[1]
	if menu == null:
		fail_test("PRECONDITION: no menu")
		return
	menu._update_tooltip()
	await wait_frames(1)
	var tip = menu._tooltip_label
	if tip == null or not is_instance_valid(tip) or tip.text == "":
		fail_test("PRECONDITION: no tooltip text to restore")
		return
	scene.set_command_menu_visible(false)
	await wait_frames(1)
	scene.set_command_menu_visible(true)
	await wait_frames(1)
	assert_true(menu.visible, "the menu comes back")
	assert_true(tip.visible, "and so does its tooltip — hiding it permanently is not a fix")


## The second sibling, found by enumerating `get_parent().add_child` rather than by re-reading the
## one that bit me. A target box left over the battlefield is the same defect wearing another node.
func test_hiding_the_menu_takes_the_target_highlight_too() -> void:
	var pair: Array = await _scene_with_menu()
	var scene = pair[0]
	var menu = pair[1]
	if menu == null:
		fail_test("PRECONDITION: no menu")
		return
	menu._setup_target_highlight()
	await wait_frames(2)
	var hl = menu._target_highlight
	if hl == null or not is_instance_valid(hl):
		fail_test("PRECONDITION: no target highlight was built")
		return
	assert_ne(hl.get_parent(), menu, "CONTROL: the highlight is a sibling too")
	hl.visible = true
	scene.set_command_menu_visible(false)
	await wait_frames(1)
	assert_false(hl.visible,
		"the target box must leave with the menu, or it frames an enemy nothing is aiming at")
