extends GutTest

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
]


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
