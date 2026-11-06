extends GutTest

## The title card a boss signature, a glory spell or a summon raises (`_show_signature_card`) was centred by its own
## width with no wrap and no clamp, so a long title at a large Text Size ran off both edges of the screen. It now
## grows with Text Size and, when it would not fit, wraps to the screen. CLAUDE.md's three Text Size arms: the font
## grows at every preset; the BUILT card fits its screen for every real title; an overlong title still fits (the clamp).

const SCENE := preload("res://src/battle/BattleScene.tscn")
const BattleStateGuard := preload("res://test/unit/helpers/battle_state.gd")
const BASE_TITLE := 30

var _guard
var _saved_scale = null
var _scene: Node = null


func before_each() -> void:
	_guard = BattleStateGuard.new()
	_guard.snapshot()
	_saved_scale = GameState.text_size_scale if "text_size_scale" in GameState else null


func after_each() -> void:
	if _saved_scale != null:
		GameState.text_size_scale = _saved_scale
	_guard.restore()


func _presets() -> Array:
	var consts: Dictionary = (load("res://src/ui/SettingsMenu.gd") as GDScript).get_script_constant_map()
	var p: Array = consts.get("TEXT_SIZE_PRESETS", [])
	assert_gt(p.size(), 1, "FLOOR: SettingsMenu.TEXT_SIZE_PRESETS must resolve and hold more than one step, got " + str(p))
	return p


func _get_scene() -> Node:
	if _scene == null or not is_instance_valid(_scene):
		_scene = SCENE.instantiate()
		add_child_autofree(_scene)
		await get_tree().process_frame
	return _scene


## Every card the game can raise: each boss's fx_signature_card, and each glory spell / summon by its ability name.
func _corpus() -> Array:
	var out: Array = []
	var monsters = JSON.parse_string(FileAccess.get_file_as_string("res://data/monsters.json"))
	for id in (monsters if monsters is Dictionary else {}):
		var card = monsters[id].get("fx_signature_card") if monsters[id] is Dictionary else null
		if card is Dictionary and str(card.get("title", "")) != "":
			out.append({"card": card, "ability": {}})
	var abilities = JSON.parse_string(FileAccess.get_file_as_string("res://data/abilities.json"))
	var table: Dictionary = abilities.get("abilities", abilities) if abilities is Dictionary else {}
	for id in table:
		var vfx = table[id].get("vfx", {}) if table[id] is Dictionary else {}
		if vfx is Dictionary and vfx.has("glory"):
			out.append({"card": {}, "ability": table[id]})
	return out


func _built(card: Dictionary, ability: Dictionary) -> PanelContainer:
	var scene: Node = await _get_scene()
	scene._show_signature_card(card, ability, 5.0)
	await get_tree().process_frame
	await get_tree().process_frame
	return scene.get_node_or_null("UI/SignatureCard") as PanelContainer


func _head_of(panel: PanelContainer) -> Label:
	return panel.get_child(0).get_child(0) as Label if panel and panel.get_child_count() > 0 else null


func _inside_screen(panel: PanelContainer) -> bool:
	var vp: Vector2 = panel.get_viewport_rect().size
	var r := panel.get_global_rect()
	return r.position.x >= 0.0 and r.end.x <= vp.x + 0.5 and r.position.y >= 0.0 and r.end.y <= vp.y + 0.5


## ARM 1: the title font follows every Text Size step, not just the largest.
func test_the_title_grows_at_every_text_size() -> void:
	var sizes: Array = []
	for scale in _presets():
		GameState.text_size_scale = scale
		var panel := await _built({"title": "Summary Judgment"}, {})
		assert_not_null(panel, "CONTROL: the card was built at %s" % str(scale))
		var head := _head_of(panel)
		sizes.append(head.get_theme_font_size("font_size") if head else 0)
	for i in range(1, sizes.size()):
		assert_gt(int(sizes[i]), int(sizes[i - 1]), "the title grows from preset %d to %d: %s" % [i - 1, i, str(sizes)])


## ARM 2: every real card fits the screen at every Text Size, measured on the BUILT card.
func test_every_real_card_fits_at_every_text_size() -> void:
	var corpus := _corpus()
	assert_gte(corpus.size(), 10, "CONTROL: the corpus holds the boss cards and the glory/summon spells (%d)" % corpus.size())
	var off: Array = []
	for scale in _presets():
		GameState.text_size_scale = scale
		for entry in corpus:
			var panel := await _built(entry["card"], entry["ability"])
			if panel == null:
				off.append("no card for %s" % str(entry))
				continue
			if not _inside_screen(panel):
				off.append("%s at %s: %s" % [_head_of(panel).text, str(scale), str(panel.get_global_rect())])
	assert_eq(off, [], "a title card ran off the screen")


## ARM 3: a title longer than anything the game ships still fits at the largest size: the wrap-and-clamp is what holds.
func test_an_overlong_title_wraps_to_the_screen() -> void:
	var presets := _presets()
	GameState.text_size_scale = presets[presets.size() - 1]
	var long_title := "The Exceptionally Long And Grandiose Title Of A Very Patient Calibrant"
	var panel := await _built({"title": long_title, "subtitle": "and a subtitle that also goes on for rather longer than any real one does"}, {})
	assert_not_null(panel, "CONTROL: the card was built")
	if panel == null:
		return
	var head := _head_of(panel)
	assert_eq(head.text, long_title, "CONTROL: it is the long title")
	assert_true(_inside_screen(panel), "the overlong card stays on screen: %s" % str(panel.get_global_rect()))
	assert_gt(head.get_line_count(), 1, "by wrapping, not by shrinking the text")


## ARM 4: a card raised over another replaces it in the same frame, keeps the name, and leaves one card on screen.
func test_a_second_card_replaces_the_first_by_name() -> void:
	var scene: Node = await _get_scene()
	scene._show_signature_card({"title": "First Card"}, {}, 5.0)
	scene._show_signature_card({"title": "Second Card"}, {}, 5.0)
	var named := scene.get_node_or_null("UI/SignatureCard") as PanelContainer
	assert_not_null(named, "the second card answers to its own name in the frame it was raised")
	assert_eq(str(_head_of(named).text) if named else "", "Second Card")
	await get_tree().process_frame
	var cards := 0
	for c in scene.get_node("UI").get_children():
		if c is PanelContainer and c.get_child_count() > 0 and _head_of(c) != null and str(_head_of(c).text).ends_with(" Card"):
			cards += 1
	assert_eq(cards, 1, "the first card is gone, not left beside the second until its own hold runs out")


## A cast that raises the tint while the last one fades gets a tint of its own, not the one about to be freed.
func test_a_tint_raised_during_the_fade_out_is_its_own() -> void:
	var scene: Node = await _get_scene()
	scene._signature_stage(true, Color(0.3, 0.1, 0.4, 0.5))
	var first: Node = scene.get_node_or_null("SignatureTint")
	assert_not_null(first, "CONTROL: the tint went up")
	scene._signature_stage(false, Color(0.3, 0.1, 0.4, 0.5))
	scene._signature_stage(true, Color(0.1, 0.3, 0.4, 0.5))
	var second: Node = scene.get_node_or_null("SignatureTint")
	assert_not_null(second, "the new cast has a tint")
	assert_ne(second, first, "and it is not the fading one its tween is about to free")
