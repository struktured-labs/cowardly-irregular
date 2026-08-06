extends GutTest

## struktured, at the title screen with a finale save invisible in slot 50: "i dont think
## there is a way to select any game but the one continue loads ... you should be able to
## pick at startup somehow". There wasn't — Continue took get_most_recent_slot() and nothing
## else existed. This is the picker: LOAD GAME on the title menu, a replace-in-place slot
## list, cancel/BACK returns, and the chosen slot rides the SAME hardened load path Continue
## uses (one function on purpose — a second copy is how the paths would drift).
##
## Tests avoid touching user:// entirely (hard rule): menu rows are constructed directly and
## _select_item drives the real handler, so no on-disk save is required or written.

const TitleScreenScript = preload("res://src/ui/TitleScreen.gd")


func _title() -> Node:
	var t = TitleScreenScript.new()
	add_child_autofree(t)
	return t


func test_selecting_a_slot_row_emits_the_chosen_slot() -> void:
	var t := _title()
	var got: Array[int] = []
	t.load_selected.connect(func(slot): got.append(int(slot)))
	# Typed-array coercion: a plain literal assigned to Array[Dictionary] ABORTS the test
	# function silently — this file's own first run scored 2 Risky exactly that way.
	var rows: Array[Dictionary] = [{"id": "load_slot", "slot": 2, "label": "SLOT 3", "enabled": true}]
	t.menu_items = rows
	t.selected_index = 0
	t._select_item()
	assert_eq(got, [2] as Array[int],
		"the picker must emit the slot the player CHOSE — not most-recent, which is Continue's job")


func test_back_row_returns_to_the_main_menu() -> void:
	var t := _title()
	t._load_mode = true
	var rows: Array[Dictionary] = [{"id": "load_back", "label": "BACK", "enabled": true}]
	t.menu_items = rows
	t.selected_index = 0
	t._select_item()
	assert_false(t._load_mode, "BACK leaves the picker")
	var ids: Array = []
	for item in t.menu_items:
		ids.append(str(item.get("id", "")))
	assert_has(ids, "new_game", "and the main menu is rebuilt in its place")


func test_load_game_row_exists_exactly_when_continue_does() -> void:
	# The picker is only offered when a save exists — same predicate as Continue, read from
	# the same _check_for_save, so the two rows can never disagree about whether saves exist.
	var t := _title()
	t._build_menu()
	var ids: Array = []
	for item in t.menu_items:
		ids.append(str(item.get("id", "")))
	assert_eq(ids.has("load_game"), ids.has("continue"),
		"LOAD GAME and CONTINUE appear together or not at all — one save-existence predicate")


func test_the_chosen_slot_rides_continues_load_path() -> void:
	# The wiring half: GameLoop's picker handler and Continue must share _title_load_slot —
	# a duplicated body is how the two paths would drift apart bug by bug.
	var src := FileAccess.get_file_as_string("res://src/GameLoop.gd")
	assert_true(src.contains("_title_screen.load_selected.connect(_on_title_load)"),
		"the picker's signal must be connected or the feature is a dead menu row")
	var continue_body_start: int = src.find("func _on_title_continue")
	var load_body_start: int = src.find("func _on_title_load")
	assert_gt(continue_body_start, -1, "continue handler exists")
	assert_gt(load_body_start, -1, "load handler exists")
	for fn_start in [continue_body_start, load_body_start]:
		var fn_end: int = src.find("\nfunc ", fn_start + 1)
		assert_true(src.substr(fn_start, fn_end - fn_start).contains("_title_load_slot"),
			"both title entry points delegate to the ONE slot-loading core")
