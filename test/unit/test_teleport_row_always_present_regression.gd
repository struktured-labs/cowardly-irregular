extends GutTest

## Teleport used to be gated on `debug_log_enabled` — a flag whose name and comment
## advertise only a logging overlay ("Show debug log overlay"). Turning the overlay off
## before a demo silently removed the pause-menu Teleport row, which was the only route to
## Glacius and Pyrroth while they sat in sealed walkable components of the W1 map.
## struktured 2026-08-22: "just leave teleport in the menuy all the time right now worry
## about it later" — so the row is unconditional and whether it SHOULD be player-facing is
## deferred. These guard the defect, not the flag: re-introduce ANY gate and the debug-off
## arm reds.

var _orig_debug: bool = true


func before_all() -> void:
	# GameState is an autoload; whatever this file leaves set survives into later files.
	if GameState:
		_orig_debug = GameState.debug_log_enabled


func after_each() -> void:
	if GameState:
		GameState.debug_log_enabled = _orig_debug


func after_all() -> void:
	if GameState:
		GameState.debug_log_enabled = _orig_debug


func _option_ids(debug_on: bool) -> Array:
	# BUILDS the real option list rather than pinning source, so dead code cannot fake it.
	# setup() iterates the party; an empty array skips that loop and reaches the append.
	if GameState:
		GameState.debug_log_enabled = debug_on
	var menu = load("res://src/ui/OverworldMenu.gd").new()
	add_child_autofree(menu)
	menu.setup([])
	var ids := []
	for opt in menu._menu_options:
		ids.append(opt.get("id", ""))
	return ids


func test_teleport_is_offered_with_the_debug_overlay_ON() -> void:
	assert_has(_option_ids(true), "teleport", "Teleport must be in the pause menu")


func test_teleport_is_offered_with_the_debug_overlay_OFF() -> void:
	# THE DEFECT. Hiding the debug overlay before a demo used to delete the only route to
	# two W1 dragon bosses, with nothing red.
	assert_has(_option_ids(false), "teleport",
		"turning the debug overlay OFF must not remove Teleport")


func test_the_menu_builder_discriminates() -> void:
	# CONTROL: without this, both arms above would pass on a builder that returned
	# everything, or on an `assert_has` that matched anything.
	var ids := _option_ids(true)
	assert_does_not_have(ids, "not_a_real_menu_id",
		"the id lookup must be able to say NO, or the arms above prove nothing")
	assert_gt(ids.size(), 3, "the real menu should carry several rows, got %d" % ids.size())


func test_no_gate_sits_on_the_teleport_append() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/ui/OverworldMenu.gd")
	assert_ne(src, "", "OverworldMenu must be readable")
	var idx := src.find('"id": "teleport"')
	assert_gt(idx, -1, "the teleport row must exist")
	# Read only the lines ABOVE the append: debug_log_enabled may legitimately appear
	# elsewhere in the file, and a file-wide search would pass on the wrong occurrence.
	var head: String = src.substr(maxi(0, idx - 200), 200)
	assert_false(head.contains("debug_log_enabled"),
		"the teleport row must not be gated on the debug-overlay flag")
