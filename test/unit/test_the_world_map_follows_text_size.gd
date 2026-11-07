extends GutTest

## The World Map (field menu → World Map) ignored Text Size: 7 literal font sizes on a header, three rows of cards and
## two bottom lines laid out at authored positions (census 22697, routed by cowir-main 22699). It now scales fonts AND
## geometry by one layout factor: the setting's factor, capped where the stack still fits the screen height (on 1280x720
## the 2.0 preset caps near 1.84). Exactly the authored layout at 100%.
## Every fit judgement measures text off the FONT, never a Label's own size (which grows to whatever it holds).

const MENU := preload("res://src/ui/WorldMapMenu.gd")
const UNLOCKS := ["cutscene_flag_world1_mordaine_defeated", "cutscene_flag_world2_complete",
	"cutscene_flag_world3_complete", "cutscene_flag_world4_complete", "cutscene_flag_world5_complete"]

var _saved_scale := 1.0
var _saved_world := 1
var _saved_flags := {}


func before_each() -> void:
	_saved_scale = float(GameState.text_size_scale)
	_saved_world = int(GameState.current_world)
	_saved_flags.clear()
	for f in UNLOCKS:
		_saved_flags[f] = GameState.game_constants.get(f, null)
		GameState.game_constants[f] = true   # every world unlocked, so every card shows its real (long) name


func after_each() -> void:
	GameState.set_text_size_scale(_saved_scale)
	GameState.current_world = _saved_world
	for f in _saved_flags:
		if _saved_flags[f] == null:
			GameState.game_constants.erase(f)
		else:
			GameState.game_constants[f] = _saved_flags[f]


func _presets() -> Array:
	var p: Array = (load("res://src/ui/SettingsMenu.gd") as GDScript).get_script_constant_map().get("TEXT_SIZE_PRESETS", [])
	assert_gt(p.size(), 1, "FLOOR: SettingsMenu.TEXT_SIZE_PRESETS must hold more than one step, or the preset loop proves nothing")
	return p


func _menu(world: int) -> Control:
	GameState.current_world = world
	var m: Control = MENU.new()
	add_child_autofree(m)
	return m


func _live_labels(node: Node) -> Array:
	return node.find_children("*", "Label", true, false).filter(
		func(l): return not l.is_queued_for_deletion() and (l as Label).text.strip_edges() != "")


## Where a label's TEXT is drawn, off its font, honouring its horizontal alignment inside its own box.
func _text_rect(lb: Label) -> Rect2:
	var px: int = lb.get_theme_font_size("font_size")
	var f: Font = lb.get_theme_font("font")
	var w: float = f.get_string_size(lb.text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	var x: float = lb.global_position.x
	if lb.horizontal_alignment == HORIZONTAL_ALIGNMENT_RIGHT:
		x += lb.size.x - w
	elif lb.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER:
		x += (lb.size.x - w) / 2.0
	return Rect2(Vector2(x, lb.global_position.y), Vector2(w, f.get_ascent(px)))


func test_the_floor_names_every_member_this_file_drives() -> void:
	var m := _menu(1)
	for f in ["layout_k", "px", "_build_ui", "_build_card"]:
		assert_true(m.has_method(f), "WorldMapMenu.%s must exist" % f)
	assert_true("_k" in m and "_world_cards" in m, "WorldMapMenu._k and _world_cards must exist")
	assert_eq(m._world_cards.size(), 6, "PRECONDITION: six world cards are built")


func test_the_world_map_grows_with_the_text() -> void:
	var seen: Array = []
	for s in _presets():
		GameState.set_text_size_scale(s)
		var m := _menu(1)
		for lb in _live_labels(m):
			if (lb as Label).text == "World Map":
				seen.append((lb as Label).get_theme_font_size("font_size"))
	assert_eq(seen.size(), _presets().size(), "CONTROL: the header was found at every preset")
	for i in range(1, seen.size()):
		assert_gt(seen[i], seen[i - 1], "the World Map's text must grow at every Text Size step: %s" % [seen])


## Each world in turn is the CURRENT one, so "YOU ARE HERE" sits beside every title, the longest one included.
func test_every_line_fits_its_card_and_nothing_prints_through_anything() -> void:
	var bad: Array = []
	for s in _presets():
		GameState.set_text_size_scale(s)
		for world in range(1, 7):
			var m := _menu(world)
			var vp: Vector2 = m.get_viewport_rect().size
			var boxes: Array = []   # [name, rect] of every card and every text line
			for card in m._world_cards:
				var crect := (card as Control).get_global_rect()
				assert_true(Rect2(Vector2.ZERO, vp).encloses(crect), "at %s card %s is on screen" % [s, crect])
				boxes.append(["card", crect])
				var in_card: Array = []
				for lb in _live_labels(card):
					var r := _text_rect(lb)
					if not crect.grow(0.5).encloses(r):
						bad.append("@%s W%d '%s' leaves its card" % [s, world, (lb as Label).text])
					for o in in_card:
						if r.grow(-0.5).intersects(o[1]):
							bad.append("@%s W%d '%s' over '%s'" % [s, world, (lb as Label).text, o[0]])
					in_card.append([(lb as Label).text, r])
			for lb in m.get_children():
				if lb is Label and not lb.is_queued_for_deletion():
					var r := _text_rect(lb)
					if not Rect2(Vector2.ZERO, vp).encloses(r):
						bad.append("@%s '%s' leaves the screen" % [s, (lb as Label).text])
					for b in boxes:
						if b[0] == "card" and r.grow(-0.5).intersects(b[1]):
							bad.append("@%s '%s' prints over a card" % [s, (lb as Label).text])
			for a in boxes.size():
				for b in range(a + 1, boxes.size()):
					if (boxes[a][1] as Rect2).grow(-0.5).intersects(boxes[b][1]):
						bad.append("@%s two cards overlap" % s)
	assert_eq(bad.size(), 0, "every line fits and nothing overlaps: %s" % [bad.slice(0, 8)])


func test_one_x_is_the_authored_layout() -> void:
	GameState.set_text_size_scale(1.0)
	var m := _menu(1)
	assert_eq(m._k, 1.0, "at 100% the layout factor is 1")
	assert_almost_eq((m._world_cards[0] as Control).position, Vector2(24, 64), Vector2.ONE, "the first card at its authored (24, 64)")
	assert_almost_eq((m._world_cards[0] as Control).size.y, 82.0, 0.5, "and its authored height")
