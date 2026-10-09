extends GutTest

## The field menu's party card printed the job under each name in DISABLED_COLOR (grey 0.4). On the selected card's
## blue that is ~1.5:1 contrast: the job of whichever character you were on all but vanished. The job line now has
## its own subdued colour that clears WCAG AA (4.5:1) on both the selected and the plain card.

const OM := preload("res://src/ui/OverworldMenu.gd")
const PLAIN_CARD := Color(0.08, 0.08, 0.12)


func _lum(c: Color) -> float:
	var f := func(v: float) -> float: return v / 12.92 if v <= 0.03928 else pow((v + 0.055) / 1.055, 2.4)
	return 0.2126 * f.call(c.r) + 0.7152 * f.call(c.g) + 0.0722 * f.call(c.b)


func _contrast(a: Color, b: Color) -> float:
	var la := _lum(a)
	var lb := _lum(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


func test_the_old_colour_vanished_on_the_selected_card() -> void:
	assert_lt(_contrast(OM.DISABLED_COLOR, OM.SELECTED_COLOR), 2.0, "CONTROL: grey 0.4 on the selected blue is unreadable")


func test_the_job_line_reads_on_both_cards() -> void:
	assert_gte(_contrast(OM.SUBTITLE_COLOR, OM.SELECTED_COLOR), 4.5, "job line vs the selected card (%.2f:1)" % _contrast(OM.SUBTITLE_COLOR, OM.SELECTED_COLOR))
	assert_gte(_contrast(OM.SUBTITLE_COLOR, PLAIN_CARD), 4.5, "job line vs a plain card")


func test_the_party_card_uses_the_subtitle_colour() -> void:
	var src := FileAccess.get_file_as_string("res://src/ui/OverworldMenu.gd")
	var i := src.find('job_label.name = "JobLabel"')
	assert_gt(i, -1, "CONTROL: the job label is built here")
	var block := src.substr(i, 400)
	assert_true(block.contains("SUBTITLE_COLOR"), "the job label is coloured SUBTITLE_COLOR, not DISABLED_COLOR")
