extends GutTest

## A level-up victory card's top line overflowed its card at large Text Sizes, and only AFTER the
## EXP counter finished counting up — the card is built with "Name  +0 EXP" (which fits at every
## preset) and tweened to "Name  +99999 EXP  ★ Lv.11". Measured overflow past the card, before:
##
##                                 100%   125%   150%   200%
##   Fighter  +99  (no level-up)   -176   -152   -122    -77
##   Fighter  +999   ★ Lv.11       -113    -76    -26    +49
##   Scriptweaver +999  ★ Lv.11     -76    -29    +32   +124
##   Scriptweaver +99999 ★ Lv.11    -61    -11    +55   +154
##
## The driver is the `★ Lv.N` suffix, not the EXP digits: with no level-up nothing overflows at any
## preset. `Scriptweaver` is the longest job name in jobs.json and a level-up is the common case
## after a boss.
##
## CARD_W/CARD_H now scale with Text Size, CAPPED against the room left UNDER the loot strip, so
## the column reads title -> strip -> cards at every size. Measured cap: 1.159 at 200%.
##
## The strip's rect is reserved BEFORE `_build_loot_strip` awaits its layout frame. Reordering the
## two build calls was not enough on its own: that function returns at its `await`, so `_strip_rect`
## was still set a frame after the cards had been placed.
##
## ⚠️ `_title_rest` IS NOT IN THESE ARMS and that is deliberate — it is where the title sits BEFORE
## it docks, mid-screen, and every card passes through it during the slam. The settled layout is
## what a player reads, so the arms pin the DOCKED title and the strip.
##
## Once capped, the card at 200% can no longer hold the worst authored line (+101px of content), so
## the TopLine trims on a WORD boundary — the last resort, applied to what is left after growth.

const OverlayScript = preload("res://src/battle/VictoryOverlay.gd")
const PRESETS: Array = [0.8, 1.0, 1.25, 1.5, 2.0]
const LABELS: Array = ["80%", "100%", "125%", "150%", "200%"]
## What VictoryOverlay builds once the EXP counter lands, with the corpus worst case in it.
const WORST_TOP := "Scriptweaver  +99999 EXP  ★ Lv.11"

var _orig_scale: float = 1.0


class FakeScene extends Node2D:
	var party_sprite_nodes: Array = []
	var party_animators: Array = []


func before_each() -> void:
	var gs = get_tree().root.get_node_or_null("GameState")
	if gs != null and "text_size_scale" in gs:
		_orig_scale = float(gs.text_size_scale)


func after_each() -> void:
	var gs = get_tree().root.get_node_or_null("GameState")
	if gs != null and "text_size_scale" in gs:
		gs.text_size_scale = _orig_scale


func _scene() -> FakeScene:
	var sc := FakeScene.new()
	add_child_autofree(sc)
	var xs := [860.0, 900.0, 840.0, 800.0, 760.0]
	var ys := [150.0, 260.0, 360.0, 450.0, 560.0]
	for i in 5:
		var s := Node2D.new()
		s.position = Vector2(xs[i], ys[i])
		sc.add_child(s)
		sc.party_sprite_nodes.append(s)
	return sc


## Five level-ups with the longest job name and a 5-digit award — the corpus worst case.
func _results() -> Dictionary:
	var cr: Array = []
	for i in 5:
		cr.append({"name": "Scriptweaver", "job_name": "fighter", "is_alive": true,
			"exp_gained": 99999, "job_exp_before": 40, "exp_to_next": 200,
			"leveled_up": true, "job_level": 11, "job_exp": 30, "stat_gains": {"HP": 46}})
	return {"char_results": cr, "total_gold": 999999, "item_drops": [], "bonuses": [], "injuries": []}


func _overlay_at(scale: float) -> Control:
	var gs = get_tree().root.get_node_or_null("GameState")
	if gs != null and "text_size_scale" in gs:
		gs.text_size_scale = scale
	var sc := _scene()
	var o = OverlayScript.new()
	sc.add_child(o)
	o.build(_results(), sc)
	await wait_frames(4)
	return o


## Found by STRUCTURE — a card is the Control that owns a "TopLine" — not by a width threshold.
## A `custom_minimum_size.x > 300` finder silently returns nothing once the cards are smaller than
## the threshold, which turned a mutation's real failure into a bare "cards must exist".
func _cards(o: Node, out: Array) -> void:
	for c in o.get_children():
		if c is Control and (c as Control).find_child("TopLine", true, false) != null:
			out.append(c)
		else:
			_cards(c, out)


func test_control_five_cards_are_built_at_every_size() -> void:
	for i in PRESETS.size():
		var o: Control = await _overlay_at(PRESETS[i])
		var cards: Array = []
		_cards(o, cards)
		assert_eq(cards.size(), 5, "Text Size %s must build one card per party member" % [LABELS[i]])


func test_one_hundred_percent_is_unchanged() -> void:
	## cowin-main's first condition. At and below 100% the scale is exactly 1.0, so every geometry
	## call returns the original literal and the screen is pixel-identical to before this change.
	for scale in [0.8, 1.0]:
		var o: Control = await _overlay_at(scale)
		assert_almost_eq(o._cscale, 1.0, 0.0001,
			"at Text Size %.0f%% the cards must not scale at all" % [scale * 100.0])
		assert_almost_eq(o._cw(), OverlayScript.CARD_W, 0.0001, "card width must be the literal")
		assert_almost_eq(o._ch(), OverlayScript.CARD_H, 0.0001, "card height must be the literal")


func test_the_post_tween_top_line_is_never_drawn_outside_its_card() -> void:
	## THE DEFECT. Measured on the FINAL string, not the "+0 EXP" the card is built with — the
	## initial text fits at every preset, which is why this never showed in a static shot.
	##
	## ⚠️ Drawn width, not content width: where the label clips, its box IS what reaches the screen.
	## Asking the font for the content width unconditionally would report the TRIM as an overflow.
	for i in PRESETS.size():
		var o: Control = await _overlay_at(PRESETS[i])
		var cards: Array = []
		_cards(o, cards)
		assert_gt(cards.size(), 0, "PRECONDITION: cards must exist")
		for c in cards:
			var top: Label = (c as Control).find_child("TopLine", true, false)
			assert_not_null(top, "CONTROL: each card must have a TopLine")
			if top == null:
				continue
			var f: Font = top.get_theme_font("font")
			var fs: int = top.get_theme_font_size("font_size")
			if f == null or fs <= 0:
				continue
			var drawn: float = top.size.x if top.clip_text \
				else f.get_string_size(WORST_TOP, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			assert_lte(drawn, top.size.x,
				"Text Size %s: the finished line draws %.0f px in a %.0f px box" % [
					LABELS[i], drawn, top.size.x])
			assert_lte(top.global_position.x + top.size.x,
				(c as Control).global_position.x + (c as Control).size.x + 0.5,
				"Text Size %s: the top line's box ends outside its card" % [LABELS[i]])


func test_growth_alone_holds_the_whole_line_up_to_one_fifty() -> void:
	## What the GROWTH buys, separately from the trim: through 150% the worst authored line fits
	## with nothing cut. Before the change it was already +55px over at 150%. Only at 200%, where
	## the fit cap binds hardest, does anything need trimming — the trim is the last resort, not
	## the mechanism.
	for i in 4:
		var o: Control = await _overlay_at(PRESETS[i])
		var cards: Array = []
		_cards(o, cards)
		for c in cards:
			var top: Label = (c as Control).find_child("TopLine", true, false)
			if top == null:
				continue
			var f: Font = top.get_theme_font("font")
			var fs: int = top.get_theme_font_size("font_size")
			if f == null or fs <= 0:
				continue
			var need: float = f.get_string_size(WORST_TOP, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			assert_lte(need, top.size.x,
				"Text Size %s: the finished line needs %.0f px untrimmed and its box is %.0f" % [
					LABELS[i], need, top.size.x])


func test_the_five_card_stack_stays_on_screen_and_apart() -> void:
	for i in PRESETS.size():
		var o: Control = await _overlay_at(PRESETS[i])
		var cards: Array = []
		_cards(o, cards)
		var rects: Array = []
		for c in cards:
			var cc := c as Control
			rects.append(Rect2(cc.global_position, cc.size))
			assert_lte(cc.global_position.y + cc.size.y, 720.0,
				"Text Size %s: a card ends at %.0f, past the 720px screen" % [
					LABELS[i], cc.global_position.y + cc.size.y])
		for a2 in rects.size():
			for b2 in range(a2 + 1, rects.size()):
				assert_false((rects[a2] as Rect2).intersects(rects[b2] as Rect2),
					"Text Size %s: cards %d and %d overlap" % [LABELS[i], a2, b2])


func test_no_card_touches_the_docked_title_or_the_loot_strip() -> void:
	## The column is title -> loot strip -> cards, each strictly below the last, at EVERY size.
	## Before this, the top card was drawn through the VICTORY title at 200% and the strip sat
	## across the card 1/2 seam covering "LEVEL UP! HP +46".
	for i in PRESETS.size():
		var o: Control = await _overlay_at(PRESETS[i])
		var cards: Array = []
		_cards(o, cards)
		assert_gt(cards.size(), 0, "PRECONDITION: cards must exist")
		var strip := o.find_child("LootStrip", true, false) as Control
		assert_not_null(strip, "CONTROL: this fixture must produce a loot strip to clear")
		for c in cards:
			var cc := c as Control
			var r := Rect2(cc.global_position, cc.size)
			if o._title_docked.has_area():
				assert_false(r.intersects(o._title_docked),
					"Text Size %s: a card overlaps the docked title" % [LABELS[i]])
			if strip != null:
				assert_false(r.intersects(Rect2(strip.global_position, strip.size)),
					"Text Size %s: a card overlaps the loot strip" % [LABELS[i]])


func test_the_card_column_lands_where_it_always_did_at_one_hundred_percent() -> void:
	## cowin-main's first condition, pinned as POSITIONS rather than only as a scale factor: the
	## scale being 1.0 does not by itself prove nothing moved. Measured on unmodified main, and the
	## first version of this change shifted them 3px by raising a clamp that places no card at all.
	var o: Control = await _overlay_at(1.0)
	var cards: Array = []
	_cards(o, cards)
	var ys: Array = []
	for c in cards:
		ys.append(int(round((c as Control).global_position.y)))
	ys.sort()
	assert_eq(ys, [155, 237, 319, 401, 483],
		"the 100%% column must land exactly where it does on main, got %s" % [str(ys)])


func test_the_cap_actually_binds_at_the_largest_size() -> void:
	## Without this the cap is untested: a scale that simply followed the font would satisfy every
	## arm above EXCEPT the stack one, and a reader could not tell the cap was doing anything.
	var o: Control = await _overlay_at(2.0)
	assert_gt(o._raw_text_scale(), o._cscale,
		"at 200%% the requested scale (%.3f) must be capped below it, got %.3f" % [
			o._raw_text_scale(), o._cscale])
	assert_gt(o._cscale, 1.0, "and the cards must still have grown, got %.3f" % [o._cscale])


func test_the_top_line_trims_on_a_word_when_even_the_grown_card_is_too_small() -> void:
	## The LAST resort, and only after growth. At the capped 200% scale the worst authored line
	## needs ~101px more than the card can give, so the line has to end somewhere — on a word, with
	## an ellipsis, rather than drawn across the card's border.
	var o: Control = await _overlay_at(2.0)
	var cards: Array = []
	_cards(o, cards)
	assert_gt(cards.size(), 0, "PRECONDITION: cards must exist")
	for c in cards:
		var top: Label = (c as Control).find_child("TopLine", true, false)
		if top == null:
			continue
		assert_true(top.clip_text,
			"the top line must clip, or its width is undone by its own minimum size")
		assert_eq(top.text_overrun_behavior, TextServer.OVERRUN_TRIM_WORD_ELLIPSIS,
			"and must trim on a WORD boundary, so a number is not cut in half")
