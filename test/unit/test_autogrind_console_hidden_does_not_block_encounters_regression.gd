extends GutTest

## struktured 2026-09-06, Suburbia: "got that bug again on overworld where no monsters can cause
## RE". Different root than the spider wedge — his log: 33x "BLOCKED — autogrind UI is open".
## The console HIDES itself when a grind starts/resumes; if it outlives the grind hidden, the
## encounter guard read "node exists" as "console open" and no battle could ever start.
## Fix: open == SHOWING, and a hidden console with no grind running is freed, not obeyed.

const GL := "res://src/GameLoop.gd"


func _showing(ui: Node) -> bool:
	return load(GL)._ui_is_showing(ui)


func test_a_visible_console_in_the_tree_counts_as_open() -> void:
	var ui := Control.new()
	add_child_autofree(ui)
	assert_true(_showing(ui), "CONTROL: visible + in tree = open (the legitimate block)")


func test_a_hidden_console_does_not_count_as_open() -> void:
	var ui := Control.new()
	add_child_autofree(ui)
	ui.visible = false
	assert_false(_showing(ui), "hidden = not open — this was the wedge")


func test_a_detached_or_null_console_does_not_count_as_open() -> void:
	var ui := Control.new()
	assert_false(_showing(ui), "not in the tree = not open")
	ui.free()
	assert_false(_showing(null), "null = not open")


func test_encounter_guard_uses_showing_and_heals_a_lingering_console() -> void:
	var src := FileAccess.get_file_as_string(GL)
	assert_gt(src.length(), 10000, "CONTROL: read a real file")
	var i: int = src.find('print("[GAMELOOP] BLOCKED — autogrind UI is open")')
	assert_gt(i, -1, "CONTROL: the guard must exist")
	var before: String = src.substr(maxi(i - 120, 0), 120)
	assert_true(before.contains("_autogrind_ui_open()"), "the guard must test SHOWING, not existence")
	var after: String = src.substr(i, 500)
	assert_true(after.contains("_on_autogrind_ui_closed()") and after.contains("not _is_autogrinding"),
		"a hidden console with no grind must be freed so the NEXT touch starts a battle")


func test_no_input_guard_still_tests_bare_existence() -> void:
	# The three input guards used the same existence test; a stale hidden console would also eat
	# the toggle-auto and menu buttons. One helper, every guard.
	var src := FileAccess.get_file_as_string(GL)
	var bare := 0
	var idx := src.find("if _autogrind_ui and is_instance_valid(_autogrind_ui):")
	while idx != -1:
		bare += 1
		idx = src.find("if _autogrind_ui and is_instance_valid(_autogrind_ui):", idx + 1)
	# The two legitimate survivors: the open-guard in _open_autogrind_ui and the free in the close handler.
	assert_lte(bare, 3, "bare existence checks left: %d — input/encounter guards must use _autogrind_ui_open()" % bare)
