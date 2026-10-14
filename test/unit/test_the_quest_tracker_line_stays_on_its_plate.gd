extends GutTest

## ⛔ 424px OF QUEST PROSE DREW OVER THE WORLD WITH NO BACKING, AT THE SHIPPED DEFAULT, and the HUD
## ignored Text Size entirely. Measured on the built node before the fix, chicken quest at 3/7:
##
##   side label  box 330  rect 668.0 x 20.0  font 11  122 chars   +338px past its box
##   bg plate    x 12..260 (248 wide, shrink-wrapped to the MAIN line only)
##   side text   x 16..684 against a plate ending at 260  ->  424px unbacked
##   and IDENTICAL at 80/100/125/150/200% — the fonts never moved
##
## 🔑 TWO DEFECTS, ONE ITEM (cowir-main's ruling): the overflow is DEFAULT-VISIBLE and the scaling is
## the census item. The plate mechanism was already font-aware and already derived — it just
## considered one of the two lines.
##
## ⚠️ FIXTURE: the chicken quest at 3/7 drives the BEHAVIOUR because it is the only objective that
## receives BOTH runtime annotations (`fetch_progress` appends, `QuestChicken.annotate_objective`
## prepends). Its 125 chars TIE for longest with world4_words_per_conversation, so the WIDTH bound is
## DERIVED from every authored objective rather than pinned to either — new content moves the arm.

const ChickenScript := preload("res://src/exploration/QuestChicken.gd")
const TrackerScript := preload("res://src/exploration/QuestTracker.gd")
const QUEST := "world1_one_chicken_problem"
const PRESETS: Array = [0.8, 1.0, 1.25, 1.5, 2.0]

var _saved: float = 1.0
var _saved_lp: String = ""


func before_each() -> void:
	_saved = float(GameState.text_size_scale) if "text_size_scale" in GameState else 1.0
	_saved_lp = str(QuestSystem.last_progressed_quest_id)
	GameState.quests.clear()


func after_each() -> void:
	if "text_size_scale" in GameState:
		GameState.text_size_scale = _saved
	QuestSystem.last_progressed_quest_id = _saved_lp
	GameState.quests.clear()


func _tracker(scale: float, with_side: bool) -> Node:
	GameState.text_size_scale = scale
	if with_side:
		for i in range(ChickenScript.ALL_CHICKEN_IDS.size()):
			GameState.set_story_flag("chicken_caught_" + ChickenScript.ALL_CHICKEN_IDS[i], i < 3)
		var qs: Node = get_tree().root.get_node_or_null("QuestSystem")
		if qs != null:
			qs.accept(QUEST)
	var host := Node.new()
	add_child_autofree(host)
	var t: Node = TrackerScript.new()
	host.add_child(t)
	t.setup(host)
	await get_tree().process_frame
	await get_tree().process_frame
	return t


## Every authored side-quest line, as the tracker composes it. The WIDTH bound comes from here.
func _authored_side_lines() -> Array:
	var out: Array = []
	var d := DirAccess.open("res://data/quests")
	if d == null:
		return out
	for f in d.get_files():
		if not f.ends_with(".json"):
			continue
		var q = JSON.parse_string(FileAccess.get_file_as_string("res://data/quests/%s" % f))
		if not (q is Dictionary):
			continue
		var title: String = str((q as Dictionary).get("title", f.get_basename()))
		for o in (q as Dictionary).get("objectives", []):
			if o is Dictionary:
				out.append("* %s — %s  [10/10]" % [title, str((o as Dictionary).get("description", ""))])
	return out


func test_the_authored_corpus_is_real() -> void:
	var lines: Array = _authored_side_lines()
	assert_gt(lines.size(), 100, "CONTROL: every authored objective must be read, saw %d" % lines.size())
	var worst := ""
	for s in lines:
		if str(s).length() > worst.length():
			worst = str(s)
	gut.p("  %d authored side lines, longest %d chars" % [lines.size(), worst.length()])
	assert_gt(worst.length(), 100, "CONTROL: the worst authored line must be long enough to wrap")


## ⛔ ARM 1 — THE STATE THAT MUST NOT MOVE. @cowir-controller's experience: a pin-the-unchanged arm is
## what catches a 3px drift in a shipped screenshot. The main-line-only plate at 100% is exactly the
## pre-fix baseline: plate 248 x 24 at (12,12), main rect 330 x 22 at (16,13).
func test_arm1_the_main_line_only_state_is_unchanged_at_100() -> void:
	var t = await _tracker(1.0, false)
	var bg: ColorRect = t._bg
	var main: Label = t._label
	gut.p("  100%% main-only: plate %.1f x %.1f at (%.0f,%.0f) · main rect %.1f x %.1f · font %d" % [
		bg.size.x, bg.size.y, bg.position.x, bg.position.y, main.size.x, main.size.y,
		main.get_theme_font_size("font_size")])
	assert_false(t._side_label.visible, "CONTROL: no quest accepted, so the side line must be hidden")
	assert_almost_eq(main.get_theme_font_size("font_size"), 12, 0, "at 100% the main font keeps its authored 12")
	assert_almost_eq(bg.size.y, 24.0, 0.5, "the collapsed plate keeps its authored 24px height")
	## ⛔ DERIVED, NOT PINNED — AND STEP (2) CAUGHT ME PINNING IT. My first version asserted
	## `bg.size.x == 248`, the width for the DEFAULT objective text. That passed alone and FAILED in
	## the full sweep at 133, because the collapsed plate shrink-wraps to whichever objective is
	## current, and `_entry_reached` reads GLOBAL STORY FLAGS that earlier test files leave set. A
	## pinned 248 is a coincidental value whose truth depends on test ORDER — the flakiest shape
	## there is, and it would have reached main as order-dependent noise.
	##
	## 🔑 The invariant is the RELATIONSHIP the shrink-wrap asserts: the plate's right edge is the
	## main line's MEASURED text plus the authored inset, whatever that text happens to be.
	var font: Font = main.get_theme_font("font")
	assert_not_null(font, "CONTROL: a theme font is needed or the derivation below says nothing")
	var text_w: float = font.get_string_size(main.text, HORIZONTAL_ALIGNMENT_LEFT, -1,
		main.get_theme_font_size("font_size")).x
	var want: float = (16.0 + text_w + 20.0) - 12.0   ## right edge minus the plate's left offset
	gut.p("    derived: main text [%s] is %.1fpx -> plate should be %.1f wide, is %.1f" % [
		main.text, text_w, want, bg.size.x])
	assert_almost_eq(bg.size.x, want, 1.0,
		"the collapsed plate must shrink-wrap to the main line's measured text plus the authored 20px inset")


## ⛔ ARM 2 — THE DEFECT. The side line must sit ON the plate, with the authored 20px margin.
## Zero margin is not a pass (@cowir-controller measured 481 against 481 and a `>` test passed).
func test_arm2_the_side_line_stays_on_its_plate_at_every_preset() -> void:
	var bad: Array = []
	for scale in PRESETS:
		var t = await _tracker(scale, true)
		var bg: ColorRect = t._bg
		var side: Label = t._side_label
		if not side.visible:
			bad.append("%.0f%%: the side line did not show, so nothing was measured" % [scale * 100.0])
			continue
		var text_right: float = side.position.x + side.size.x
		var text_bottom: float = side.position.y + side.size.y
		var plate_right: float = bg.position.x + bg.size.x
		var plate_bottom: float = bg.position.y + bg.size.y
		gut.p("  %5.0f%% font %2d  side rect %6.1f x %5.1f  text right %6.1f / bottom %6.1f  plate right %6.1f / bottom %6.1f" % [
			scale * 100.0, side.get_theme_font_size("font_size"), side.size.x, side.size.y,
			text_right, text_bottom, plate_right, plate_bottom])
		if text_right > plate_right - 19.5:
			bad.append("%.0f%%: side text ends %.0f, plate ends %.0f — margin %.0f, authored is 20" % [
				scale * 100.0, text_right, plate_right, plate_right - text_right])
		if text_bottom > plate_bottom + 0.5:
			bad.append("%.0f%%: side text runs to %.0f, past a plate ending %.0f" % [
				scale * 100.0, text_bottom, plate_bottom])
	assert_eq(bad, [], "the side-quest line leaves its plate: %s" % [bad])


## ⛔ ARM 3 — THE FONTS GREW. A fit-only arm is green on the raw-font defect, because small text fits
## by construction (cowir-main's three-arm rule; I measured 2 of 4 surfaces with no teeth earlier).
func test_arm3_both_fonts_follow_the_setting() -> void:
	var seen: Array = []
	for scale in [0.8, 1.0, 2.0]:
		var t = await _tracker(scale, true)
		seen.append([scale, t._label.get_theme_font_size("font_size"), t._side_label.get_theme_font_size("font_size")])
		gut.p("  %5.0f%%  main font %2d  side font %2d" % [scale * 100.0, seen[-1][1], seen[-1][2]])
	assert_lt(int(seen[0][1]), int(seen[1][1]), "80%% must draw the main line SMALLER than 100%%")
	assert_gt(int(seen[2][1]), int(seen[1][1]), "200%% must draw the main line LARGER than 100%%")
	assert_gt(int(seen[2][2]), int(seen[1][2]), "200%% must draw the side line LARGER than 100%%")


## ⛔ ARM 4 — reserved_rect, BOTH DIRECTIONS. TutorialHint:168 and ObjectiveArrow:96 position
## themselves clear of it, and NO guard covered QuestTracker's provider. It must cover the drawn text
## (or they overlap quest prose) and must NOT over-reserve (or they are shoved for nothing) — and
## over-reserving is the state it was in BEFORE, so a coverage-only arm would have certified it.
func test_arm4_reserved_rect_covers_the_text_without_over_reserving() -> void:
	var bad: Array = []
	for scale in PRESETS:
		var t = await _tracker(scale, true)
		var rr: Rect2 = t.reserved_rect()
		var side: Label = t._side_label
		var bg: ColorRect = t._bg
		var text := Rect2(side.position, side.size)
		gut.p("  %5.0f%% reserved %s · side %s · plate %s" % [
			scale * 100.0, str(rr), str(text), str(Rect2(bg.position, bg.size))])
		if not rr.encloses(text):
			bad.append("%.0f%%: reserved %s does not cover the drawn side text %s" % [scale * 100.0, rr, text])
		var union: Rect2 = Rect2(bg.position, bg.size).merge(text)
		if rr.size.x > union.size.x + 1.0 or rr.size.y > union.size.y + 1.0:
			bad.append("%.0f%%: reserved %s is larger than plate-union-text %s — the arrow and hint are shoved for nothing" % [
				scale * 100.0, rr, union])
	assert_eq(bad, [], "reserved_rect is wrong in one direction or the other: %s" % [bad])
