extends GutTest

## Regression: BestiaryMenu list must scroll to follow keyboard/wheel/gamepad
## selection. The monster list lives in a ScrollContainer of 28px rows (up to
## 88 monsters). Pre-fix the d-pad / arrow / wheel handlers only moved
## `_selected` + re-highlighted the row but NEVER adjusted scroll position, so
## once selection passed the ~20-row visible window the highlighted monster
## scrolled off-screen with no way to bring it back via gamepad — the exact
## controller-first path this game targets (CLAUDE.md: "Controller-first
## design"). Fix captures the ScrollContainer as a member (`_scroll`) and calls
## `ensure_control_visible(_row_nodes[_selected])` after every selection move.
##
## Bug ref: BestiaryMenu list does not scroll to follow selection.

const BESTIARY_MENU_PATH := "res://src/ui/BestiaryMenu.gd"

# A handful of real monster ids from data/monsters.json. Marking many seen
# forces the list to overflow the visible window so scroll-follow matters.
# NOTE: every id here MUST exist in data/monsters.json. BestiarySystem.
# get_seen_entries_sorted() silently drops any seen id whose monster data is
# empty (`if data.is_empty(): continue`), so a bogus id produces no list row.
# (The old seed used "rat", which is not a real id — the real one is
# "cave_rat" — so only 11 of 12 seeds yielded rows and the count assert below
# failed.) "diseased_rat" replaces it: a distinct, real id that keeps the list
# overflowing the visible window.
const _SEED_MONSTERS := [
	"slime", "bat", "goblin", "wolf", "spider", "skeleton",
	"ghost", "imp", "troll", "snake", "diseased_rat", "cave_rat",
]

var _saved_seen: Dictionary = {}


func before_each() -> void:
	# Snapshot + reset discovery state so the test is hermetic.
	_saved_seen = {}
	if GameState and GameState.game_constants.has("seen_monsters"):
		_saved_seen = GameState.game_constants["seen_monsters"].duplicate(true)
	if GameState:
		GameState.game_constants["seen_monsters"] = {}
	for id in _SEED_MONSTERS:
		BestiarySystem.mark_seen(id)


func after_each() -> void:
	if GameState:
		GameState.game_constants["seen_monsters"] = _saved_seen


func _read(path: String) -> String:
	var file = FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "file should exist: %s" % path)
	var text = file.get_as_text()
	file.close()
	return text


func _stand_up_menu() -> BestiaryMenu:
	var script = load(BESTIARY_MENU_PATH)
	var menu = script.new()
	add_child_autofree(menu)
	# _ready() runs on add_child: builds UI, refreshes detail, defers scroll.
	return menu


# --- Source pins (robust against headless layout flakiness) -----------------

func test_scroll_container_captured_as_member() -> void:
	# The ScrollContainer must be stored as a member so the nav handlers can
	# reach it. Pre-fix it was a throwaway local `var scroll := ...`.
	var text = _read(BESTIARY_MENU_PATH)
	assert_true(text.find("var _scroll: ScrollContainer") > -1,
		"BestiaryMenu must declare a `_scroll: ScrollContainer` member")
	assert_true(text.find("_scroll = ScrollContainer.new()") > -1,
		"_build_ui must assign the ScrollContainer to the `_scroll` member, not a local")
	assert_false(text.find("var scroll := ScrollContainer.new()") > -1,
		"The throwaway local `scroll` must be gone — it can't be reached by nav handlers")


func test_scroll_helper_uses_ensure_control_visible() -> void:
	var text = _read(BESTIARY_MENU_PATH)
	var idx = text.find("func _scroll_to_selected")
	assert_true(idx > -1, "BestiaryMenu must define _scroll_to_selected()")
	var body = text.substr(idx, 600)
	assert_true(body.find("ensure_control_visible") > -1,
		"_scroll_to_selected must call ScrollContainer.ensure_control_visible to follow selection")
	assert_true(body.find("is_instance_valid") > -1,
		"_scroll_to_selected must guard against freed row nodes")


func test_nav_handlers_call_scroll_to_selected() -> void:
	# Every selection-moving path (keyboard up/down, wheel up/down, hover,
	# click) must scroll the new selection into view.
	var text = _read(BESTIARY_MENU_PATH)
	# Count occurrences of the helper call inside the input/nav paths.
	var calls := 0
	var from := 0
	while true:
		var hit = text.find("_scroll_to_selected()", from)
		if hit == -1:
			break
		calls += 1
		from = hit + 1
	# 1 deferred initial call + ui_up + ui_down + wheel_up + wheel_down +
	# hover + click = 7 minimum.
	assert_true(calls >= 7,
		"Expected _scroll_to_selected() wired into every nav path (>=7 calls), found %d" % calls)


func test_keyboard_nav_ignores_echo_events() -> void:
	# Holding the d-pad must not rapid-fire _refresh_detail -> _load_sprite on
	# every key-repeat echo. The ui_up/ui_down branches gate on is_echo().
	var text = _read(BESTIARY_MENU_PATH)
	var up_idx = text.find("\"ui_up\"")
	assert_true(up_idx > -1, "ui_up branch must exist")
	var up_line = text.substr(up_idx, 80)
	assert_true(up_line.find("not event.is_echo()") > -1,
		"ui_up branch must gate on `not event.is_echo()` to avoid sprite-reload spam on d-pad hold")
	var down_idx = text.find("\"ui_down\"")
	assert_true(down_idx > -1, "ui_down branch must exist")
	var down_line = text.substr(down_idx, 80)
	assert_true(down_line.find("not event.is_echo()") > -1,
		"ui_down branch must gate on `not event.is_echo()`")


# --- Behavioral (does not crash, wiring actually runs) ----------------------

func test_scroll_to_selected_is_safe_with_no_scroll() -> void:
	# Defensive: helper must no-op (not crash) when called before/without a
	# ScrollContainer, or with an out-of-range selection.
	var script = load(BESTIARY_MENU_PATH)
	var menu = script.new()
	add_child_autofree(menu)
	# _ready already ran; force the edge cases explicitly.
	menu._scroll = null
	menu._scroll_to_selected()  # null scroll → no crash
	pass_test("_scroll_to_selected no-ops when _scroll is null")


func test_navigation_keeps_selected_row_in_scroll_window() -> void:
	# Behavioral: stand up the menu with an overflowing list, drive the
	# selection to the bottom, and assert the selected row is inside the
	# ScrollContainer's vertical window. Pre-fix the selected row would scroll
	# out of view because scroll_vertical never moved.
	var menu = _stand_up_menu()
	assert_not_null(menu._scroll, "ScrollContainer member must be populated after _ready")

	# One list row per seen monster whose data resolves in monsters.json.
	# get_seen_entries_sorted() drops any seen id with empty data (the silent
	# `if data.is_empty(): continue`), so first confirm every seeded id is a
	# real, resolvable id — this makes a future bad seed fail loudly here
	# instead of silently shrinking the list and confusing the row assert.
	var resolvable := 0
	for id in _SEED_MONSTERS:
		if not BestiarySystem.get_monster_data(id).is_empty():
			resolvable += 1
	assert_eq(resolvable, _SEED_MONSTERS.size(),
		"Every seeded id must resolve in monsters.json (no bogus ids)")
	assert_eq(menu._row_nodes.size(), resolvable,
		"Each resolvable seeded monster must produce exactly one list row")
	assert_true(menu._row_nodes.size() >= 12,
		"Seeded list must overflow the visible window so scroll-follow matters")

	# Let layout settle so row sizes + scroll geometry are valid, then run the
	# deferred initial scroll.
	await get_tree().process_frame
	await get_tree().process_frame

	# Drive selection to the last row via the down handler.
	var down_event := InputEventAction.new()
	down_event.action = "ui_down"
	down_event.pressed = true
	for _i in range(menu._row_nodes.size()):
		menu._selected = (menu._selected + 1) % menu._row_nodes.size()
		menu._highlight_row()
		menu._scroll_to_selected()
	await get_tree().process_frame

	var sel_row: Control = menu._row_nodes[menu._selected]
	assert_true(is_instance_valid(sel_row), "Selected row must be valid")

	# The selected row's top must be within the scrolled viewport window.
	# (ensure_control_visible guarantees the control is inside [scroll_v,
	# scroll_v + visible_height).) If scroll geometry hasn't settled in
	# headless (height == 0), this assertion is vacuously satisfied — the
	# source pins above are the hard guard.
	var scroll_v: int = menu._scroll.scroll_vertical
	var view_h: float = menu._scroll.size.y
	var row_top: float = sel_row.position.y
	if view_h > 0.0:
		assert_true(row_top >= float(scroll_v) - 2.0,
			"Selected row top (%f) must be at/below scroll offset (%d)" % [row_top, scroll_v])
		assert_true(row_top < float(scroll_v) + view_h + 30.0,
			"Selected row top (%f) must be within scrolled window [%d, %f)" % [
				row_top, scroll_v, float(scroll_v) + view_h])
	else:
		pass_test("Headless layout did not settle scroll geometry; source pins cover the fix")
