extends GutTest

## The controls reference must be reachable WITHOUT quitting to the title screen.
##
## Regression for demo feedback 2026-08-20 ("the controls are impossible to figure out"):
## the HOW TO PLAY content existed and was good, but lived only in TitleScreen's private
## overlay. Pressing NEW GAME made it unreachable for the rest of the session, and the
## in-game path was Settings -> Controls, with Settings item 18 of 18.
##
## These assert REACHABILITY — a door exists from in-game to the reference. They deliberately
## do not pin pixel positions or row numbers, which drift on any layout edit.

const OverworldMenuPath := "res://src/ui/OverworldMenu.gd"
const ControlsMenuPath := "res://src/ui/ControlsMenu.gd"
const OverlayPath := "res://src/ui/HowToPlayOverlay.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "expected %s to be readable" % p)
	return t


func test_overworld_menu_offers_controls_at_top_level() -> void:
	var src := _read(OverworldMenuPath)
	assert_true(src.contains('{"id": "controls"'),
		"the pause menu must offer Controls without nesting it under Settings")
	assert_true(src.contains('"controls":'),
		"the id must be dispatched, or the row is inert")
	assert_true(src.contains("func _open_controls("),
		"dispatch must reach an opener")


func test_controls_entry_is_not_buried_below_settings() -> void:
	# The point is discoverability, so position carries the behaviour here — but assert the
	# RELATIONSHIP (before Settings) rather than an index, which any menu edit would break.
	var src := _read(OverworldMenuPath)
	var controls_at := src.find('{"id": "controls"')
	var settings_at := src.find('{"id": "settings"')
	assert_gt(controls_at, -1, "Controls entry must exist")
	assert_gt(settings_at, -1, "Settings entry must exist (control for this comparison)")
	assert_lt(controls_at, settings_at,
		"Controls must appear before Settings — burying it is the bug being fixed")


## struktured 2026-11-19, playing .808: "controls should not be first item in the menu list". It sits directly above Settings.
func test_controls_is_directly_above_settings_and_never_first() -> void:
	var opts: Array = (load(OverworldMenuPath) as GDScript).get_script_constant_map().get("BASE_MENU_OPTIONS", [])
	assert_gt(opts.size(), 3, "FLOOR: BASE_MENU_OPTIONS was read (%d rows)" % opts.size())
	var ids: Array = opts.map(func(o): return str((o as Dictionary).get("id", "")))
	var at: int = ids.find("controls")
	assert_gt(at, -1, "CONTROL: the Controls row exists (%s)" % [ids])
	assert_ne(str(ids[0]), "controls", "the menu must not open on Controls")
	assert_eq(str(ids[0]), "quest_log", "the menu opens on Quest Log, nothing else reordered")
	assert_eq(at, ids.find("settings") - 1, "Controls sits directly above Settings (%s)" % [ids])
	assert_eq(at, ids.find("load") + 1, "Controls sits directly after Load (%s)" % [ids])


func test_controls_screen_opens_the_full_reference() -> void:
	var src := _read(ControlsMenuPath)
	assert_true(src.contains("ROW_HELP"), "Controls needs a How to Play row")
	assert_true(src.contains("HowToPlayOverlay.new()"),
		"the row must instantiate the shared overlay, not duplicate the text")


func test_the_reference_is_shared_not_duplicated() -> void:
	# Two copies would drift, and the glyph fix would land on only one of them.
	var overlay := _read(OverlayPath)
	var title := _read("res://src/ui/TitleScreen.gd")
	# Canary for "the body lives here". Was "Defer / Party Chat" until that row was split per key
	# (2026-10-12) — pick a token off a row that exists, not one a correct edit can retire.
	assert_true(overlay.contains("Defer (in battle)"),
		"the overlay must own the reference body")
	assert_false(title.contains("Defer (in battle)"),
		"TitleScreen must delegate to the overlay rather than keep a second copy")
	assert_true(title.contains("HowToPlayOverlay.new()"),
		"TitleScreen must open the shared overlay")


func test_reference_body_names_the_attached_pad_not_a_hardcoded_letter() -> void:
	# The whole point of the glyph work: this text is where a wrong letter is most visible.
	var body: String = HowToPlayOverlay.build_text()
	assert_ne(body, "", "build_text must return the reference")
	assert_true(body.contains("Confirm / Select"),
		"the confirm row must survive extraction")
	assert_false(body.contains("A Button          Z / Enter"),
		"hardcoded Xbox lettering is back in the shared body")
