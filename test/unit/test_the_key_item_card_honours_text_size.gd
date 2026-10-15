extends GutTest

## Text Size, 2026-10-14: the Zelda-style "Key Item Obtained!" card. All six font sites were raw
## literals and every band on the card was a literal too, so the card ignored the player's Text Size
## completely — at 200% it rendered exactly as it did at 100%.
##
## ⛔ AND SCALING THE FONTS ALONE WOULD HAVE BEEN WORSE THAN LEAVING IT, which is why this guard has
## a FIT half as well as a GROW half. TextScale.apply_tree's own docstring says it: "re-scaling text
## is not re-scaling a LAYOUT". The card pins its continue hint at `panel_h - 22` and its
## description band at a flat 44px, so a grown description is drawn THROUGH the hint and past the
## bottom border — the exact collision this card was already fixed for once, at one scale.
##
## 🔑 A FIT ARM CANNOT SEE A CARD THAT NEVER GREW. Every "nothing overflows" assertion here is
## satisfied by a card that ignores Text Size entirely — that IS the bug, and it is green on a
## fit-only guard. So the growth arms come first and assert that the fonts and the card both get
## bigger; the fit arms are what stop the growth from being an overflow.

## DERIVED from the list the player actually drives, never copied: an arm written for "it broke at
## 125%" never visits a rung added later. Reached through the class_name, so a rename is a PARSE
## error (EC=3, nothing ran) rather than an abort into a vacuous pass — and deliberately with no
## fallback, because a fallback ladder passes every arm against presets nobody can select.
const PRESETS: Array = SettingsMenu.TEXT_SIZE_PRESETS

const ITEMS_JSON := "res://data/items.json"

## The reveal that exercises the "In your bag:" line: a flavour name differing from the canonical
## one is what puts a SIXTH band on the card, which is the tallest layout it can reach.
const FLAVOUR_NAME := "The Cartographer's Last Promise"
const PLAIN_NAME := "Probe Relic"

var _orig_scale: float = 1.0
var _host: Control = null
var _pop = null


func before_each() -> void:
	var gs = get_tree().root.get_node_or_null("GameState")
	if gs != null and "text_size_scale" in gs:
		_orig_scale = float(gs.text_size_scale)


func after_each() -> void:
	_drop()
	var gs = get_tree().root.get_node_or_null("GameState")
	if gs != null and "text_size_scale" in gs:
		gs.text_size_scale = _orig_scale


## Frees the card WITHOUT restoring the scale: a sweep builds one card per rung and the scale is
## about to be set again. after_each() is GUT's, and calling it by hand mid-test both resets the
## scale pointlessly and reads as a teardown that already happened.
func _drop() -> void:
	if _pop != null and is_instance_valid(_pop):
		_pop.queue_free()
	_pop = null
	if _host != null and is_instance_valid(_host):
		_host.queue_free()
	_host = null


func _release() -> void:
	_drop()
	await get_tree().process_frame


func _set_scale(scale: float) -> void:
	var gs = get_tree().root.get_node_or_null("GameState")
	if gs != null and "text_size_scale" in gs:
		gs.text_size_scale = scale


## The ladder's own ends, never the literals 0.8 and 2.0: a sweep that names its rungs stops
## visiting the ladder the day one is added or its ends move.
func _lowest() -> float:
	return float(PRESETS[0]) if not PRESETS.is_empty() else 1.0


func _highest() -> float:
	return float(PRESETS[PRESETS.size() - 1]) if not PRESETS.is_empty() else 1.0


func _descriptions() -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(ITEMS_JSON))
	if not (parsed is Dictionary):
		return {}
	var items: Variant = (parsed as Dictionary).get("items", parsed)
	var out: Dictionary = {}
	if items is Dictionary:
		for k in (items as Dictionary):
			var v = (items as Dictionary)[k]
			if v is Dictionary and str(v.get("description", "")) != "":
				out[str(k)] = str(v["description"])
	return out


## The longest AUTHORED description. The worst case has to come from the data, not the keyboard: a
## fixture longer than anything items.json holds measures an overflow no player can reach.
func _longest() -> String:
	var best := ""
	for k in _descriptions():
		var d: String = str(_descriptions()[k])
		if d.length() > best.length():
			best = d
	return best


## Built AT the live scale: every derived value reads TextScale at call time, so a card built at one
## scale answers only for that one. `show_item` is the shipped entry point, reached through the
## class_name so a rename is a parse error rather than a silent skip.
func _card(scale: float, desc: String, with_bag: bool):
	_set_scale(scale)
	_host = Control.new()
	_host.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_host)
	await get_tree().process_frame
	## `mapped_route` is a real items.json id whose canonical name differs from FLAVOUR_NAME, which
	## is what makes the bag line appear. The other id is deliberately unknown, so that card takes
	## the EMBLEM branch (no sprite, no icon texture) and the emblem's font site is measurable.
	_pop = KeyItemPopup.show_item(_host, {
		"item_id": "mapped_route" if with_bag else "probe_textsize_relic",
		"name": FLAVOUR_NAME if with_bag else PLAIN_NAME,
		"description": desc,
	})
	for _i in 3:
		await get_tree().process_frame
	return _pop


## Labels found BY THEIR TEXT, not by child order: RetroPanel.add_border adds children of its own,
## and an order-indexed lookup silently shifts the day a band is added or the border changes.
func _labels(pop, desc: String) -> Dictionary:
	var out: Dictionary = {"title": null, "name": null, "bag": null, "desc": null, "hint": null}
	if pop == null or not is_instance_valid(pop):
		return out
	var panel = pop.get("_panel")
	if panel == null or not is_instance_valid(panel):
		return out
	for c in panel.get_children():
		if not (c is Label):
			continue
		var t: String = str((c as Label).text)
		if t == "Key Item Obtained!":
			out["title"] = c
		elif t.begins_with("In your bag: "):
			out["bag"] = c
		elif t == FLAVOUR_NAME or t == PLAIN_NAME:
			out["name"] = c
		elif desc != "" and t == desc:
			out["desc"] = c
	out["hint"] = pop.get("_hint")
	return out


## ⛔ `is Label`, NOT `!= null`. `_icon` holds a TextureRect on the sprite and icon branches, and
## `(TextureRect as Label)` is null — so a `!= null` guard passes the check and then calls a method
## on null, which aborts the arm. GUT scores an aborted body as a PASS, so the emblem arm would go
## green on precisely the card whose emblem it could not find.
func _px(l) -> int:
	return int((l as Label).get_theme_font_size("font_size")) if l is Label else -1


## A label's rendered TEXT height, from its OWN resolved font. NEVER Label.size.y: a Label clamps
## its Control rect UP to its content, so a band holding more than it was given reports the larger
## number and "fits" itself. This card was fixed once already for exactly that reason, and the
## single-scale guard beside this one carries the measurement.
func _text_h(l, text: String) -> float:
	if l == null:
		return 0.0
	var f: Font = (l as Label).get_theme_font("font")
	if f == null:
		return 0.0
	var size: int = _px(l)
	if (l as Label).autowrap_mode != TextServer.AUTOWRAP_OFF:
		return f.get_multiline_string_size(
			text, HORIZONTAL_ALIGNMENT_CENTER, (l as Label).size.x, size).y
	return f.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1.0, size).y


# ---------------------------------------------------------------- the control


func test_the_fixture_really_builds_the_card() -> void:
	var longest := _longest()
	assert_gt(longest.length(), 200,
		"CONTROL: the longest authored key-item description must still overrun one band, got %d"
		% longest.length())
	var pop = await _card(1.0, longest, true)
	assert_not_null(pop.get("_panel"), "CONTROL: no card was built")
	var L := _labels(pop, longest)
	for key in ["title", "name", "bag", "desc", "hint"]:
		assert_not_null(L[key],
			"CONTROL: the %s label is not on the card, so every arm that measures it is vacuous" % key)
	if L["desc"] != null:
		assert_gt((L["desc"] as Label).get_line_count(), 3,
			"CONTROL: the description must wrap past one band for the collision arms to mean anything (got %d)"
			% (L["desc"] as Label).get_line_count())


func test_the_emblem_fixture_reaches_the_emblem_branch() -> void:
	## The sixth font site only exists on a card with no sprite AND no icon texture. If an icon
	## ever resolves for the probe id, the emblem arm below would measure a TextureRect's absent
	## font and pass on -1 == -1 rather than failing.
	var pop = await _card(1.0, _longest(), false)
	assert_true(pop.get("_icon") is Label,
		"CONTROL: the no-bag fixture must take the EMBLEM branch; it built a %s, so the emblem's "
		% [pop.get("_icon")] + "font site is unmeasured by this file")


func test_the_preset_ladder_is_the_players_own() -> void:
	## An EMPTY ladder makes every preset loop below iterate zero times and pass. Named rather than
	## counted: a `size() > 3` floor is satisfied by a list with the wrong contents.
	assert_false(PRESETS.is_empty(),
		"the ladder derived empty — every preset loop in this file would pass vacuously")
	assert_true(PRESETS.has(1.0), "the shipped default must be a selectable rung: %s" % str(PRESETS))
	## ASCENDING matters here specifically: the growth arms walk the ladder asserting each value is
	## >= the one before, and _lowest()/_highest() read the ends by INDEX. An unsorted ladder
	## silently changes what every one of those arms asserts rather than failing any of them.
	var prev: float = -1.0
	for scale in PRESETS:
		assert_gt(float(scale), prev,
			"the ladder is not ascending at %s: %s" % [str(scale), str(PRESETS)])
		prev = float(scale)
	assert_gt(_highest(), 1.0, "the ladder's top rung must be above the default, got %s" % _highest())
	assert_lt(_lowest(), 1.0, "the ladder's bottom rung must be below the default, got %s" % _lowest())


# ---------------------------------------------------------------- the card grew


func test_every_font_on_the_card_follows_the_text_size() -> void:
	if PRESETS.is_empty():
		assert_false(true, "the ladder is empty; this sweep would iterate nothing and pass")
		return
	var longest := _longest()
	var seen: Dictionary = {}
	for scale in PRESETS:
		var pop = await _card(float(scale), longest, true)
		var L := _labels(pop, longest)
		seen[float(scale)] = {
			"title": _px(L["title"]), "name": _px(L["name"]), "bag": _px(L["bag"]),
			"desc": _px(L["desc"]), "hint": _px(L["hint"]),
		}
		gut.p("  %.2fx  title %d  name %d  bag %d  desc %d  hint %d  card %s"
			% [scale, seen[float(scale)]["title"], seen[float(scale)]["name"],
				seen[float(scale)]["bag"], seen[float(scale)]["desc"], seen[float(scale)]["hint"],
				str((pop.get("_panel") as Control).size)])
		await _release()

	## ⛔ GUARDED, NOT INDEXED. `seen[1.0]` on a ladder without a 100% rung RAISES mid-arm, and GUT
	## scores an aborted body as a PASS — so the arm that exists to notice the default moved would go
	## green on exactly that. Same hazard the flag-graph audit documents about a renamed const.
	var at_default: Dictionary = seen.get(1.0, {})
	assert_false(at_default.is_empty(),
		"the ladder carries no 100%% rung (%s), so every shipped-size arm below is vacuous" % str(PRESETS))
	if at_default.is_empty():
		return

	## 100% must draw the shipped size at every site, read through the card's own consts — reached
	## by class_name, so a renamed const is a parse error rather than a silently skipped arm.
	var base: Dictionary = {
		"title": KeyItemPopup.TITLE_FONT_SIZE, "name": KeyItemPopup.NAME_FONT_SIZE,
		"bag": KeyItemPopup.BAG_FONT_SIZE, "desc": KeyItemPopup.DESC_FONT_SIZE,
		"hint": KeyItemPopup.HINT_FONT_SIZE,
	}
	for site in base:
		assert_eq(int(at_default[site]), int(base[site]),
			"100%% must draw the shipped %s size (%d), got %d"
			% [site, int(base[site]), int(at_default[site])])

	## Monotonic across the ladder, then strictly bigger at the top rung and strictly smaller at the
	## bottom. This is the arm the pre-fix card fails at every site, because it drew ONE size at
	## every preset — and it is the arm no amount of "nothing overflows" can stand in for.
	var lo := _lowest()
	var hi := _highest()
	for site in base:
		var prev: int = 0
		for scale in PRESETS:
			assert_gte(int(seen[float(scale)][site]), prev,
				"the %s font went BACKWARDS at %.2fx (%d after %d)"
				% [site, scale, int(seen[float(scale)][site]), prev])
			prev = int(seen[float(scale)][site])
		assert_gt(int(seen[hi][site]), int(at_default[site]),
			"the %s does not grow with Text Size: %.0f%% draws %d and 100%% draws %d"
			% [site, hi * 100.0, int(seen[hi][site]), int(at_default[site])])
		assert_lt(int(seen[lo][site]), int(at_default[site]),
			"the %s does not shrink at %.0f%%: %d vs %d"
			% [site, lo * 100.0, int(seen[lo][site]), int(at_default[site])])


func test_the_emblem_glyph_follows_the_text_size() -> void:
	## The emblem is the one font site that is not a named band, and it is 64px — the site where
	## ignoring Text Size is most visible and the easiest to miss in a sweep keyed to labels.
	var px: Dictionary = {}
	for scale in PRESETS:
		var pop = await _card(float(scale), _longest(), false)
		px[float(scale)] = _px(pop.get("_icon"))
		await _release()
	var at_default: int = int(px.get(1.0, -1))
	assert_ne(at_default, -1,
		"the ladder carries no 100%% rung (%s), or the emblem was not a Label — either way this arm "
		% str(PRESETS) + "measures nothing")
	if at_default == -1:
		return
	assert_eq(at_default, KeyItemPopup.EMBLEM_FONT_SIZE,
		"100%% must draw the shipped emblem size (%d), got %d"
		% [KeyItemPopup.EMBLEM_FONT_SIZE, at_default])
	assert_gt(int(px[_highest()]), at_default,
		"the emblem does not grow with Text Size: %.0f%% draws %d and 100%% draws %d"
		% [_highest() * 100.0, int(px[_highest()]), at_default])


func test_the_card_itself_grows_so_the_bigger_text_has_room() -> void:
	## The structural half. Without it every fit arm below is satisfied by fonts growing inside
	## bands that stayed put — which is not a pass, it is the collision.
	var longest := _longest()
	var w: Dictionary = {}
	var h: Dictionary = {}
	for scale in PRESETS:
		var pop = await _card(float(scale), longest, true)
		var panel := pop.get("_panel") as Control
		w[float(scale)] = panel.size.x
		h[float(scale)] = panel.size.y
		await _release()
	var prev_w: float = 0.0
	var prev_h: float = 0.0
	for scale in PRESETS:
		assert_gte(float(w[float(scale)]), prev_w - 0.5,
			"at %.2fx the card got NARROWER (%.0f after %.0f) while its text got bigger"
			% [scale, w[float(scale)], prev_w])
		assert_gte(float(h[float(scale)]), prev_h - 0.5,
			"at %.2fx the card got SHORTER (%.0f after %.0f) while its text got bigger"
			% [scale, h[float(scale)], prev_h])
		prev_w = float(w[float(scale)])
		prev_h = float(h[float(scale)])
	var w0: float = float(w.get(1.0, -1.0))
	var h0: float = float(h.get(1.0, -1.0))
	assert_gt(w0, 0.0,
		"the ladder carries no 100%% rung (%s), so the growth comparison below is vacuous" % str(PRESETS))
	if w0 <= 0.0:
		return
	assert_gt(float(w[_highest()]), w0,
		"at %.0f%% the card is still %.0fpx wide, so the grown text has no more room than at 100%%"
		% [_highest() * 100.0, w0])
	assert_gt(float(h[_highest()]), h0,
		"at %.0f%% the card is still %.0fpx tall" % [_highest() * 100.0, h0])


# ---------------------------------------------------------------- the text fits


func test_the_description_clears_the_continue_hint_at_every_preset() -> void:
	## The invariant the single-scale guard already pins, now at every rung and in both layouts.
	## Measured from the font, never from desc.size.y.
	var longest := _longest()
	for scale in PRESETS:
		for bag in [false, true]:
			var pop = await _card(float(scale), longest, bag)
			var L := _labels(pop, longest)
			if L["desc"] != null and L["hint"] != null:
				var bottom: float = (L["desc"] as Label).position.y + _text_h(L["desc"], longest)
				var hint_y: float = (L["hint"] as Label).position.y
				gut.p("  %.2fx bag=%s  desc ends %.0f  hint starts %.0f" % [scale, bag, bottom, hint_y])
				assert_lte(bottom, hint_y + 0.5,
					"at %.2fx (bag=%s) the description's %d wrapped lines end at y=%.0f and the continue hint starts at y=%.0f — they are drawn on top of each other"
					% [scale, bag, (L["desc"] as Label).get_line_count(), bottom, hint_y])
			await _release()


func test_the_continue_hint_stays_inside_the_card_at_every_preset() -> void:
	## The other half: growing the description must grow the CARD, not push its own hint through the
	## bottom border. The border is drawn from _panel.size at construction, so a card that did not
	## grow leaves the hint outside the frame.
	var longest := _longest()
	for scale in PRESETS:
		for bag in [false, true]:
			var pop = await _card(float(scale), longest, bag)
			var L := _labels(pop, longest)
			var panel := pop.get("_panel") as Control
			if L["hint"] != null and panel != null:
				var hint: Label = L["hint"]
				var end: float = hint.position.y + _text_h(hint, str(hint.text))
				assert_lte(end, panel.size.y + 0.5,
					"at %.2fx (bag=%s) the continue hint's text ends at y=%.0f on a %.0fpx card — it is drawn past the bottom border"
					% [scale, bag, end, panel.size.y])
			await _release()


func test_nothing_on_the_card_is_drawn_outside_it() -> void:
	var longest := _longest()
	for scale in PRESETS:
		var pop = await _card(float(scale), longest, true)
		var L := _labels(pop, longest)
		var panel := pop.get("_panel") as Control
		if panel != null:
			for key in ["title", "name", "bag", "desc"]:
				if L[key] == null:
					continue
				var lab: Label = L[key]
				var text_bottom: float = lab.position.y + _text_h(lab, str(lab.text))
				assert_lte(text_bottom, panel.size.y + 0.5,
					"at %.2fx the %s's glyphs end at y=%.0f on a %.0fpx card"
					% [scale, key, text_bottom, panel.size.y])
				assert_gte(lab.position.x, -0.5,
					"at %.2fx the %s starts left of the card at x=%.0f" % [scale, key, lab.position.x])
				assert_lte(lab.position.x + lab.size.x, panel.size.x + 0.5,
					"at %.2fx the %s's box ends at x=%.0f on a %.0fpx card"
					% [scale, key, lab.position.x + lab.size.x, panel.size.x])
		await _release()


func test_the_card_and_its_hint_stay_on_the_screen() -> void:
	## The half a card-relative arm cannot see: every band can sit correctly inside a card that is
	## itself off the display. The HINT is called out separately because it is the only line telling
	## the player how to dismiss the card — a card that loses it looks stuck, which is why the card's
	## position clamps its BOTTOM last and its top first.
	var longest := _longest()
	var screen: Vector2 = get_viewport().get_visible_rect().size
	for scale in PRESETS:
		var pop = await _card(float(scale), longest, true)
		var panel := pop.get("_panel") as Control
		var L := _labels(pop, longest)
		if panel != null:
			var r: Rect2 = panel.get_global_rect()
			gut.p("  %.2fx  card %s at %s  screen %s"
				% [scale, str(panel.size), str(r.position), str(screen)])
			assert_gte(r.position.x, -0.5,
				"at %.2fx the card starts at x=%.0f, off the left edge" % [scale, r.position.x])
			assert_lte(r.end.x, screen.x + 0.5,
				"at %.2fx the card reaches x=%.0f on a %.0fpx screen" % [scale, r.end.x, screen.x])
			assert_lte(r.end.y, screen.y + 0.5,
				"at %.2fx the card reaches y=%.0f on a %.0fpx screen" % [scale, r.end.y, screen.y])
			if L["hint"] != null:
				var hint: Label = L["hint"]
				var hint_end: float = r.position.y + hint.position.y + _text_h(hint, str(hint.text))
				assert_lte(hint_end, screen.y + 0.5,
					"at %.2fx the continue hint ends at screen y=%.0f on a %.0fpx screen — the player cannot see how to dismiss the card"
					% [scale, hint_end, screen.y])
		await _release()


# ---------------------------------------------------------------- 100% is untouched


func test_the_shipped_layout_is_pixel_identical_at_100_and_below() -> void:
	## The LAYOUT only ever grows, so the bottom rung must be identical to 100% and both identical
	## to the card that shipped before this change — at 80% only the FONTS get smaller.
	## struktured plays at 100%, so this is the arm that says the fix cost him nothing.
	var short := ""
	for k in _descriptions():
		var d: String = str(_descriptions()[k])
		if d.length() > 0 and d.length() < 60:
			short = d
			break
	assert_ne(short, "", "CONTROL: a short description must exist, or this arm measures a grown card")
	## The literals the card shipped with, before any of this. Spelled out rather than derived from
	## the expressions under test, which would be a tautology — the two that are read from the card
	## are its UNSCALED base constants, which this change does not touch.
	var want: Dictionary = {
		"w": KeyItemPopup.PANEL_W, "h": KeyItemPopup.PANEL_H, "title_y": 16.0, "name_y": 160.0,
		"desc_x": 20.0, "desc_w": KeyItemPopup.PANEL_W - 40.0, "hint_y": KeyItemPopup.PANEL_H - 22.0,
	}
	for scale in [_lowest(), 1.0]:
		var pop = await _card(float(scale), short, false)
		var panel := pop.get("_panel") as Control
		var L := _labels(pop, short)
		assert_not_null(panel, "CONTROL: no card at %.2fx" % scale)
		for key in ["title", "name", "desc", "hint"]:
			assert_not_null(L[key], "CONTROL: no %s label at %.2fx" % [key, scale])
		if panel != null and L["title"] != null and L["name"] != null \
			and L["desc"] != null and L["hint"] != null:
			var got: Dictionary = {
				"w": panel.size.x, "h": panel.size.y,
				"title_y": (L["title"] as Label).position.y,
				"name_y": (L["name"] as Label).position.y,
				"desc_x": (L["desc"] as Label).position.x,
				"desc_w": (L["desc"] as Label).size.x,
				"hint_y": (L["hint"] as Label).position.y,
			}
			for key in want:
				assert_almost_eq(float(got[key]), float(want[key]), 0.5,
					"at %.2fx the card's %s is %.1f where the shipped layout has %.1f — 100%% and below must be pixel-identical to before this change"
					% [scale, key, got[key], want[key]])
		await _release()
