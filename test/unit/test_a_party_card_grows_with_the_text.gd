extends GutTest

## The field menu's PARTY cards were laid out in literals (name at y 4, job 20, HP 36, MP 52, level 68, a 100 px card,
## the title row 28) around fonts that scale: at 200% the name, job, HP, MP and level lines overprinted each other in a
## card the 100% height, and the "PARTY / gold" header was cut by the first card (seen in a still, cowir-main 24445).
## The card's geometry now grows with the text. Measured on the built nodes at every Text Size step.

const FIELD := "res://src/ui/OverworldMenu.gd"
const SETTINGS := "res://src/ui/SettingsMenu.gd"
const CombatantScript := preload("res://src/battle/Combatant.gd")
const ROWS := ["NameLabel", "HPBar", "MPBar", "EXPRow"]
const SLACK := 0.5

var _saved_scale := 1.0


func before_each() -> void:
	_saved_scale = float(GameState.text_size_scale)


func after_each() -> void:
	GameState.text_size_scale = _saved_scale


func _presets() -> Array:
	var p: Array = (load(SETTINGS) as GDScript).get_script_constant_map().get("TEXT_SIZE_PRESETS", [])
	assert_gt(p.size(), 1, "FLOOR: SettingsMenu.TEXT_SIZE_PRESETS must hold more than one step")
	return p


func _menu(s: float, members: int = 4) -> Control:
	GameState.text_size_scale = s
	var vp := SubViewport.new()
	vp.size = Vector2i(1280, 720)
	add_child_autofree(vp)
	var layer := CanvasLayer.new()
	vp.add_child(layer)
	var party: Array = []
	for i in members:
		var pc = CombatantScript.new()
		pc.combatant_name = ["Bram", "Sister Ilse", "Quill", "Nettle", "Fen"][i]
		pc.max_hp = 120
		pc.current_hp = 77
		pc.max_mp = 40
		pc.current_mp = 12
		add_child_autofree(pc)
		party.append(pc)
	var m: Control = load(FIELD).new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(m)
	m.setup(party)
	await get_tree().process_frame
	await get_tree().process_frame
	return m


## The tops of the card's text rows, card-local, in ROWS order.
func _row_tops(card: Control) -> Array:
	var out: Array = []
	for n in ROWS:
		out.append((card.get_node(n) as Control).position.y)
	return out


func test_the_floor_names_every_member_this_file_drives() -> void:
	var m: Control = await _menu(1.0)
	assert_true("_party_panels" in m and "party" in m and m.has_method("setup") and m.has_method("_card_k") and m.has_method("_update_party_stats"), "OverworldMenu._party_panels / party / setup / _card_k / _update_party_stats must exist")
	assert_true("selected_character" in m and m.has_method("_update_selection"), "OverworldMenu.selected_character / _update_selection must exist")
	assert_eq(m._party_panels.size(), 4, "PRECONDITION: one card per member")
	var card: Control = m._party_panels[0]
	for n in ROWS + ["JobLabel", "LeaderStar", "AilmentLabel", "Background"]:
		assert_not_null(card.get_node_or_null(n), "a card has a %s" % n)
	assert_not_null((card.get_node("HPBar") as Control).get_node_or_null("Fill"), "a stat bar has a Fill")
	assert_not_null((card.get_node("HPBar") as Control).get_node_or_null("Value"), "a stat bar has a Value")


## CONTROL: at 100% the card is exactly the shipped card, so the fix moves nothing a player sees today at the default.
func test_at_100_percent_the_card_is_the_shipped_card() -> void:
	var m: Control = await _menu(1.0)
	var card: Control = m._party_panels[0]
	assert_eq(card.size.y, 100.0, "the card is 100 px tall")
	assert_eq(_row_tops(card), [4.0, 36.0, 52.0, 68.0], "name, HP, MP and level sit where they did")
	assert_eq(card.position.y, 28.0, "under a 28 px title row")
	var small: Control = (await _menu(0.8))._party_panels[0]
	assert_eq(small.size.y, 100.0, "and 80% never shrinks the shipped card")


## THE DEFECT: the rows kept a fixed step while their fonts grew. Each step between rows must grow with the text.
func test_the_rows_step_apart_as_the_text_grows() -> void:
	var base: Array = _row_tops((await _menu(1.0))._party_panels[0])
	for s in _presets():
		if float(s) <= 1.0:
			continue
		var m: Control = await _menu(s)
		var tops: Array = _row_tops(m._party_panels[0])
		var name_px: int = (m._party_panels[0].get_node("NameLabel") as Label).get_theme_font_size("font_size")
		assert_gt(name_px, 14, "CONTROL @%s: the name's font grew (%d px)" % [s, name_px])
		for i in range(1, tops.size()):
			var step: float = tops[i] - tops[i - 1]
			var want: float = (base[i] - base[i - 1]) * float(s)
			assert_gte(step, want - SLACK, "@%s %s starts %.0f px under %s; its 100%% step grown with the text is %.0f" % [s, ROWS[i], step, ROWS[i - 1], want])


## Every line a card draws ends inside the card, every card inside the panel (or its scroll), and no card on the title.
func test_a_card_holds_its_lines_and_the_panel_holds_its_cards() -> void:
	var bad: Array = []
	var seen := 0
	for s in _presets():
		for members in [1, 4, 5]:
			var m: Control = await _menu(s, members)
			var cards: Array = m._party_panels
			var panel: Control = null
			for i in cards.size():
				var card: Control = cards[i]
				var cr: Rect2 = card.get_global_rect()
				seen += 1
				for l in card.find_children("*", "Label", true, false):
					var lb := l as Label
					if not lb.visible or lb.text == "":
						continue
					var px: int = lb.get_theme_font_size("font_size")
					var bottom: float = lb.global_position.y + lb.get_theme_font("font").get_height(px)
					if bottom > cr.end.y + SLACK:
						bad.append("@%s x%d card %d: '%s' ends %.0f px below its card" % [s, members, i, lb.text.left(12), bottom - cr.end.y])
				if i > 0 and cr.position.y < (cards[i - 1] as Control).get_global_rect().end.y - SLACK:
					bad.append("@%s x%d card %d starts inside card %d" % [s, members, i, i - 1])
				var host: Control = card.get_parent() as Control
				var scrolled: bool = host.get_parent() is ScrollContainer
				panel = (host.get_parent().get_parent() if scrolled else host) as Control
				if not scrolled and cr.end.y > panel.get_global_rect().end.y + SLACK:
					bad.append("@%s x%d card %d ends %.0f px below the party panel, with no scroll" % [s, members, i, cr.end.y - panel.get_global_rect().end.y])
			var gold := panel.get_node_or_null("GoldLabel") as Label
			var title_bottom: float = gold.global_position.y + gold.get_theme_font("font").get_height(gold.get_theme_font_size("font_size"))
			var first_top: float = (cards[0] as Control).get_global_rect().position.y
			if not ((cards[0] as Control).get_parent().get_parent() is ScrollContainer) and title_bottom > first_top + SLACK:
				bad.append("@%s x%d the title row's text ends %.0f px inside the first card" % [s, members, title_bottom - first_top])
	assert_gt(seen, 30, "CONTROL: the sweep measured real cards (%d)" % seen)
	assert_eq(bad.size(), 0, "a party card holds its lines:\n%s" % "\n".join(PackedStringArray(bad)))


## A stat bar reads label, bar, value left to right at every size: the bar starts after "HP" and the number after the bar.
func test_a_stat_bar_keeps_its_label_bar_and_value_apart() -> void:
	var bad: Array = []
	for s in _presets():
		var m: Control = await _menu(s)
		var bar: Control = (m._party_panels[0] as Control).get_node("HPBar")
		var lbl: Label = null
		var bg: ColorRect = null
		for c in bar.get_children():
			if c is Label and c.name != "Value" and lbl == null:
				lbl = c
			elif c is ColorRect and c.name != "Fill" and bg == null:
				bg = c
		var value := bar.get_node("Value") as Label
		var fill := bar.get_node("Fill") as ColorRect
		assert_true(lbl != null and bg != null, "PRECONDITION @%s: the bar has its label and its trough" % s)
		var ink: float = lbl.get_theme_font("font").get_string_size(lbl.text, HORIZONTAL_ALIGNMENT_LEFT, -1, lbl.get_theme_font_size("font_size")).x
		if lbl.position.x + ink > bg.position.x + SLACK:
			bad.append("@%s 'HP' is %.0f px wide and the bar starts at %.0f" % [s, ink, bg.position.x])
		if bg.position.x + bg.size.x > value.position.x + SLACK:
			bad.append("@%s the bar ends %.0f, the number starts %.0f" % [s, bg.position.x + bg.size.x, value.position.x])
		## Through the live refresh, so the fill it writes is judged against the same trough the build drew.
		var who = m.party[0]
		who.current_hp = int(who.max_hp / 4)
		m._update_party_stats()
		assert_gt(who.max_hp, 3, "PRECONDITION @%s: the member has HP to lose" % s)
		assert_almost_eq(fill.size.x / bg.size.x, float(who.current_hp) / float(who.max_hp), 0.02, "@%s after a refresh the fill is the HP share of the trough" % s)
	assert_eq(bad, [], "a stat bar's parts keep apart: %s" % [bad])


## Five members at 200% no longer fit the panel, so the cards scroll: the SELECTED card must be the one in view.
func test_a_scrolling_party_keeps_the_selected_card_in_view() -> void:
	var m: Control = await _menu(2.0, 5)
	var scroller := (m._party_panels[0] as Control).get_parent().get_parent() as ScrollContainer
	assert_not_null(scroller, "CONTROL: five cards at 200% scroll")
	if scroller == null:
		return
	var last: Control = m._party_panels[4]
	assert_gt(last.get_global_rect().end.y, scroller.get_global_rect().end.y, "CONTROL: the fifth card starts out of view")
	m.selected_character = 4
	m._update_selection()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_lte(last.get_global_rect().end.y, scroller.get_global_rect().end.y + 1.5, "selected, the fifth card is inside the window")
	assert_gte(last.get_global_rect().position.y, scroller.get_global_rect().position.y - 1.5, "from its top")
