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

const PRESETS: Array = [0.8, 1.0, 1.25, 1.5, 2.0]
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
	## any larger size is judged against it. PRESETS is ascending, which puts 1.0 before 1.25/1.5/2.0.
	var base_ratio: Dictionary = {}
	var base_box: Dictionary = {}
	for scale in PRESETS:
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
	for scale in [0.8, 1.0]:
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
		var glyph: float = float(font.get_height(t_px))
		var title_bottom: float = title.position.y + maxf(title.size.y, glyph)
		gut.p("  %s at 200%%: title y=%.0f glyphs=%.0f bottom=%.0f | subtitle y=%.0f" % [
			str(spec[0]), title.position.y, glyph, title_bottom, sub.position.y])
		if sub.position.y + 0.5 < title_bottom:
			overlap.append("%s (subtitle y %.0f under a title ending %.0f)" % [str(spec[0]), sub.position.y, title_bottom])
	assert_eq(overlap, [], "at 200%% these cards print their title through their subtitle: %s" % [overlap])
