extends GutTest

## main 22699: the reading panel, the Inn's rest panel and the Tavern's dialogue drew literal px, so Text Size did nothing to them.
## The reading panel now scales by its body font's own ratio (so a page that fits at 100% still fits); the Inn and Tavern panels grow to their wrapped text.
## The Tavern's panel was ALSO parented to the room in world coordinates (the Inn's 2026-07-25 bug), so the camera left it behind; it is screen-space now.

const InnScript := preload("res://src/maps/interiors/InnInterior.gd")
const TavernScript := preload("res://src/maps/interiors/TavernInterior.gd")
const SCREEN := Vector2(1280, 720)
const PANEL_TOP := 96.0
const TAVERN_LINES := [
	"*plays a beautiful melody on the piano*",
	"*You press some keys... it sounds terrible.*",
	"*You carefully press a key... then immediately regret it.*",
	"*You mash some keys rapidly. It's chaos.*",
]

var _saved: float = 1.0


func before_each() -> void:
	_saved = float(GameState.text_size_scale)


func after_each() -> void:
	GameState.text_size_scale = _saved


func _presets() -> Array:
	return SettingsMenu.TEXT_SIZE_PRESETS


func _wrapped_h(text: String, width: float, px: int, align: int) -> float:
	return ThemeDB.fallback_font.get_multiline_string_size(text, align, width, px, -1, InnScript.WRAP_FLAGS).y


## Every message the rest panel can show: the price prompt at three purses and every authored line, per village.
func _inn_messages() -> Array:
	var inn: Node = autofree(InnScript.new())
	var out: Array = []
	for key in InnDialogue.village_keys():
		var map_id: String = str(key) + "_village"
		for purse in [-1, 5, 100000]:
			out.append(inn._rest_prompt_for(map_id, purse))
		var lines: Dictionary = InnDialogue.lines_for(map_id)
		for kind in ["rest_complete", "cant_afford"]:
			var v = lines.get(kind, [])
			for line in (v if v is Array else [v]):
				if str(line) != "":
					out.append(str(line) + "\nHP and MP restored. (-%d G)\nFighter, Cleric cannot be roused — that death is permanent." % InnScript.REST_COST)
					out.append(str(line) + "\nNeed %d G, you have %d G." % [InnScript.REST_COST, 3])
	out.append("Not enough gold!\nNeed %d G, you have %d G." % [InnScript.REST_COST, 3])
	return out


## A long reading page trimmed until it JUST fits the 100% body box.
func _page_that_fits_at_1x() -> String:
	GameState.text_size_scale = 1.0
	var words := ("The ledger runs in a careful hand for nine pages, every debt marked paid but one, and that one is "
		+ "underlined twice in a different ink. Someone came back to it years later. The margin holds a single date "
		+ "and the word ENOUGH, pressed so hard the nib tore the paper, and below it a list of names in the same hand.").repeat(3).split(" ")
	var box := ReadableProp.body_box()
	var text := " ".join(words)
	while words.size() > 1 and _wrapped_h(text, box.x, ReadableProp.BODY_FONT, HORIZONTAL_ALIGNMENT_LEFT) > box.y:
		words.remove_at(words.size() - 1)
		text = " ".join(words)
	return text


func _reading_panel() -> Panel:
	var r := ReadableProp.new()
	r.display_name = "Probe"
	add_child_autofree(r)
	r._entries = [{"heading": "Probe", "body": "x"}]
	r._open_panel()
	var panel: Panel = r._layer.get_child(0).get_child(0)
	return panel


func test_every_panel_grows_at_every_preset() -> void:
	assert_gt(_presets().size(), 2, "FLOOR: the Text Size presets must be read")
	var last := {"reading": 0, "inn": 0, "tavern": 0}
	for p in _presets():
		GameState.text_size_scale = float(p)
		var reading: Label = _reading_panel().get_child(1)
		var inn_label: Label = autofree(InnScript.new())._make_inn_dialog("Rest?").get_child(0).get_child(0).get_child(0)
		var tav_label: Label = autofree(TavernScript.new())._make_dialogue_layer("*hm*").get_child(0).get_child(0).get_child(0)
		var now := {"reading": reading.get_theme_font_size("font_size"), "inn": inn_label.get_theme_font_size("font_size"), "tavern": tav_label.get_theme_font_size("font_size")}
		for k in now:
			assert_gt(now[k], last[k], "%s font must grow at Text Size %s" % [k, str(p)])
			last[k] = now[k]


func test_the_text_fits_its_built_panel_at_every_preset() -> void:
	var page := _page_that_fits_at_1x()
	var messages := _inn_messages()
	assert_gt(messages.size(), 6, "FLOOR: the inn's real messages must be derived (%d)" % messages.size())
	for p in _presets():
		GameState.text_size_scale = float(p)
		var box := ReadableProp.body_box()
		assert_lte(_wrapped_h(page, box.x, TextScale.scaled(ReadableProp.BODY_FONT), HORIZONTAL_ALIGNMENT_LEFT), box.y,
			"a page that fits at 100%% overflows the reading panel at %s" % str(p))
		var rp := _reading_panel()
		assert_true(Rect2(Vector2.ZERO, SCREEN).encloses(Rect2((SCREEN - rp.size) / 2.0, rp.size)), "the reading panel leaves the screen at %s" % str(p))
		var kinn := float(TextScale.scaled(InnScript.DIALOG_FONT)) / float(InnScript.DIALOG_FONT)
		for m in messages:
			var sz: Vector2 = InnScript.dialog_size(m)
			var inner := sz - Vector2(InnScript.DIALOG_PAD, InnScript.DIALOG_PAD) * 2.0 * kinn
			assert_lte(_wrapped_h(m, inner.x, TextScale.scaled(InnScript.DIALOG_FONT), HORIZONTAL_ALIGNMENT_CENTER), inner.y + 0.5,
				"the rest panel cannot hold '%s' at %s" % [str(m).left(40), str(p)])
			assert_lte(PANEL_TOP + sz.y, SCREEN.y, "the rest panel runs off the bottom at %s" % str(p))
			assert_lte(sz.x, SCREEN.x, "the rest panel is wider than the screen at %s" % str(p))
		var ktav := float(TextScale.scaled(TavernScript.DIALOGUE_FONT)) / float(TavernScript.DIALOGUE_FONT)
		for t in TAVERN_LINES:
			var tsz: Vector2 = TavernScript.dialogue_size(t)
			var tin := tsz - Vector2(TavernScript.DIALOGUE_PAD, TavernScript.DIALOGUE_PAD) * 2.0 * ktav
			assert_lte(_wrapped_h(t, tin.x, TextScale.scaled(TavernScript.DIALOGUE_FONT), HORIZONTAL_ALIGNMENT_LEFT), tin.y + 0.5,
				"the tavern panel cannot hold '%s' at %s" % [t.left(40), str(p)])


func test_the_tavern_dialogue_is_screen_space() -> void:
	var layer = autofree(TavernScript.new())._make_dialogue_layer("*hm*")
	assert_true(layer is CanvasLayer, "the tavern's panel must sit on a CanvasLayer, or the camera leaves it behind (the Inn's 2026-07-25 bug)")


func test_the_authored_panels_hold_at_1x() -> void:
	GameState.text_size_scale = 1.0
	assert_eq(ReadableProp.panel_scale(), 1.0, "the reading panel scales by exactly 1.0 at 100%")
	assert_eq(_reading_panel().size, Vector2(ReadableProp.PANEL_W, ReadableProp.PANEL_H), "and keeps its authored size")
	assert_eq(InnScript.dialog_size("Rest until morning?"), InnScript.DIALOG_MIN, "a short rest prompt keeps the authored 300x88")
	assert_eq(TavernScript.dialogue_size("*hm*"), TavernScript.DIALOGUE_MIN, "a short tavern line keeps the authored 300x60")
