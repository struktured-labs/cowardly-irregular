extends GutTest

## The autogrind Summary drew every value in a fixed 170-px box with no clipping. A five-item session's "Items Used"
## value needs 438 px, so it ran off the RIGHT EDGE OF THE SCREEN (ink ended at x=1460 on a 1280-wide viewport) — the
## player saw a sentence walk off the panel and stop. Measured on main 96d55cb5b: ink ran 920..1358 on a 1280-wide
## screen. It needs the TWO-COLUMN layout, which a long session always reaches, so every fixture here is a long session.

const LONG_ITEMS := {"potion": 30, "hi_potion": 5, "ether": 12, "mega_potion": 7, "phoenix_down": 3}

const BASE := {
	"battles_won": 120, "total_exp": 99999, "total_gold": 88888, "elapsed_seconds": 3600.0,
	"consecutive_wins": 12, "efficiency": 4.2, "corruption": 2.5, "adaptation": 3.1, "collapse_count": 2,
	"rules_authored": 4, "rules_that_fired": 2, "rule_checks": 500,
	"meta_bosses_defeated": 5, "meta_bosses_spawned": 6,
	"fatigue_events_triggered": 4, "time_multiplier": 1.5,
	## These push the panel into two columns, which is where the row lands in the right column and runs off the screen.
	"per_character_exp": {"Fighter": 9999, "Cleric": 9999, "Rogue": 9999, "Mage": 9999, "Bard": 9999},
	"rule_noops": {"Heal Party: out of potions": 12, "Restore MP: out of ethers": 4},
	"permadead": ["Bard"],
}


func _build(extra: Dictionary) -> Control:
	var s = load("res://src/ui/autogrind/AutogrindSummary.gd").new()
	add_child_autofree(s)
	var stats: Dictionary = BASE.duplicate(true)
	stats.merge(extra, true)
	s.setup(stats, "HP threshold reached (20%)")
	await wait_frames(4)
	return s


func _labels(s: Control) -> Array:
	return s.find_children("*", "Label", true, false)


## What the player actually sees: the glyphs, not the box. A right-aligned label's ink ends at its right edge.
func _ink(l: Label) -> Rect2:
	var r: Rect2 = l.get_global_rect()
	var f: Font = l.get_theme_font("font")
	if f == null:
		return r
	## Godot draws the WHOLE string unless clip_text is set, so an unclipped label's ink is its text, not its box.
	var w: float = f.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, l.get_theme_font_size("font_size")).x
	if l.clip_text:
		w = minf(w, r.size.x)
	var x: float = r.position.x
	if l.horizontal_alignment == HORIZONTAL_ALIGNMENT_RIGHT:
		x = r.position.x + r.size.x - w
	return Rect2(Vector2(x, r.position.y), Vector2(w, r.size.y))


func _row(s: Control, label_text: String) -> Label:
	var ls: Array = _labels(s)
	for i in ls.size():
		if ls[i].text == label_text and i + 1 < ls.size():
			return ls[i + 1]
	return null


func test_the_panel_really_is_two_columns_here() -> void:
	var s: Control = await _build({"items_consumed": LONG_ITEMS})
	var ls: Array = _labels(s)
	var rows_at_y: Dictionary = {}
	for l in ls:
		var key: int = int(l.get_global_rect().position.y)
		rows_at_y[key] = int(rows_at_y.get(key, 0)) + 1
	var widest: int = 0
	for k in rows_at_y:
		widest = maxi(widest, int(rows_at_y[k]))
	assert_gte(widest, 4, "CONTROL: this fixture must reach the two-column layout, or the overflow arms prove nothing")


func test_a_five_item_session_stays_on_screen() -> void:
	var s: Control = await _build({"items_consumed": LONG_ITEMS})
	var vp: Rect2 = s.get_viewport().get_visible_rect()
	var off: Array = []
	for l in _labels(s):
		if l.text.strip_edges() != "" and not vp.grow(1).encloses(_ink(l)):
			off.append("'%s' ink=%s" % [l.text.substr(0, 30), _ink(l)])
	assert_eq(off, [], "Summary text ran off the 1280x720 screen")


func test_the_items_row_still_names_items_and_counts() -> void:
	var s: Control = await _build({"items_consumed": LONG_ITEMS})
	var val: Label = _row(s, "Items Used")
	assert_not_null(val, "CONTROL: the Items Used row must exist to be measured")
	assert_string_contains(val.text, "Potion x30", "the fitted value must still name the items the player burned")
	assert_string_contains(val.text, "more", "and say how many it could not show, rather than silently dropping them")


func test_the_items_row_fits_its_own_box() -> void:
	var s: Control = await _build({"items_consumed": LONG_ITEMS})
	var val: Label = _row(s, "Items Used")
	var f: Font = val.get_theme_font("font")
	var needed: float = f.get_string_size(val.text, HORIZONTAL_ALIGNMENT_LEFT, -1, val.get_theme_font_size("font_size")).x
	assert_lte(needed, val.size.x, "the fitted items text (%.0f px) must fit its box (%.0f px)" % [needed, val.size.x])
	assert_true(val.clip_text, "and the box must clip, so no future value can escape the panel either")


func test_a_short_item_list_is_shown_in_full() -> void:
	var s: Control = await _build({"items_consumed": {"potion": 3}})
	var val: Label = _row(s, "Items Used")
	assert_eq(val.text, "Potion x3", "CONTROL: a list that fits must be shown whole, with no '+N more' tail")


func test_no_value_overlaps_its_row_label() -> void:
	var s: Control = await _build({"items_consumed": LONG_ITEMS})
	var ls: Array = _labels(s)
	var hits: Array = []
	for i in ls.size():
		for j in range(i + 1, ls.size()):
			if absf(ls[i].get_global_rect().position.y - ls[j].get_global_rect().position.y) > 4.0:
				continue
			if ls[i].text.strip_edges() == "" or ls[j].text.strip_edges() == "":
				continue
			if _ink(ls[i]).grow(-1).intersects(_ink(ls[j]).grow(-1)):
				hits.append("'%s' / '%s'" % [ls[i].text.substr(0, 24), ls[j].text.substr(0, 24)])
	assert_eq(hits, [], "a widened value box collided with its row label")
