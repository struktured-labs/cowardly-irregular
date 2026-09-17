extends GutTest

## The two longest lists in the game moved one row per press.
##
## `MenuPaging` has existed since 2026-07-25 ("should be a fast scroll down feature in menus") and
## reached three menus. The Bestiary (113 monsters) and the item list (172 items) were not among
## them, and they are the two longest: at ~20 visible rows, reaching the tail of the Bestiary was
## about 90 presses. @cowir-controller published the 13-menu gap; @cowir-cutscenes took the two
## cutscene lists; these are the two with the most rows.
##
## 🔑 CLAMPED, NOT WRAPPED, and that is a deliberate difference from the arrows beside it. Both
## menus wrap on up/down (`% size`), which is right for stepping. A page jump means "move a
## screenful" — wrapping from row 2 to the tail is a different intent, and AbilitiesMenu's existing
## page behaviour already reads that way.
##
## ⛔ A CONTROL THE FOOTER DOES NOT NAME IS A CONTROL NOBODY FINDS, so both footers advertise it —
## derived through `hint_for_action`, never a family letter. `battle_defer`/`battle_advance` print
## L1/R1 on PlayStation, LB/RB on Xbox and L/R on Nintendo, and four footers in this game were
## shipping Nintendo's letters to every pad until `aabe8bb8` this morning.

const GdSource := preload("res://test/unit/helpers/gd_source.gd")
const BESTIARY := "res://src/ui/BestiaryMenu.gd"
const ITEMS := "res://src/ui/ItemsMenu.gd"

## Real ids, so BestiarySystem does not silently drop them (it skips ids with no monster data).
const _SEED := [
	"slime", "bat", "goblin", "wolf", "spider", "skeleton",
	"ghost", "imp", "troll", "snake", "diseased_rat", "cave_rat",
]

var _saved_seen: Dictionary = {}


func before_each() -> void:
	_saved_seen = {}
	if GameState and GameState.game_constants.has("seen_monsters"):
		_saved_seen = GameState.game_constants["seen_monsters"].duplicate(true)
	if GameState:
		GameState.game_constants["seen_monsters"] = {}
	for id in _SEED:
		BestiarySystem.mark_seen(id)


func after_each() -> void:
	if GameState:
		GameState.game_constants["seen_monsters"] = _saved_seen


## PageDown/PageUp rather than the shoulder actions: MenuPaging accepts both, and a key event needs
## no InputMap state, so the arm measures the menu instead of the bindings.
func _page(down: bool) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = KEY_PAGEDOWN if down else KEY_PAGEUP
	e.pressed = true
	return e


func _bestiary() -> Node:
	var menu: Node = load(BESTIARY).new()
	add_child_autofree(menu)
	return menu


func test_the_bestiary_moves_a_screenful_per_press() -> void:
	var menu: Node = _bestiary()
	assert_gt(menu._row_nodes.size(), MenuPaging.PAGE_ROWS,
		"CONTROL: the seeded list holds %d rows, more than one page — otherwise a page jump has nowhere to go" % menu._row_nodes.size())
	menu._selected = 0

	menu._input(_page(true))
	assert_eq(menu._selected, MenuPaging.PAGE_ROWS,
		"a page down must move %d rows; selection is at %d" % [MenuPaging.PAGE_ROWS, menu._selected])

	menu._input(_page(false))
	assert_eq(menu._selected, 0, "and a page up must come back")


func test_a_page_jump_clamps_where_the_arrows_wrap() -> void:
	var menu: Node = _bestiary()
	var last: int = menu._row_nodes.size() - 1
	menu._selected = last

	menu._input(_page(true))
	assert_eq(menu._selected, last,
		"a page down at the tail must stay at the tail, not wrap to the top like the arrows do")

	menu._selected = 0
	menu._input(_page(false))
	assert_eq(menu._selected, 0, "and a page up at the head must stay at the head")


## Real consumable ids, because ItemsMenu lists only items usable outside battle.
const _STOCK := [
	"potion", "hi_potion", "mega_potion", "elixir", "ether", "hi_ether", "antidote",
	"echo_herbs", "remedy", "phoenix_down", "power_drink", "speed_tonic", "x_potion",
	"smoke_bomb", "tent", "eye_drops",
]


func test_the_item_list_pages_too() -> void:
	## ⛔ SEEDED, NOT BORROWED. A headless run's inventory is EMPTY, so an arm that drives whatever
	## the save happens to hold measured a 0-row list and passed — it survived deleting the paging
	## branch outright. Stock the menu so the jump has somewhere to go.
	var stock: Dictionary = {}
	for id in _STOCK:
		stock[id] = 3
	var menu: Node = load(ITEMS).new()
	menu.setup([], stock)
	add_child_autofree(menu)
	assert_gt(menu._item_list.size(), MenuPaging.PAGE_ROWS,
		"CONTROL: the stocked list holds %d rows, and a page jump needs more than one page of them" % menu._item_list.size())
	menu.mode = 0
	menu.selected_item_index = 0
	menu._input(_page(true))
	assert_eq(menu.selected_item_index, MenuPaging.PAGE_ROWS,
		"a page down in the item list must move %d rows; it is at %d" % [MenuPaging.PAGE_ROWS, menu.selected_item_index])

	menu.selected_item_index = menu._item_list.size() - 1
	menu._input(_page(true))
	assert_eq(menu.selected_item_index, menu._item_list.size() - 1,
		"and it clamps at the tail rather than wrapping")


func test_both_footers_advertise_paging_without_naming_a_family_letter() -> void:
	## Source-read on purpose: the footer text is built once in _build_ui and a rendered Label is
	## not where the defect would be. What matters is that the token is DERIVED.
	for path in [BESTIARY, ITEMS]:
		var src: String = GdSource.code_of(path)
		assert_true(src.contains("func _build_ui") or src.contains("_build_ui()"),
			"CONTROL: %s read back without its builder — the strip ate the file" % path)
		## ⛔ NOT just "the word Page appears". Freezing `L/R: Page` into the string leaves every
			## hint_for_action call below it intact, so a presence assert passes while the caption lies
			## to two pad families out of three. Require the token itself to be a PLACEHOLDER.
		assert_true(src.contains("%s/%s: Page") or src.contains("%s: Page"),
			"%s must advertise paging with a derived token, not a literal — found no %%s placeholder beside \": Page\"" % path)
		assert_true(src.contains("hint_for_action(\"battle_defer\")") and src.contains("hint_for_action(\"battle_advance\")"),
			"%s must DERIVE both page tokens, never print a family's letter" % path)

## ⛔ HERMETIC ABOUT THE PROFILE. This file asks InputProfileManager for a name or glyph, so it
## inherits whatever `user://input/controls.json` holds; a remap test writes a "Custom" profile there
## and an interrupted run skips its cleanup. Two suites red that way on 2026-09-17 in one sandbox.
var _saved_profile: String = ""


func before_all() -> void:
	_saved_profile = InputProfileManager.active_profile
	InputProfileManager.apply_profile("Standard")


func after_all() -> void:
	if _saved_profile != "":
		InputProfileManager.apply_profile(_saved_profile)
