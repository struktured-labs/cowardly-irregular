extends GutTest

## Target rows in the battle command menu ("Slime (48 HP) ~12 dmg [KILL]") were
## measured at a hardcoded 11px and drawn at TextScale.scaled(16). The panel
## stayed on its 210px floor, clip_text ellipsized the damage and [KILL] off
## the end, and a larger text-size setting clipped the glyph vertically too.
## The box is now sized from the font the row actually draws. The half-screen
## cap is unchanged, and a short command stays on the narrow menu.


const Win98MenuScript = preload("res://src/ui/Win98Menu.gd")

var _scale_before: float = 1.0


func before_all() -> void:
	if GameState and "text_size_scale" in GameState:
		_scale_before = float(GameState.text_size_scale)


func before_each() -> void:
	if GameState and "text_size_scale" in GameState:
		GameState.text_size_scale = _scale_before


func after_each() -> void:
	if GameState and "text_size_scale" in GameState:
		GameState.text_size_scale = _scale_before


func _open(items: Array) -> Win98Menu:
	var menu = Win98MenuScript.new()
	add_child_autofree(menu)
	menu.setup("Attack", items, Vector2(40, 40), "fighter")
	# setup() builds the rows, then awaits a frame and two short timers before it goes idle.
	# Freeing the menu in the middle of that leaves it as a child of the test.
	await get_tree().create_timer(0.25, true, false, true).timeout
	return menu


func _fits(label: Label) -> void:
	var font := label.get_theme_font("font")
	var px := label.get_theme_font_size("font_size")
	assert_not_null(font, "the row must have a font to measure against")
	var needed := font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	assert_gte(label.size.x + 0.5, needed,
		"'%s' draws at %dpx and needs %.0fpx, but the box is %.0fpx — the tail gets ellipsized" % [label.text, px, needed, label.size.x])
	assert_gte(label.size.y + 0.5, font.get_height(px),
		"the row is shorter than the %dpx glyph it draws" % px)


func test_a_target_row_keeps_its_damage_and_kill_readout() -> void:
	var text := "Slime (48 HP) ~12 dmg [KILL]"
	var menu := await _open([{"id": "t", "label": text}])
	var label := menu.find_child("Label", true, false) as Label
	assert_not_null(label, "the target row must have a label")
	assert_eq(label.text, text)
	assert_eq(label.get_theme_font_size("font_size"), TextScale.scaled(16),
		"the row draws at the battle menu's label size, which is what the box has to be measured with")
	_fits(label)
	var cap := int(menu.get_viewport_rect().size.x) / 2
	assert_lt(int(menu.size.x), cap,
		"this label fits under the half-screen cap — ellipsis here would be the measurement, not the cap")


func test_a_short_command_stays_on_the_narrow_menu() -> void:
	var menu := await _open([{"id": "a", "label": "Attack"}])
	assert_eq(int(menu.size.x), 210, "short commands keep the existing 210px menu; only rows that need the room grow")


func test_a_larger_text_size_still_fits_the_line_and_the_mp_cost() -> void:
	assert_true(GameState != null and "text_size_scale" in GameState, "CONTROL: text size is a live setting")
	GameState.text_size_scale = 1.5
	var menu := await _open([{"id": "fire", "label": "Fire", "cost": 999, "cost_affordable": true}])
	var name := menu.find_child("Label", true, false) as Label
	var cost := menu.find_child("Cost", true, false) as Label
	assert_not_null(name)
	assert_not_null(cost)
	assert_eq(name.get_theme_font_size("font_size"), TextScale.scaled(16))
	assert_eq(cost.get_theme_font_size("font_size"), TextScale.scaled(10))
	_fits(name)
	_fits(cost)
	var cap := int(menu.get_viewport_rect().size.x) / 2
	assert_lte(int(menu.size.x), cap, "a bigger font widens the row up to the existing half-screen cap, and no further")
