extends GutTest

## struktured 2026-11-23: an earned autobattle recipe "should really show off when you learn them", and no text is ever cut.
## RecipeReveal is built for real on a 1280x720 viewport at every Text Size, fed every catalog recipe through the ledger's own reveal_dict.

const SCREEN := Vector2i(1280, 720)
## A fixed sample for the card and pip arms; the FIT arms derive their corpus from the catalog (main 27183).
const WORST := {"icon_key": "icon_defer_at_low_ap", "name": "Strategic Cowardice", "line": "Deferred at 0 AP or less 10 times",
	"flavour": "The title was never ironic.", "rarity": "rare", "progress": 10, "threshold": 10}
const SHORT := {"icon_key": "icon_heal_ally_under_50", "name": "Triage", "line": "Healed an ally below half HP 10 times",
	"flavour": "Somebody has to keep the idiots alive.", "rarity": "common", "progress": 10, "threshold": 10}

var _saved := 1.0


func before_each() -> void:
	_saved = float(GameState.text_size_scale)


func after_each() -> void:
	GameState.text_size_scale = _saved


func _reveal(recipe: Dictionary) -> RecipeReveal:
	var vp := SubViewport.new()
	vp.size = SCREEN
	add_child_autofree(vp)
	var r := RecipeReveal.show_recipe(vp, recipe)
	await get_tree().process_frame
	await get_tree().process_frame
	return r


func _rect(c: Control) -> Rect2:
	return Rect2(c.position, c.size)


## Every catalog recipe as the reveal will receive it, plus one made of the longest name, line and flavour so the worst case is whatever the data says.
func _corpus() -> Array:
	var ledger := RecipeLedger.new()
	var out: Array = []
	var worst := {"name": "", "line": "", "flavour": ""}
	for id in RecipeCatalog.ids():
		var d: Dictionary = ledger.reveal_dict("fighter", id)
		d["progress"] = d["threshold"]
		out.append(d)
		for f in worst:
			if str(d[f]).length() > str(worst[f]).length():
				worst[f] = str(d[f])
	out.append(WORST.merged(worst, true))
	return out


## Every line of every text is drawn (the engine's own count), inside the panel, clear of the card and of each other.
func test_every_text_reads_whole_at_every_text_size() -> void:
	var name_px := {}
	var card_px := {}
	for p in SettingsMenu.TEXT_SIZE_PRESETS:
		GameState.text_size_scale = float(p)
		var corpus := _corpus()
		assert_gt(corpus.size(), 9, "CONTROL: the catalog's 9 recipes and the composite worst were judged at %s" % str(p))
		for recipe in corpus:
			var r: RecipeReveal = await _reveal(recipe)
			var panel := r.panel_node()
			var card := r.card_node()
			assert_not_null(panel, "CONTROL: the reveal built a panel at %s" % str(p))
			if panel == null:
				continue
			var tag := "%s @ %s" % [str(recipe["name"]), str(p)]
			assert_true(Rect2(Vector2.ZERO, Vector2(SCREEN)).encloses(Rect2(panel.position, panel.size)),
				"%s: the panel %s leaves the screen" % [tag, str(Rect2(panel.position, panel.size))])
			var placed: Array = []
			for which in ["title", "name", "line", "flavour", "hint"]:
				var l: Label = r.text_label(which)
				assert_not_null(l, "%s: no %s label" % [tag, which])
				if l == null:
					continue
				assert_eq(l.text_overrun_behavior, TextServer.OVERRUN_NO_TRIMMING, "%s: %s may trim" % [tag, which])
				assert_eq(l.get_visible_line_count(), l.get_line_count(),
					"%s: %s draws %d of its %d lines in %s" % [tag, which, l.get_visible_line_count(), l.get_line_count(), str(l.size)])
				assert_true(Rect2(Vector2.ZERO, panel.size).encloses(_rect(l)), "%s: %s %s leaves the panel %s" % [tag, which, str(_rect(l)), str(panel.size)])
				assert_false(_rect(l).intersects(_rect(card)), "%s: %s %s overlaps the card %s" % [tag, which, str(_rect(l)), str(_rect(card))])
				for other in placed:
					assert_false(_rect(l).intersects(_rect(other[1])), "%s: %s overlaps %s" % [tag, which, other[0]])
				placed.append([which, l])
			assert_true(Rect2(Vector2.ZERO, panel.size).encloses(_rect(card)), "%s: the card leaves the panel" % tag)
			if recipe == corpus.back():
				name_px[p] = (r.text_label("name") as Label).get_theme_font_size("font_size")
				card_px[p] = card.size
			r.free()
	var steps: Array = SettingsMenu.TEXT_SIZE_PRESETS.duplicate()
	assert_gt(steps.size(), 2, "CONTROL: the Text Size ladder has steps to walk")
	for i in range(1, steps.size()):
		assert_gt(int(name_px[steps[i]]), int(name_px[steps[i - 1]]), "the name grows from %s to %s" % [str(steps[i - 1]), str(steps[i])])
		assert_eq(card_px[steps[i]], card_px[steps[0]], "the pixel card keeps its integer scale at %s" % str(steps[i]))


## The card is sprites' registered frame at CARD_SCALE, its pips are the manifest's count, and the earned ones light.
func test_the_card_is_the_registered_frame_and_its_pips_count_up() -> void:
	GameState.text_size_scale = 1.0
	var section := RecipeReveal.manifest_section()
	var entry := RecipeReveal.card_entry(section, "card_rare")
	assert_false(entry.is_empty(), "CONTROL: sprites registered recipe_cards.card_rare")
	var r: RecipeReveal = await _reveal(WORST.merged({"progress": 7}, true))
	var frame := r.card_node().get_node_or_null("Frame") as TextureRect
	assert_not_null(frame, "the card draws the registered frame, not the procedural fallback")
	if frame != null:
		assert_eq(frame.texture.resource_path, str(entry["path"]), "and it is the rarity's own frame")
		assert_eq(frame.size, Vector2(float(entry["frame_width"]), float(entry["frame_height"])) * RecipeReveal.CARD_SCALE,
			"at CARD_SCALE")
	assert_not_null(r.card_node().get_node_or_null("Icon"), "the recipe's icon_key names sprites' icon, drawn in the art window")
	var bare: RecipeReveal = await _reveal(WORST.merged({"icon_key": "icon_not_drawn_yet"}, true))
	assert_null(bare.card_node().get_node_or_null("Icon"), "an icon with no art yet leaves the window empty")
	assert_null(bare.card_node().get_node_or_null("Emblem"), "and puts no emblem over the registered frame")
	bare.free()
	assert_eq(r.pip_count(), int(entry["pip_count"]), "one socket per manifest pip")
	assert_false(r.is_dismissable(), "CONTROL: the count-up has not finished on the first frame")
	var waited := 0.0
	while not r.is_dismissable() and waited < 4.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
	assert_true(r.is_dismissable(), "the reveal finishes its count-up")
	assert_eq(r.lit_pips(), 7, "7 of 10 earned lights 7 pips")
	r.free()


func test_lit_count_scales_progress_onto_the_sockets() -> void:
	assert_eq(RecipeReveal.lit_count({"progress": 10, "threshold": 10}, 10), 10)
	assert_eq(RecipeReveal.lit_count({"progress": 25, "threshold": 10}, 10), 10, "past the threshold stays full")
	assert_eq(RecipeReveal.lit_count({"progress": 3, "threshold": 6}, 10), 5, "a threshold of 6 fills half at 3")
	assert_eq(RecipeReveal.lit_count({"threshold": 10}, 10), 10, "no progress means the earned reveal, full")


func test_the_count_up_ticks_name_sfx_s_keys_and_stay_silent_until_registered() -> void:
	assert_eq(RecipeReveal.pip_tick_key(1), "recipe_pip_01")
	assert_eq(RecipeReveal.pip_tick_key(10), "recipe_pip_10")
	assert_false(RecipeReveal.has_sfx("recipe_pip_never_registered"), "an unregistered key plays nothing")
	assert_true(RecipeReveal.has_sfx("item_obtain") or RecipeReveal.has_sfx("menu_select"), "CONTROL: a registered cue reads as present")


## The frame at 100% drew the flavour and the hint at the face's 1x step and the name level with its line (cutscenes 27126).
## Judged on the DRAWN step, UiFont.scale_for, not the raw size: raw sizes stay distinct while the step collapses (adhoc 27128).
func test_every_tier_draws_legibly_and_the_name_leads_at_every_text_size() -> void:
	var tiers := ["title", "name", "line", "flavour", "hint"]
	for p in SettingsMenu.TEXT_SIZE_PRESETS:
		GameState.text_size_scale = float(p)
		var r: RecipeReveal = await _reveal(WORST)
		var step := {}
		for which in tiers:
			var l: Label = r.text_label(which)
			assert_not_null(l, "CONTROL: the %s label exists at %s" % [which, str(p)])
			if l != null:
				step[which] = UiFont.scale_for(l.get_theme_font_size("font_size"))
		if float(p) >= 1.0:
			for which in step:
				assert_gte(int(step[which]), 2, "%s draws at the face's %dx step at %s, too small to read" % [which, int(step[which]), str(p)])
		if step.has("name") and step.has("line"):
			assert_gt(int(step["name"]), int(step["line"]), "the name stands a step above its line at %s (%dx vs %dx)" % [str(p), int(step["name"]), int(step["line"])])
		r.free()


## A pad player is told their own Confirm face; "Press X" is true on a keyboard only (main 27127).
func test_the_continue_hint_names_the_players_own_confirm() -> void:
	var pad_name := "Xbox Wireless Controller"
	var cap: String = InputProfileManager.hint_for_action("ui_accept", pad_name)
	assert_ne(cap, "", "CONTROL: the xbox layout names a confirm button")
	assert_eq(RecipeReveal.continue_hint(pad_name), "Press %s to continue" % cap)
	var r: RecipeReveal = await _reveal(WORST)
	assert_eq((r.text_label("hint") as Label).text, RecipeReveal.continue_hint(), "the panel shows the derived hint")
	r.free()


## The panel hugs its content: no wide empty band right of the text (main 27127).
func test_the_panel_hugs_its_widest_line() -> void:
	GameState.text_size_scale = 1.0
	var r: RecipeReveal = await _reveal(SHORT)
	var right := 0.0
	for which in ["name", "line", "flavour"]:
		var l: Label = r.text_label(which)
		var f: Font = l.get_theme_font("font")
		right = maxf(right, l.position.x + f.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, l.get_theme_font_size("font_size")).x)
	var slack: float = r.panel_node().size.x - right
	assert_lt(slack, RecipeReveal.k(RecipeReveal.PAD) * 2.5, "the panel runs %d px past its widest line" % int(slack))
	r.free()
