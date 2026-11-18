extends GutTest

## The four W1 dragon intros were one template: the same red name card and the same white flash for fire, ice,
## lightning and void. boss_intro now takes an optional name colour, and each dragon enters in its own element.

const DirectorScript = preload("res://src/cutscene/CutsceneDirector.gd")
const DRAGONS := ["pyrroth", "glacius", "voltharion", "umbraxis"]
const DEFAULT_NAME := Color(0.95, 0.3, 0.2)

var _d: Node


func before_each() -> void:
	_d = DirectorScript.new()
	add_child_autofree(_d)
	_d._skipping = false


## The name Label the card draws, waited for under a bound (the card sleeps before it builds the name).
func _name_label(boss_name: String) -> Label:
	for i in 20000:
		for n in _d.find_children("*", "Label", true, false):
			if (n as Label).text == boss_name:
				return n
		await get_tree().process_frame
	return null


func _start(step: Dictionary) -> void:
	var runner := func() -> void:
		await _d._execute_step(step)
	runner.call()


func test_a_boss_card_draws_its_name_in_the_authored_colour() -> void:
	_start({"type": "boss_intro", "name": "Plain Boss", "title": "No colour"})
	var plain: Label = await _name_label("Plain Boss")
	assert_not_null(plain, "CONTROL: the card draws the name")
	if plain == null:
		return
	assert_eq(plain.get_theme_color("font_color"), DEFAULT_NAME, "CONTROL: without a colour, the name keeps the old red")
	_start({"type": "boss_intro", "name": "Blue Boss", "title": "Coloured", "color": "#9fdcff"})
	var blue: Label = await _name_label("Blue Boss")
	assert_not_null(blue, "the coloured card draws its name too")
	if blue == null:
		return
	assert_eq(blue.get_theme_color("font_color"), Color("#9fdcff"), "the name is drawn in the step's colour")


func _steps_of(dragon: String, step_type: String) -> Array:
	var f := FileAccess.open("res://data/cutscenes/world1_%s_intro.json" % dragon, FileAccess.READ)
	assert_not_null(f, "world1_%s_intro.json exists" % dragon)
	if f == null:
		return []
	var d: Dictionary = JSON.parse_string(f.get_as_text())
	return (d.get("steps", []) as Array).filter(func(s): return str(s.get("type", "")) == step_type)


func test_each_dragon_enters_in_a_colour_no_other_dragon_uses() -> void:
	var names := {}
	var flashes := {}
	for dr in DRAGONS:
		var cards := _steps_of(dr, "boss_intro")
		var lit := _steps_of(dr, "screen_flash")
		assert_eq(cards.size(), 1, "%s has one boss card" % dr)
		assert_gt(lit.size(), 0, "%s has an entrance flash" % dr)
		if cards.is_empty() or lit.is_empty():
			continue
		assert_true(cards[0].has("color"), "%s's card names its colour" % dr)
		assert_true(lit[0].has("color"), "%s's flash names its colour" % dr)
		var nc := Color(str(cards[0].get("color", "")))
		var fc := Color(str(lit[0].get("color", "")))
		assert_ne(nc, DEFAULT_NAME, "%s does not fall back to the shared red" % dr)
		assert_ne(fc, Color.WHITE, "%s's flash is not the shared white" % dr)
		names[nc.to_html()] = dr
		flashes[fc.to_html()] = dr
	assert_eq(names.size(), DRAGONS.size(), "four dragons, four name colours: %s" % str(names))
	assert_eq(flashes.size(), DRAGONS.size(), "four dragons, four flash colours: %s" % str(flashes))
