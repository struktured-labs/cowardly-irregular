extends GutTest

var GdSource = load("res://test/unit/helpers/gd_source.gd")

## struktured 2026-07-26: "how to scroll quickly or page thru long menus?"
##
## He asked because paging existed in only 2 of the menus that need it — and the
## two longest lists in the game (Jukebox at 153 tracks, Abilities) were among
## the ones without it. A feature that exists in some menus and not others is
## worse than one that exists nowhere: the player learns it works, then it
## silently doesn't, and they conclude the menu is broken rather than unpaged.
##
## Ratchets that every menu driving a long list through selected_index also
## offers a page jump. Deliberately NOT "every menu" — short fixed menus don't
## need it and requiring them would be the allowlist-on-day-one shape.

const LONG_LIST_MENUS := [
	"res://src/ui/SettingsMenu.gd",
	"res://src/ui/BossSelectorMenu.gd",
	"res://src/ui/JukeboxMenu.gd",
	"res://src/ui/AbilitiesMenu.gd",
	"res://src/ui/TeleportMenu.gd",
	"res://src/ui/FastTravelMenu.gd",
]

## Godot ships these with a KEYBOARD default and no joypad binding, and project.godot declares
## none of them — so a menu paging through them pages on keyboard only. TeleportMenu did exactly
## that (2026-09-16): PageUp/PageDown moved 8 rows, and a pad had no fast scroll at all.
const KEYBOARD_ONLY_PAGE_ACTIONS := ["ui_page_up", "ui_page_down"]

## Jump-to-first/last is a keyboard CONVENIENCE, not a control a pad is missing: a page jump
## reaches either end. So these are allowed — but only in a menu that also offers the pad-reachable
## page jump, which is the property the arm below checks. Found by the page arm reporting them.
const KEYBOARD_ONLY_EXTRA_ACTIONS := ["ui_home", "ui_end"]


func test_every_long_list_menu_offers_a_page_jump() -> void:
	var missing: Array = []
	for path in LONG_LIST_MENUS:
		var src := FileAccess.get_file_as_string(path)
		assert_ne(src, "", "%s must be readable" % path)
		if not src.contains("MenuPaging.page_delta("):
			missing.append(path.get_file())
	assert_eq(missing, [],
		"these menus scroll long lists but offer no page jump, so paging works in some "
		+ "menus and not others: %s" % [missing])


func test_paging_helper_covers_both_keyboard_and_gamepad() -> void:
	# If it were keyboard-only, a controller-first player would never find it —
	# and this project is controller-first by design.
	var src := FileAccess.get_file_as_string("res://src/ui/MenuPaging.gd")
	assert_true(src.contains("KEY_PAGEUP") and src.contains("KEY_PAGEDOWN"),
		"keyboard paging must stay bound to PageUp/PageDown")
	assert_true(src.contains("battle_defer") and src.contains("battle_advance"),
		"gamepad paging must stay on L1/R1 — controller-first is a project rule")


func test_page_jump_is_a_meaningful_stride() -> void:
	var src := FileAccess.get_file_as_string("res://src/ui/MenuPaging.gd")
	var re := RegEx.new()
	re.compile("PAGE_ROWS\\s*:=\\s*(?<n>\\d+)")
	var m := re.search(src)
	assert_not_null(m, "PAGE_ROWS must be declared")
	if m != null:
		assert_gt(int(m.get_string("n")), 3,
			"a page jump smaller than a few rows is indistinguishable from holding the d-pad")


## The arm that would have caught TeleportMenu. Derived from the source rather than a list of
## menus someone remembers to update: any UI file reaching for a keyboard-only nav action is
## shipping a control a controller cannot press, in a project whose first rule is the opposite.
func test_no_menu_pages_through_a_keyboard_only_action() -> void:
	var declared := FileAccess.get_file_as_string("res://project.godot")
	var offenders: Array = []
	var scanned := 0
	for action in KEYBOARD_ONLY_PAGE_ACTIONS + KEYBOARD_ONLY_EXTRA_ACTIONS:
		assert_false(declared.contains("\n%s={" % action),
			"%s is now declared in project.godot — if it was given a pad binding, drop it from this list" % action)
	for path in _ui_scripts("res://src/ui"):
		# Comment-stripped: the fix for this very defect explains itself in a comment naming both
		# actions, and a raw scan would red on the sentence describing why they were removed.
		var src: String = GdSource.code_of(path)
		if src == "":
			continue
		scanned += 1
		for action in KEYBOARD_ONLY_PAGE_ACTIONS:
			if src.contains('is_action_pressed("%s")' % action):
				offenders.append("%s -> %s" % [path.get_file(), action])
		for action in KEYBOARD_ONLY_EXTRA_ACTIONS:
			if src.contains('is_action_pressed("%s")' % action) and not src.contains("MenuPaging.page_delta("):
				offenders.append("%s -> %s with no pad-reachable page jump beside it" % [path.get_file(), action])
	assert_gt(scanned, 20, "the scan must actually read the UI corpus; a short corpus passes vacuously")
	assert_eq(offenders, [],
		"these menus navigate with an action that has no gamepad binding, so the control is "
		+ "invisible to a controller-first player: %s" % [offenders])


func _ui_scripts(dir_path: String) -> Array:
	var out: Array = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		var full := dir_path.path_join(name)
		if dir.current_is_dir():
			out.append_array(_ui_scripts(full))
		elif name.ends_with(".gd"):
			out.append(full)
		name = dir.get_next()
	dir.list_dir_end()
	return out
