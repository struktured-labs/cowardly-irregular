extends GutTest

## struktured, 2026-08-29 and after: a battle quip bubble tall enough to clip the crown of the enemy
## it sits beside. HEIGHT is what occludes; width is already managed (viewport clamp, RESERVED_RIGHT_PX
## keeps it off the party panel, the keep-out rects slide it past the command menu). So a long quip
## widens before it grows a third row.
##
## Measured with the shaper at the bubble's own font size (13), all 25 scripted party lines:
##   at 260px (shipped)   1 row 1 · 2 rows 11 · 3 rows 13
##   at 420px             1 row 11 · 2 rows 14 · 3 rows 0
## and a 140-char line — MAX_PARTY_LINE_CHARS, the LLM cap — goes from 4 rows to 3.
##
## 📌 This changes no authored line. Shortening the Mage/Cleric/Bard lines, or lowering the LLM cap,
## is still struktured's open call; this removes the clipping they caused without making it.

const BubbleScript = preload("res://src/battle/BattleSpeechBubble.gd")

var _font: Font
var _fsz: int


func before_each() -> void:
	var lbl := Label.new()
	add_child_autofree(lbl)
	_font = lbl.get_theme_font("font")
	_fsz = TextScale.scaled(13)


func _rows(text: String, width: float) -> int:
	var tp := TextParagraph.new()
	tp.width = width
	tp.add_string(text, _font, _fsz)
	return tp.get_line_count()


func _scripted_lines() -> Array:
	var out: Array = []
	var d = JSON.parse_string(FileAccess.get_file_as_string("res://data/job_personas.json"))
	if not (d is Dictionary) or not d.has("jobs"):
		return out
	for job in (d["jobs"] as Dictionary).keys():
		var tv = d["jobs"][job].get("trigger_voices", {})
		if not (tv is Dictionary):
			continue
		for trig in (tv as Dictionary).keys():
			var entry = tv[trig]
			var items: Array = entry if entry is Array else [entry]
			for ln in items:
				out.append({"who": "%s/%s" % [job, trig], "text": '"%s"' % VoiceLines.text_of(ln)})
	return out


## A quip that already fits keeps the narrow bubble it has today.
func test_a_short_quip_keeps_the_narrow_bubble() -> void:
	var short_line := '"Got it."'
	assert_lte(_rows(short_line, BubbleScript.MAX_TEXT_WIDTH), BubbleScript.WIDEN_TARGET_ROWS,
		"PRECONDITION: the fixture must already fit")
	assert_eq(BubbleScript.wrap_width_for(short_line, _font, _fsz), BubbleScript.MAX_TEXT_WIDTH,
		"nothing widens for a line that fits — a wider bubble occludes more for no gain")


## A quip that needs three rows gets width instead, and the width it gets actually fixes the rows.
func test_a_three_row_quip_widens_until_it_fits() -> void:
	var long_line := '"Verse complete. Wounds tallied, breaths counted, all party members returned to the page."'
	var before: int = _rows(long_line, BubbleScript.MAX_TEXT_WIDTH)
	assert_gt(before, BubbleScript.WIDEN_TARGET_ROWS,
		"PRECONDITION: the fixture must need widening at the shipped width (got %d rows)" % before)
	var w: float = BubbleScript.wrap_width_for(long_line, _font, _fsz)
	assert_gt(w, BubbleScript.MAX_TEXT_WIDTH, "it must widen")
	assert_lte(_rows(long_line, w), BubbleScript.WIDEN_TARGET_ROWS,
		"and the width it chose must actually reach the target — widening that does not is worse than not widening")


## SMALLEST sufficient width: one step narrower must NOT fit. Otherwise "widen" becomes "always widest".
func test_it_widens_by_the_smallest_step_that_works() -> void:
	var long_line := '"Verse complete. Wounds tallied, breaths counted, all party members returned to the page."'
	var w: float = BubbleScript.wrap_width_for(long_line, _font, _fsz)
	if w <= BubbleScript.MAX_TEXT_WIDTH:
		return
	var narrower: float = w - BubbleScript.WIDEN_STEP
	assert_gt(_rows(long_line, narrower), BubbleScript.WIDEN_TARGET_ROWS,
		"width %.0f fits in %d rows, so %.0f was wider than needed" % [narrower, _rows(long_line, narrower), w])


## A line too long for the target even at the cap gets the cap, not unbounded width.
func test_an_enormous_quip_stops_at_the_cap() -> void:
	var huge := ""
	for i in 40:
		huge += "unreasonable "
	var w: float = BubbleScript.wrap_width_for(huge, _font, _fsz)
	assert_eq(w, BubbleScript.MAX_TEXT_WIDTH_WIDE,
		"the widening is bounded — a runaway line must not push the bubble across the screen")
	assert_gt(_rows(huge, w), BubbleScript.WIDEN_TARGET_ROWS,
		"control: the fixture must genuinely exceed the target even at the cap, else this proves nothing")


## THE CORPUS: every scripted party line fits the target at the width it would actually be given.
func test_every_scripted_party_line_fits_the_target() -> void:
	var lines: Array = _scripted_lines()
	assert_gt(lines.size(), 20, "PRECONDITION: the persona corpus must load")
	var widened: Array = []
	var over: Array = []
	for e in lines:
		var t: String = str(e["text"])
		var w: float = BubbleScript.wrap_width_for(t, _font, _fsz)
		if w > BubbleScript.MAX_TEXT_WIDTH:
			widened.append(e["who"])
		if _rows(t, w) > BubbleScript.WIDEN_TARGET_ROWS:
			over.append("%s (%d rows at %.0f)" % [e["who"], _rows(t, w), w])
	gut.p("scripted lines widened: %d of %d %s" % [widened.size(), lines.size(), str(widened)])
	assert_eq(over.size(), 0, "scripted lines still over the target at their chosen width: %s" % str(over))
	# ANTI-VACUITY: if no scripted line needs widening, this file guards a mechanism nothing exercises.
	assert_gt(widened.size(), 0,
		"no scripted party line needed widening — either the lines were shortened (then say so and retire this) or the measurement broke")


## The bubble itself must USE it: a long quip's label must be wider than the narrow default.
## (A helper can be correct and uncalled — the source arm below cannot tell the difference.)
func test_the_built_bubble_uses_the_chosen_width() -> void:
	var host := Node2D.new()
	add_child_autofree(host)
	var long_line := "Verse complete. Wounds tallied, breaths counted, all party members returned to the page."
	var bubble = BubbleScript.spawn(host, Vector2(400, 300), "Cleric", long_line)
	assert_not_null(bubble, "PRECONDITION: the bubble must spawn")
	if bubble == null:
		return
	var label: Label = null
	for n in bubble.find_children("*", "Label", true, false):
		if str(n.text).begins_with('"'):
			label = n
			break
	assert_not_null(label, "the quip's own label must exist")
	if label == null:
		return
	assert_gt(label.custom_minimum_size.x, BubbleScript.MAX_TEXT_WIDTH,
		"the live bubble must take the widened width, not the narrow default")
	assert_lte(label.custom_minimum_size.x, BubbleScript.MAX_TEXT_WIDTH_WIDE, "and never exceed the cap")
