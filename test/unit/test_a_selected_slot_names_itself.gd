extends GutTest

## The Equipment screen titled each slot (Weapon / Armor / Accessory) in DISABLED_COLOR (grey 0.4) -- the greyed-out
## option colour -- on rows that turn SELECTED_COLOR blue when highlighted: ~1.5:1, so the selected slot's own title
## all but vanished. Same defect the party card's job line had. Slot titles now clear WCAG AA on both rows.

const EM := preload("res://src/ui/EquipmentMenu.gd")
const PLAIN_ROW := Color(0.08, 0.08, 0.12)


func _lum(c: Color) -> float:
	var f := func(v: float) -> float: return v / 12.92 if v <= 0.03928 else pow((v + 0.055) / 1.055, 2.4)
	return 0.2126 * f.call(c.r) + 0.7152 * f.call(c.g) + 0.0722 * f.call(c.b)


func _contrast(a: Color, b: Color) -> float:
	var la := _lum(a)
	var lb := _lum(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


func test_a_slot_title_reads_on_the_selected_row() -> void:
	assert_lt(_contrast(EM.DISABLED_COLOR, EM.SELECTED_COLOR), 2.0, "CONTROL: the old grey is unreadable on the selected blue")
	assert_gte(_contrast(EM.SUBTITLE_COLOR, EM.SELECTED_COLOR), 4.5, "slot title vs the selected row")
	assert_gte(_contrast(EM.SUBTITLE_COLOR, PLAIN_ROW), 4.5, "slot title vs a plain row")


func test_the_slot_title_uses_the_subtitle_colour() -> void:
	var src := FileAccess.get_file_as_string("res://src/ui/EquipmentMenu.gd")
	var i := src.find('slot_label.name = "SlotTitle"')
	assert_gt(i, -1, "CONTROL: the slot title is built here")
	assert_true(src.substr(i, 400).contains("SUBTITLE_COLOR"), "the slot title is coloured SUBTITLE_COLOR, not DISABLED_COLOR")
