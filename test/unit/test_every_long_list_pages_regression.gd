extends GutTest

## The Theater (40+ scenes a world) and Party Chat (44 registry chats) had no fast scroll — one row per press, and the footers named no such control (cowir-controller's survey, 2026-09-16: 13 of 16 list menus).

const GALLERY := "res://src/ui/CutsceneGallery.gd"
const PARTY_CHAT := "res://src/ui/PartyChatMenu.gd"


func _src(p: String) -> String:
	var s := FileAccess.get_file_as_string(p)
	assert_gt(s.length(), 0, "%s must load" % p)
	return s


func _page_event(down: bool) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = KEY_PAGEDOWN if down else KEY_PAGEUP
	e.pressed = true
	return e


## The helper must agree the synthesised event IS a page jump, or every arm below is vacuous.
func test_control_the_page_event_reads_as_paging() -> void:
	assert_eq(MenuPaging.page_delta(_page_event(true)), 1, "PageDown must read as +1")
	assert_eq(MenuPaging.page_delta(_page_event(false)), -1, "PageUp must read as -1")
	var plain := InputEventKey.new()
	plain.keycode = KEY_Z
	plain.pressed = true
	assert_eq(MenuPaging.page_delta(plain), 0, "an unrelated key must not page, else the arms fire on anything")


## Both menus must consult the shared helper rather than growing their own step.
func test_both_menus_page_through_the_shared_helper() -> void:
	for p in [GALLERY, PARTY_CHAT]:
		var s := _src(p)
		assert_true(s.contains("MenuPaging.page_delta(event)"),
			"%s still steps one row per press on a list that outgrows the screen" % p)
		assert_true(s.contains("MenuPaging.PAGE_ROWS"),
			"%s must move by the shared page size, not a number of its own" % p)


## Clamped, not wrapped: a page jump that lands past the end is disorienting (AbilitiesMenu's rule).
func test_paging_is_clamped_not_wrapped() -> void:
	for p in [GALLERY, PARTY_CHAT]:
		var s := _src(p)
		var i := s.find("MenuPaging.page_delta(event) * MenuPaging.PAGE_ROWS")
		assert_gt(i, -1, "%s must scale the delta by the page size" % p)
		var window := s.substr(max(0, i - 200), 260)
		assert_true(window.contains("clampi("),
			"%s pages without clamping — wrapping past the end of a long list loses the player's place" % p)


## A control no footer names is a control nobody finds, and the token must be derived per device.
func test_both_footers_advertise_paging_with_a_derived_token() -> void:
	for p in [GALLERY, PARTY_CHAT]:
		var s := _src(p)
		assert_true(s.contains("Page"), "%s must advertise the paging control in its footer" % p)
		assert_true(s.contains('hint_for_action("battle_defer")') and s.contains('hint_for_action("battle_advance")'),
			"%s must derive the paging glyphs — L/L1/LB are three families' names for one button" % p)


## And it must not hand any pad a frozen shoulder name, which is the class that hit four footers today.
func test_no_footer_freezes_a_shoulder_name() -> void:
	for p in [GALLERY, PARTY_CHAT]:
		var s := _src(p)
		for frozen in ["[L/R]", "L/R: Page", "L1/R1", "LB/RB"]:
			assert_false(s.contains(frozen),
				"%s writes %s literally; that names one family's buttons for every pad" % [p, frozen])
