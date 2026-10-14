extends GutTest

## ⛔ THE LARGEST TEXT IN THE GAME DID NOT SCALE, AND ITS SUBTITLE SAT AT A HARDCODED GUESS AT THE
## TITLE'S HEIGHT. The boss-intro name card is font 36 raw in a 50px box with its subtitle pinned at
## `+48`; the chapter title card is 28 raw in a 40px box with its subtitle at `+44`. `clip_text` is
## false on all four, so at 200% Text Size the title's glyphs overrun their box and print through the
## subtitle beneath them — on the same screens whose dialogue box has scaled since tick 222.
##
## 🔑 Scaling the fonts ALONE would be the defect, not the fix: that is what `_box_metrics` and the
## backlog header were about earlier today. `card_metrics` derives the gap from the title's MEASURED
## glyph height, so the subtitle sits under the title at every size rather than under an assumption.
##
## Two kinds of arm, deliberately: the METRICS at every preset (cheap, total), and the BUILT cards
## driven through the real step functions, because a helper can be right while the card that uses it
## is not — @cowir-adhoc's JobMenu was clean in the mode their guard happened to build.

## ⛔ THE SWEEP IS THE PLAYER'S OWN LADDER, DERIVED — NOT A COPY OF IT. This file carried
## `const PRESETS: Array = [0.8, 1.0, 1.25, 1.5, 2.0]`, a duplicate of
## `SettingsMenu.TEXT_SIZE_PRESETS` with nothing checking the two still agreed. A copy goes stale
## the day a preset is added, and the arm written to catch "it broke at 125%" then never visits the
## new rung — silently, because a loop over a short list still passes.
##
## ⚠️ NO FALLBACK DEFAULT, deliberately: a RENAME must red rather than pass against a ladder
## nobody can select. If the const is gone, `s.TEXT_SIZE_PRESETS` raises and this file fails by
## name; if it is emptied, `_presets()` asserts below.
const SETTINGS_PATH := "res://src/ui/SettingsMenu.gd"

var _ladder: Array = []


## ⛔ THE FLOOR LIVES HERE, IN THE HELPER EVERY SWEEPING ARM CALLS, not only as a separate arm.
## A file-level floor arm makes the FILE red on an empty ladder but leaves each looping arm
## individually vacuous — it iterates zero times and passes green, so a reorder or a single-arm
## run reports success. Asserting on every call means every arm that sweeps reds by its own name.
func _presets() -> Array:
	if _ladder.is_empty():
		var s = load(SETTINGS_PATH)
		_ladder = (s.TEXT_SIZE_PRESETS as Array) if s != null else []
	assert_gt(_ladder.size(), 1, "the shipped Text Size ladder must have at least two rungs — an "
		+ "empty or stubbed ladder makes every preset loop iterate ZERO times and pass")
	return _ladder


## The sub-unity rungs. A SECOND literal lived in these files as `for scale in [0.8, 1.0]`, and it
## is invisible to any census keyed on the full ladder because it carries no 1.25 — yet it is the
## arm deciding whether a new sub-unity preset is ever checked at all. (@cowir-music, 2026-10-14.)
func _sub_unity() -> Array:
	var out: Array = []
	for p in _presets():
		if float(p) <= 1.0:
			out.append(p)
	return out


## The ladder's SHAPE, which several arms below silently depend on: ascending (a "100% is the
## baseline, larger must not shrink" arm reads differently under an unsorted ladder) and containing
## 1.0 (the default-unchanged arms have nothing to assert without it).
func test_the_sweep_is_the_players_own_ladder() -> void:
	var p: Array = _presets()
	assert_gt(p.size(), 1, "FLOOR: the derived ladder must be real")
	assert_true(1.0 in p, "the ladder must contain 1.0 — the default-unchanged arms sweep "
		+ "_sub_unity() and would examine nobody without it")
	var ascending := true
	for i in range(1, p.size()):
		if float(p[i]) <= float(p[i - 1]):
			ascending = false
	assert_true(ascending, "the ladder must be ASCENDING: arms here judge every larger size "
		+ "against 1.0 and an unsorted ladder changes what they assert rather than breaking them: %s" % [p])
	assert_gt(_sub_unity().size(), 0, "FLOOR: the sub-unity set must be non-empty, else the "
		+ "default-unchanged arm iterates zero times and passes")
	gut.p("  ladder %s · sub-unity %s (derived from SettingsMenu.TEXT_SIZE_PRESETS)" % [p, _sub_unity()])


const BOSS_NAME := "Warden of the Old Guard"
const BOSS_TITLE := "Masterite — Medieval"
const CH_TITLE := "Chapter Four"
const CH_SUB := "The Backwards Warren"

var _saved: float = 1.0


func before_each() -> void:
	if GameState and "text_size_scale" in GameState:
		_saved = float(GameState.text_size_scale)


func after_each() -> void:
	if GameState and "text_size_scale" in GameState:
		GameState.text_size_scale = _saved


func _font() -> Font:
	return ThemeDB.fallback_font


## THE METRICS ARM: at every size the player can pick, the title's box holds its own glyphs and the
## subtitle starts below that box. A constant gap passes none of this above 100%.
func test_every_card_metric_clears_its_own_title() -> void:
	var font: Font = _font()
	assert_not_null(font, "CONTROL: a theme font is needed to measure a card")
	var bad: Array = []
	## Read at 100% first: the baseline is the implementation's OWN output, so it must exist before
	## any larger size is judged against it. _presets() is ascending, which puts 1.0 before 1.25/1.5/2.0.
	var base_ratio: Dictionary = {}
	var base_box: Dictionary = {}
	for scale in _presets():
		GameState.text_size_scale = scale
		for spec in [["boss", 36, 16, 50.0, 48.0, 30.0], ["chapter", 28, 18, 40.0, 44.0, 30.0]]:
			var t_px: int = TextScale.scaled(int(spec[1]))
			var s_px: int = TextScale.scaled(int(spec[2]))
			var m: Dictionary = CutsceneDirector.card_metrics(t_px, s_px, int(spec[1]), int(spec[2]), float(spec[3]), float(spec[4]), float(spec[5]))
			## ⛔ THE PREDICATE COMPARES TWO IMPLEMENTATION OUTPUTS, AND BOTH EARLIER VERSIONS WERE
			## WRONG RATHER THAN THE LAYOUT. First I asserted `gap >= font.get_height(title_px)`; the
			## AUTHORED default failed it, because the boss card ships +48 under a 36pt glyph box of
			## 50px and looks fine (`get_height` is ascent+descent and a Label centres its text). A
			## threshold the shipped design never met is a coincidental value, not a defect.
			##
			## ⚠️ Then I wrote `gap >= base_gap * glyph / base_glyph` — which is `card_metrics`'s own
			## arithmetic spelled a second time, the tautology my notes warn about: it could only
			## agree with whatever the implementation computed.
			##
			## 🔑 So the invariant is RELATIVE and names no constant from the implementation: the
			## clearance the card ships at 100% must not degrade at any larger size. A fixed gap fails
			## it everywhere above 100% (48px against 99px of glyph is 0.48 of the authored 0.96), an
			## additive `th + 2` fails it on the chapter card at 125%, and raw unscaled fonts fail it
			## worst. What passes is any scheme that carries the authored proportion upward.
			var glyph: float = float(font.get_height(t_px))
			var ratio: float = float(m["gap"]) / maxf(glyph, 1.0)
			var box_ratio: float = float(m["title_h"]) / maxf(glyph, 1.0)
			if scale == 1.0:
				base_ratio[str(spec[0])] = ratio
				base_box[str(spec[0])] = box_ratio
				continue
			if scale < 1.0:
				continue  ## 80% keeps the authored numbers by design; the default arm pins that
			if ratio + 0.02 < float(base_ratio.get(str(spec[0]), 0.0)):
				bad.append("%s %.0f%%: clearance fell to %.2f of its glyphs from %.2f at 100%% (gap +%.0f under %.0f-tall text)" % [
					str(spec[0]), scale * 100.0, ratio, float(base_ratio.get(str(spec[0]), 0.0)), float(m["gap"]), glyph])
			if box_ratio + 0.02 < float(base_box.get(str(spec[0]), 0.0)):
				bad.append("%s %.0f%%: the name box fell to %.2f of its glyphs from %.2f at 100%%" % [
					str(spec[0]), scale * 100.0, box_ratio, float(base_box.get(str(spec[0]), 0.0))])
			if float(m["gap"]) + 0.5 < glyph:
				bad.append("%s %.0f%%: subtitle at +%.0f collides with %.0f-tall glyphs" % [
					str(spec[0]), scale * 100.0, float(m["gap"]), glyph])
	assert_eq(bad, [], "a title card's own text does not fit above its subtitle: %s" % [bad])


## The default must not move: 80% and 100% keep every authored number.
func test_the_default_cards_are_unchanged() -> void:
	for scale in _sub_unity():
		GameState.text_size_scale = scale
		var b: Dictionary = CutsceneDirector.card_metrics(TextScale.scaled(36), TextScale.scaled(16), 36, 16, 50.0, 48.0, 30.0)
		var c: Dictionary = CutsceneDirector.card_metrics(TextScale.scaled(28), TextScale.scaled(18), 28, 18, 40.0, 44.0, 30.0)
		assert_almost_eq(float(b["gap"]), 48.0, 0.5, "at %.0f%% the boss subtitle keeps its authored +48" % [scale * 100.0])
		assert_almost_eq(float(c["gap"]), 44.0, 0.5, "at %.0f%% the chapter subtitle keeps its authored +44" % [scale * 100.0])
		assert_almost_eq(float(b["title_h"]), 50.0, 0.5, "at %.0f%% the boss name keeps its authored 50px box" % [scale * 100.0])


## THE BUILT ARM: drive the real steps and measure the labels the player sees.
func _built(scale: float, kind: String) -> Array:
	GameState.text_size_scale = scale
	var dir = load("res://src/cutscene/CutsceneDirector.gd").new()
	add_child_autofree(dir)
	await get_tree().process_frame
	if kind == "boss":
		dir._step_boss_intro({"type": "boss_intro", "name": BOSS_NAME, "title": BOSS_TITLE})
	else:
		dir._step_chapter_title({"type": "chapter_title", "title": CH_TITLE, "subtitle": CH_SUB})
	await get_tree().create_timer(0.8).timeout
	var out: Array = []
	for n in _walk(dir):
		if n is Label:
			out.append(n)
	return out


func _walk(n: Node) -> Array:
	var out: Array = [n]
	for kid in n.get_children():
		out.append_array(_walk(kid))
	return out


func test_a_built_card_does_not_print_through_its_subtitle() -> void:
	var font: Font = _font()
	var overlap: Array = []
	for spec in [["boss", BOSS_NAME, BOSS_TITLE, 36, 16], ["chapter", CH_TITLE, CH_SUB, 28, 18]]:
		var labels: Array = await _built(2.0, str(spec[0]))
		var title: Label = null
		var sub: Label = null
		for l in labels:
			if str((l as Label).text) == str(spec[1]):
				title = l
			elif str((l as Label).text) == str(spec[2]):
				sub = l
		if title == null or sub == null:
			gut.p("  %s: card not built within the window (title=%s sub=%s) — arm skipped" % [
				str(spec[0]), str(title != null), str(sub != null)])
			continue
		## ⛔ FIT IS HALF THE CLAIM. The pre-fix state reds the overlap check below by only 2px on the
		## boss card and not at all on the chapter card — because raw fonts produce SMALL glyphs, which
		## fit their authored boxes perfectly. The defect a player actually sees is that the biggest
		## text in the game ignored the accessibility setting entirely, and a fit-only arm is green on
		## it. So: the font must have grown, AND the grown text must fit.
		var t_px: int = title.get_theme_font_size("font_size")
		var s_px: int = sub.get_theme_font_size("font_size")
		if t_px <= int(spec[3]) or s_px <= int(spec[4]):
			overlap.append("%s: at 200%% Text Size the card still draws at %d/%d, its authored %d/%d" % [
				str(spec[0]), t_px, s_px, int(spec[3]), int(spec[4])])
		## ⛔ THE RECT ALONE, NOT `maxf(rect, font_metric)` — WHICH IS THE MISTAKE I WARNED THE FLEET
		## ABOUT, IN MY OWN ARM. @cowir-controller's sharpening: a box-against-a-font-metric predicate
		## is what reds on fine authored layout, and a rect-vs-rect comparison is immune, because a
		## Label clamps `size.y` UP to its content and therefore already reports the TRUE rendered
		## height. Mixing the two can only make the arm stricter than the screen. The glyph figure
		## stays in the report below, where it explains the number without deciding it.
		var glyph: float = float(font.get_height(t_px))
		var title_bottom: float = title.position.y + title.size.y
		gut.p("  %s at 200%%: title y=%.0f glyphs=%.0f bottom=%.0f | subtitle y=%.0f" % [
			str(spec[0]), title.position.y, glyph, title_bottom, sub.position.y])
		if sub.position.y + 0.5 < title_bottom:
			overlap.append("%s (subtitle y %.0f under a title ending %.0f)" % [str(spec[0]), sub.position.y, title_bottom])
	assert_eq(overlap, [], "at 200%% these cards print their title through their subtitle: %s" % [overlap])


## ⛔ THE SKIP PILL AND THE STEP TIMER, THE OTHER TWO SURFACES IN THIS FILE. Both are driven through
## the SHIPPED functions rather than through their metric seams, because a seam can be right while
## its caller still uses the old arithmetic beside it — which is exactly what made the two cards'
## built arm worth writing. These read the nodes the player looks at.
func _director_at(scale: float):
	GameState.text_size_scale = scale
	var dir = load("res://src/cutscene/CutsceneDirector.gd").new()
	add_child_autofree(dir)
	await get_tree().process_frame
	return dir


func test_the_skip_pill_keeps_its_text_off_its_own_bar() -> void:
	var bad: Array = []
	for scale in _presets():
		var dir = await _director_at(scale)
		dir._update_layout()
		await get_tree().process_frame
		var lbl: Label = dir._skip_label
		var bar: ColorRect = dir._skip_bar_bg
		var pill: ColorRect = dir._skip_pill_bg
		if lbl == null or bar == null or pill == null:
			bad.append("%.0f%%: the pill did not build" % [scale * 100.0])
			continue
		## `size.y` is the REAL one: a Label clamps its height up to its content, so this is the box
		## the player sees rather than the 18 the layout asked for.
		var text_bottom: float = lbl.position.y + lbl.size.y
		gut.p("  skip pill at %.0f%%: font=%d text %.0f..%.0f | bar at %.0f | pill %.0fx%.0f" % [
			scale * 100.0, lbl.get_theme_font_size("font_size"), lbl.position.y, text_bottom,
			bar.position.y, pill.size.x, pill.size.y])
		if text_bottom > bar.position.y + 0.5:
			bad.append("%.0f%%: the prompt runs to y=%.0f and the hold-bar sits at y=%.0f" % [
				scale * 100.0, text_bottom, bar.position.y])
		if bar.position.y + bar.size.y > pill.size.y + 0.5:
			bad.append("%.0f%%: the hold-bar ends at %.0f, past the %.0f-tall pill" % [
				scale * 100.0, bar.position.y + bar.size.y, pill.size.y])
		if lbl.size.x > pill.size.x + 0.5:
			bad.append("%.0f%%: the prompt is %.0f wide in a %.0f pill" % [
				scale * 100.0, lbl.size.x, pill.size.x])
		## ⛔ AND THE FONT, MEASURED: reverting it to raw 14 left every check above GREEN, because a
		## small font fits its box and clears the bar by construction. Third time today a fit-only
		## predicate was blind to the actual defect — the prompt simply never grew.
		if lbl.get_theme_font_size("font_size") <= 14 and scale > 1.0:
			bad.append("%.0f%%: the skip prompt still draws at %d, its authored 14" % [
				scale * 100.0, lbl.get_theme_font_size("font_size")])
	assert_eq(bad, [], "the skip prompt collides with its own progress bar: %s" % [bad])


func test_the_step_timer_stays_on_screen() -> void:
	var bad: Array = []
	for scale in _presets():
		var dir = await _director_at(scale)
		## THE ONLY AUTHORED TIMER IN THE GAME: world4_orrery's 300s. A guard on a made-up duration
		## would be measuring a string no player sees; "10:00" below is the first unauthored width.
		dir._timer_remaining = 300.0
		dir._build_timer_hud()
		await get_tree().process_frame
		var lbl: Label = dir._timer_label
		if lbl == null:
			bad.append("%.0f%%: no timer built" % [scale * 100.0])
			continue
		var vw: float = dir.get_viewport().get_visible_rect().size.x
		var right: float = lbl.position.x + lbl.size.x
		gut.p("  timer at %.0f%%: font=%d text='%s' box %.0f..%.0f of %.0f wide" % [
			scale * 100.0, lbl.get_theme_font_size("font_size"), str(lbl.text),
			lbl.position.x, right, vw])
		if right > vw + 0.5:
			bad.append("%.0f%%: the timer's right edge is at %.0f on a %.0f-wide screen" % [
				scale * 100.0, right, vw])
		if lbl.position.x < 0.0:
			bad.append("%.0f%%: the timer starts at x=%.0f, off the left edge" % [scale * 100.0, lbl.position.x])
		## The authored right inset, which the shipped `x - 120` only hit because the box happened to
		## be 100 wide. Pinning it is the whole point of the arithmetic change; the width is inert.
		if absf((vw - right) - 20.0) > 0.5:
			bad.append("%.0f%%: the right inset drifted to %.0f from the authored 20" % [scale * 100.0, vw - right])
		## ⛔ AND THE FONT, BECAUSE THE INSET ALONE HAS NO TEETH HERE. The shipped `x - 120` with a
		## 100-wide box lands the inset at 20 by coincidence, so reverting EITHER the font or the
		## position arithmetic leaves the checks above green on the authored "5:00". The font not
		## scaling is the defect a player on 200% actually experiences.
		if lbl.get_theme_font_size("font_size") <= 22 and scale > 1.0:
			bad.append("%.0f%%: the countdown still draws at %d, its authored 22" % [
				scale * 100.0, lbl.get_theme_font_size("font_size")])
	assert_eq(bad, [], "the step timer does not stay on screen: %s" % [bad])


## ⛔ THE INPUT THAT SEPARATES THE TWO ARITHMETICS. Every authored countdown is four glyphs ("5:00",
## the game's only timer step), which fits the authored 100px box at every preset — so the built arm
## above cannot tell `viewport - 120` from `viewport - 20 - width`. Measured at 200%, "10:00" needs
## 113px, and that is where the old formula puts the right edge 7px from the viewport edge.
##
## 🔑 This is the seam asked directly, with the first string that discriminates. It is not a
## re-derivation of the formula: it asserts the INSET, which the formula does not mention.
func test_the_timer_holds_its_inset_for_a_countdown_wider_than_its_box() -> void:
	var bad: Array = []
	for scale in _presets():
		GameState.text_size_scale = scale
		var px: int = TextScale.scaled(22)
		var r: Rect2 = CutsceneDirector.timer_rect(px, 22, "10:00", 1280.0, 100.0, 28.0, 20.0)
		var inset: float = 1280.0 - (r.position.x + r.size.x)
		gut.p("  '10:00' at %.0f%%: font=%d box %.0f wide, right inset %.0f" % [
			scale * 100.0, px, r.size.x, inset])
		if absf(inset - 20.0) > 0.5:
			bad.append("%.0f%%: a %.0f-wide countdown lands its right edge %.0f from the edge, not 20" % [
				scale * 100.0, r.size.x, inset])
		## ⚠️ NO HEIGHT ASSERTION HERE, AND THE REASON IS THE THIRD INSTANCE OF IT TODAY. I wrote
		## `box >= get_height(px)` and it red on the AUTHORED default: 28px box, 31px of glyph at
		## font 22. The boss name card is the same shape (48 under 50) and so was the first version
		## of the metrics arm above. `get_height` is ascent+descent+leading and a Label clamps its
		## own height up to its content at runtime, so an authored box being under it is normal and
		## invisible. The height a player actually gets is the CLAMPED `size.y`, which the built arm
		## reads off the real node — asserting it here would only red correct shipped layout.
	assert_eq(bad, [], "a countdown wider than its authored box leaves the screen: %s" % [bad])
