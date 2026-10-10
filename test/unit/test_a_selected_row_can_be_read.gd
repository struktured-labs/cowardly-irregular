extends GutTest

## A rendered contrast probe over every field-menu screen (text colour against the pixels drawn behind it) found
## information printed in the "disabled" grey on rows that turn SELECTED_COLOR blue: ~1.5:1. On the row you were ON,
## you could not read an item's quantity, a job's description, a setting's help text or a lens's effect. Each of those
## labels now uses a subtitle colour that clears WCAG AA on the highlight. Locked lens text was 2.6:1; lightened.
## The Save/Load screen had it on every line inside a slot card -- location, time, date, job, HP -- and Teleport on
## a destination's area line.

const SITES := [
	["res://src/ui/ItemsMenu.gd", "qty_label.add_theme_color_override(\"font_color\", "],
	["res://src/ui/JobMenu.gd", "slot_label.add_theme_color_override(\"font_color\", "],
	["res://src/ui/JobMenu.gd", "desc_label.add_theme_color_override(\"font_color\", "],
	["res://src/ui/LensMenu.gd", "passive_lbl.add_theme_color_override(\"font_color\", "],
	["res://src/ui/TeleportMenu.gd", "id_label.add_theme_color_override(\"font_color\", "],
	["res://src/ui/SaveScreen.gd", "loc_label.add_theme_color_override(\"font_color\", "],
	["res://src/ui/SaveScreen.gd", "time_label.add_theme_color_override(\"font_color\", "],
	["res://src/ui/SaveScreen.gd", "empty_label.add_theme_color_override(\"font_color\", "],
]
const MENUS := ["res://src/ui/ItemsMenu.gd", "res://src/ui/JobMenu.gd", "res://src/ui/SettingsMenu.gd", "res://src/ui/LensMenu.gd",
	"res://src/ui/TeleportMenu.gd", "res://src/ui/SaveScreen.gd"]


func _chan(v: float) -> float:
	return v / 12.92 if v <= 0.03928 else pow((v + 0.055) / 1.055, 2.4)


func _lum(c: Color) -> float:
	return 0.2126 * _chan(c.r) + 0.7152 * _chan(c.g) + 0.0722 * _chan(c.b)


func _contrast(a: Color, b: Color) -> float:
	return (maxf(_lum(a), _lum(b)) + 0.05) / (minf(_lum(a), _lum(b)) + 0.05)


func test_each_menus_subtitle_reads_on_its_own_highlight() -> void:
	for path in MENUS:
		var m = load(path)
		assert_lt(_contrast(Color(0.4, 0.4, 0.4), m.SELECTED_COLOR), 2.0, "CONTROL: %s: the old grey fails on its highlight" % path.get_file())
		assert_gte(_contrast(m.SUBTITLE_COLOR, m.SELECTED_COLOR), 4.5, "%s: subtitle vs highlight (%.2f:1)" % [path.get_file(), _contrast(m.SUBTITLE_COLOR, m.SELECTED_COLOR)])


func test_each_in_row_label_uses_the_subtitle_colour() -> void:
	for site in SITES:
		var src := FileAccess.get_file_as_string(site[0])
		var i := src.find(site[1])
		assert_gt(i, -1, "CONTROL: %s still builds %s" % [site[0].get_file(), site[1].get_slice(".", 0)])
		assert_true(src.substr(i, site[1].length() + 20).contains("SUBTITLE_COLOR"), "%s: %s is SUBTITLE_COLOR" % [site[0].get_file(), site[1].get_slice(".", 0)])


func test_no_setting_help_text_is_the_disabled_grey() -> void:
	var src := FileAccess.get_file_as_string("res://src/ui/SettingsMenu.gd")
	assert_gt(src.count("desc.add_theme_color_override(\"font_color\", SUBTITLE_COLOR)"), 5, "CONTROL: the setting builders colour their help text")
	assert_eq(src.count("desc.add_theme_color_override(\"font_color\", DISABLED_COLOR)"), 0, "no setting's help text uses the disabled grey")


func test_a_locked_lens_reads_on_the_highlight_and_takes_the_right_article() -> void:
	var lm = load("res://src/ui/LensMenu.gd")
	assert_gte(_contrast(lm.LOCKED_COLOR, lm.SELECTED_COLOR), 4.5, "locked lens text vs highlight (%.2f:1)" % _contrast(lm.LOCKED_COLOR, lm.SELECTED_COLOR))
	assert_eq(LensSystem.article_for("arbiter"), "an", "an Arbiter")
	assert_eq(LensSystem.article_for("warden"), "a", "a Warden")
	assert_eq(LensSystem.article_for("Curator"), "a", "a Curator")


func test_load_modes_empty_slot_stays_dimmer_but_legible() -> void:
	var ss = load("res://src/ui/SaveScreen.gd")
	assert_gte(_contrast(ss.NO_SAVE_COLOR, ss.SELECTED_COLOR), 3.0, "'- No save -' on the highlighted slot (%.2f:1)" % _contrast(ss.NO_SAVE_COLOR, ss.SELECTED_COLOR))
	assert_lt(_lum(ss.NO_SAVE_COLOR), _lum(ss.SUBTITLE_COLOR), "LOAD mode's empty slot is still dimmer than SAVE mode's: it is not a target")
