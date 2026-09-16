extends GutTest

## struktured 2026-08-22 asked for hold-to-repeat in menus. It reached three of them — Settings,
## the battle command menu, and the overworld menu — and the Equipment screen was not one, so its
## item list moved exactly one row per press. That list is the longest one on the screen and it is
## the one menu that cannot page: both shoulders are already taken there, cycling the party member.
##
## MenuRepeat is POLLED (a held d-pad emits one press event and never echoes, so is_echo can never
## produce repeat on a pad). Polling means it inherits NONE of the refusals _input makes for itself,
## which is why the _process guard has to mirror them and why that is the load-bearing arm here.

const EquipmentMenuScript = preload("res://src/ui/EquipmentMenu.gd")
const CombatantScript = preload("res://src/battle/Combatant.gd")

## Past MenuRepeat.INITIAL_DELAY, so one tick arms the hold and the next one fires.
const PAST_DELAY := 0.5


func _make_menu(item_count: int) -> EquipmentMenu:
	var menu: EquipmentMenu = EquipmentMenuScript.new()
	add_child_autofree(menu)
	var c = CombatantScript.new()
	add_child_autofree(c)
	menu.character = c
	var weapons: Array = []
	for i in range(item_count):
		weapons.append("weapon_%d" % i)
	menu.available_weapons = weapons
	menu.selected_slot = 0
	menu.mode = EquipmentMenuScript.Mode.ITEM_SELECT
	menu.visible = true
	return menu


## Godot's Input singleton leaks across GUT tests — a stuck ui_down drags later tests.
func after_each() -> void:
	Input.action_release("ui_up")
	Input.action_release("ui_down")


func test_holding_down_walks_the_item_list() -> void:
	var menu := _make_menu(20)
	menu.selected_item_index = 0

	Input.action_press("ui_down")
	menu._process(PAST_DELAY)
	assert_eq(menu.selected_item_index, 0,
		"the frame a direction goes down must NOT repeat — the press path owns the first step")
	menu._process(PAST_DELAY)
	assert_eq(menu.selected_item_index, 1, "holding past the delay steps the list on its own")
	menu._process(PAST_DELAY)
	assert_eq(menu.selected_item_index, 2, "…and keeps stepping while held")


func test_holding_up_walks_the_other_way() -> void:
	var menu := _make_menu(20)
	menu.selected_item_index = 5
	Input.action_press("ui_up")
	menu._process(PAST_DELAY)
	menu._process(PAST_DELAY)
	assert_eq(menu.selected_item_index, 4, "a held up steps backwards")


func test_a_hold_also_walks_the_slot_list() -> void:
	var menu := _make_menu(20)
	menu.mode = EquipmentMenuScript.Mode.SLOT_SELECT
	menu.selected_slot = 0
	Input.action_press("ui_down")
	menu._process(PAST_DELAY)
	menu._process(PAST_DELAY)
	assert_eq(menu.selected_slot, 1, "the repeat must follow whichever list the menu is showing")


## ⛔ THE LOAD-BEARING ARM. MenuRepeat polls Input, so a hold keeps stepping a menu the event path
## would refuse. _input returns early when the menu is not visible; _process must do the same.
func test_a_hidden_menu_does_not_step_under_a_held_direction() -> void:
	var menu := _make_menu(20)
	menu.selected_item_index = 3
	menu.visible = false

	Input.action_press("ui_down")
	for i in range(6):
		menu._process(PAST_DELAY)
	assert_eq(menu.selected_item_index, 3,
		"a hidden menu must not walk its list — _input refuses while hidden and the hold must too")


func test_releasing_drops_the_ramp_so_the_next_hold_waits_again() -> void:
	var menu := _make_menu(20)
	menu.selected_item_index = 0
	Input.action_press("ui_down")
	menu._process(PAST_DELAY)
	menu._process(PAST_DELAY)
	assert_eq(menu.selected_item_index, 1, "precondition: the hold fired once")

	Input.action_release("ui_down")
	menu._process(PAST_DELAY)
	Input.action_press("ui_down")
	menu._process(PAST_DELAY)
	assert_eq(menu.selected_item_index, 1,
		"a fresh hold must serve its initial delay again rather than inheriting the last ramp")


## ⚠️ THE EMPTY-LIST GUARD IS PINNED AT THE SOURCE, and the reason is measured rather than assumed.
## Deleting it leaves `(idx + step + 0) % 0`, and GDScript's modulo-by-zero ABORTS the enclosing
## function — so the assignment never completes, the index keeps its old value, and _build_ui() and
## the move sound do not run. That is byte-identical to what the guard produces, so NO value assert
## can tell them apart; only the pushed SCRIPT ERROR differs, which GUT does not fail on.
## Probed before writing this: `before=3 after=0` with the line after the modulo never reached.
## The behavioural half below still pins that a hold does not walk an empty list.
func test_an_empty_item_list_does_not_move_under_a_hold() -> void:
	var menu := _make_menu(0)
	menu.selected_item_index = 0
	Input.action_press("ui_down")
	for i in range(4):
		menu._process(PAST_DELAY)
	assert_eq(menu.selected_item_index, 0, "an empty list has nowhere to step")

	var GdSource = load("res://test/unit/helpers/gd_source.gd")
	var code: String = GdSource.code_of("res://src/ui/EquipmentMenu.gd")
	var at := code.find("func _nav_step(")
	assert_gt(at, -1, "the step must exist to be guarded")
	var stop := code.find("\nfunc ", at + 1)
	var body := code.substr(at, stop - at) if stop > at else code.substr(at)
	assert_true(body.find("items.is_empty()") > -1,
		"the empty-list guard must stay: without it a held direction spams a modulo-by-zero error "
		+ "that no value assert in this file can see")


## ONE OWNER. The press path and the hold path must share the step, or they drift — this repo has
## fixed that class repeatedly (heal_amount, restore_mp, the bust crop in two files).
func test_the_press_path_and_the_hold_path_share_one_step() -> void:
	var GdSource = load("res://test/unit/helpers/gd_source.gd")
	var code: String = GdSource.code_of("res://src/ui/EquipmentMenu.gd")
	assert_ne(code, "", "EquipmentMenu must be readable as source")
	assert_eq(code.count("func _nav_step("), 1, "there must be exactly one definition of the step")
	# A COUNT of call sites was a magnitude standing in for a property: routing the press branches
	# through MenuNav collapsed four of them into two and redded this arm on a correct change.
	# The property is that BOTH paths reach the one owner and neither carries its own arithmetic.
	assert_gt(code.count("_nav_step(") - code.count("func _nav_step("), 1,
		"the press path and the hold path must BOTH route through the one step")
	var proc_at := code.find("func _process(")
	assert_gt(proc_at, -1, "the hold path must exist")
	var proc_end := code.find("\nfunc ", proc_at + 1)
	var proc_body := code.substr(proc_at, proc_end - proc_at) if proc_end > proc_at else code.substr(proc_at)
	assert_true(proc_body.find("_nav_step(") > -1, "the hold path must call the shared step")
	assert_eq(code.find("selected_item_index - 1 + items.size()"), -1,
		"the press path must not carry its own copy of the arithmetic any more")
	assert_eq(code.find("selected_slot - 1 + SLOTS.size()"), -1,
		"…nor the slot path")
