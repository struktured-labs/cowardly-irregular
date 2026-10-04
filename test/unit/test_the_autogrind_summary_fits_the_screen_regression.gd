extends GutTest

## A long autogrind session's Summary stacked past the 720-px screen: with a full party's EXP rows, rule notes, a permadeath
## and a few new badges, 9 labels were drawn below the bottom edge, namely the SESSION GRADE, the PERMADEAD line and every
## achievement. The panel height was clamped to the viewport; the rows were not. Too many rows now split into two columns.

const LONG := {
	"battles_won": 120, "total_exp": 99999, "total_gold": 88888, "elapsed_seconds": 3600.0,
	"consecutive_wins": 12, "efficiency": 4.2, "corruption": 2.5, "adaptation": 3.1, "collapse_count": 2,
	"rules_authored": 4, "rules_that_fired": 2, "rule_checks": 500,
	"meta_bosses_defeated": 5, "meta_bosses_spawned": 6,
	"per_character_exp": {"Fighter": 9999, "Cleric": 9999, "Rogue": 9999, "Mage": 9999, "Bard": 9999},
	"items_consumed": {"potion": 30, "hi_potion": 5, "ether": 12},
	"fatigue_events_triggered": 4, "time_multiplier": 1.5,
	"rule_noops": {"Heal Party: out of potions": 12, "Restore MP: out of ethers": 4, "Member Casts: Cleric is silenced": 2},
	"permadead": ["Bard"],
}
const SHORT := {"battles_won": 8, "total_exp": 400, "total_gold": 300, "elapsed_seconds": 120.0}


func _build_summary(stats: Dictionary) -> Control:
	var s = load("res://src/ui/autogrind/AutogrindSummary.gd").new()
	add_child_autofree(s)
	s.setup(stats, "HP threshold reached (20%)")
	await wait_frames(3)
	return s


func _labels(s: Control) -> Array:
	return s.find_children("*", "Label", true, false)


func _rect(l: Label) -> Rect2:
	var r: Rect2 = l.get_global_rect()
	return Rect2(r.position, Vector2(maxf(r.size.x, l.get_minimum_size().x), maxf(r.size.y, 16.0)))


func test_a_long_session_stays_on_screen() -> void:
	var s: Control = await _build_summary(LONG)
	var vp: Rect2 = s.get_viewport().get_visible_rect()
	var off: Array = []
	for l in _labels(s):
		if not vp.encloses(_rect(l)):
			off.append("%s @ %s" % [l.text.substr(0, 30), _rect(l).position])
	assert_eq(off, [], "the Summary drew labels outside the 1280x720 screen")


func test_the_end_of_the_panel_is_what_the_player_needed() -> void:
	var s: Control = await _build_summary(LONG)
	var texts: PackedStringArray = []
	for l in _labels(s):
		texts.append(l.text)
	var joined := "\n".join(texts)
	assert_string_contains(joined, "SESSION GRADE", "CONTROL: the grade row exists")
	assert_string_contains(joined, "PERMADEAD", "CONTROL: the permadeath row exists")
	assert_string_contains(joined, "Press ", "CONTROL: the dismiss hint exists")
	var vp: Rect2 = s.get_viewport().get_visible_rect()
	for l in _labels(s):
		if l.text in ["SESSION GRADE", "PERMADEAD"] or l.text.begins_with("ACHIEVEMENTS") or l.text.begins_with("Press "):
			assert_true(vp.encloses(_rect(l)), "%s is off screen on a long session" % l.text)


## Label boxes include line padding taller than a row, so box overlap is not what a player sees. Same-row TEXT spans are.
func _ink(l: Label) -> Vector2:
	var r: Rect2 = l.get_global_rect()
	var w: float = l.get_minimum_size().x
	if l.horizontal_alignment == HORIZONTAL_ALIGNMENT_RIGHT:
		return Vector2(r.position.x + r.size.x - w, r.position.x + r.size.x)
	return Vector2(r.position.x, r.position.x + w)


func test_two_columns_do_not_overlap() -> void:
	var s: Control = await _build_summary(LONG)
	var ls: Array = _labels(s)
	var hits: Array = []
	for i in ls.size():
		for j in range(i + 1, ls.size()):
			if absf(ls[i].get_global_rect().position.y - ls[j].get_global_rect().position.y) > 4.0:
				continue
			var a: Vector2 = _ink(ls[i])
			var b: Vector2 = _ink(ls[j])
			if a.x < b.y - 1 and b.x < a.y - 1:
				hits.append("%s / %s" % [ls[i].text.substr(0, 20), ls[j].text.substr(0, 20)])
	assert_eq(hits, [], "text from two columns collides on the same row")


func test_a_short_session_keeps_one_column() -> void:
	var s: Control = await _build_summary(SHORT)
	var panel: Control = null
	for c in s.get_children():
		if c is Control and c.size.x > 100.0:
			panel = c
	assert_almost_eq(panel.size.x, 520.0, 0.5, "CONTROL: a session that fits must keep the original 520-px single column")
