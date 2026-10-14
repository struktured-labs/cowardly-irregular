extends GutTest

## ⛔ THE F11 GAMEPAD DIAGNOSTIC IGNORED TEXT SIZE — a raw `normal_font_size, 18`, the last raw
## RichTextLabel font in `src/ui`. It is advertised to the player in the F1 controls reference and in
## ControlsMenu, so a player who turned the text up reached a screen that did not honour the setting.
##
## ⛔ AND SCALING IT ALONE WOULD HAVE MADE IT WORSE, which is the half that needs a guard. The label
## is PRESET_FULL_RECT with `scroll_active = false`, so anything past the viewport was simply not
## drawn: no scrollbar, no indicator, nothing. The action list — the whole point of the screen — is
## what runs off the bottom first.
##
## 🔑 TWO HARD ARMS, ONE THE OTHER'S PREMISE: that the content at 200% EXCEEDS the box, and that a
## d-pad press then MOVES the view. Written as two hard arms rather than one conditional, because
## "if there is scroll range then it moves" passes vacuously exactly when the premise is false —
## which is the shape this lane has had to repair six times.

const SRC := "res://src/ui/GamepadDiagnostic.gd"

## ⛔ THE BOX MUST BE THE REAL SCREEN, OR ARM 4 IS TRIVIALLY TRUE. The overlay is PRESET_FULL_RECT
## against whatever parent it is added to, and a GUT test node can be 0-sized — in which case
## "content exceeds the box" passes for a box that does not exist. Read from ProjectSettings rather
## than written as 1280x720, so a viewport change moves the guard with the game.
static func _view_size() -> Vector2:
	var w: float = float(ProjectSettings.get_setting("display/window/size/viewport_width", 1280))
	var h: float = float(ProjectSettings.get_setting("display/window/size/viewport_height", 720))
	return Vector2(w, h)

## ⛔ DERIVED FROM THE CONSUMER'S OWN LIST, NOT A COPY. A hardcoded [0.8, 1.0, 1.25, 1.5, 2.0] goes
## quietly stale the day a preset is added, and the arm meant to catch "it broke at 125%" then never
## visits the new step. NO FALLBACK DEFAULT: a rename must red, and a fallback would make this pass
## against a ladder the player cannot select.
##
## ⛔ THE FLOOR LIVES IN HERE, NOT ONLY IN ITS OWN ARM. An empty or renamed ladder makes every
## `for scale in _presets()` iterate ZERO times and pass green; asserting inside the helper makes
## each sweeping arm red BY ITS OWN NAME, and it cannot be separated from the loops by a later edit
## the way a standalone floor arm can (@cowir-autogrind named the gap, @cowir-story the repair).
func _presets() -> Array:
	var consts: Dictionary = (load("res://src/ui/SettingsMenu.gd") as GDScript).get_script_constant_map()
	var p: Array = consts.get("TEXT_SIZE_PRESETS", [])
	assert_gt(p.size(), 1,
		"FLOOR: SettingsMenu.TEXT_SIZE_PRESETS must resolve and hold more than one step, or this "
		+ "arm's preset loop iterates nothing and passes. Got " + str(p))
	return p


var _saved_scale = null


func before_each() -> void:
	_saved_scale = GameState.text_size_scale if "text_size_scale" in GameState else null


func after_each() -> void:
	if _saved_scale != null:
		GameState.text_size_scale = _saved_scale


func _f11() -> InputEventKey:
	var k := InputEventKey.new()
	k.keycode = KEY_F11
	k.pressed = true
	return k


func _dpad(action: String) -> InputEventAction:
	var a := InputEventAction.new()
	a.action = action
	a.pressed = true
	return a


## Build the overlay at a scale and OPEN it through the real F11 path, so `_process` populates the
## label. An unopened overlay early-returns and every measurement below would read an empty label.
func _opened_at(scale: float) -> Node:
	GameState.text_size_scale = scale
	var o: Node = load(SRC).new()
	add_child_autofree(o)
	(o as Control).size = _view_size()
	await get_tree().process_frame
	o._input(_f11())
	await get_tree().process_frame
	await get_tree().process_frame
	return o


func _label_of(o: Node) -> RichTextLabel:
	for c in o.get_children():
		if c is RichTextLabel:
			return c as RichTextLabel
	return null


## FLOOR — the constants the arms below depend on, from the script's own map. A rename would
## otherwise leave an arm reading a default instead of reding.
func test_the_constants_these_arms_depend_on_exist() -> void:
	var consts: Dictionary = (load(SRC) as GDScript).get_script_constant_map()
	for name in ["BASE_FONT_SIZE", "SCROLL_LINES"]:
		assert_true(consts.has(name),
			"FLOOR: GamepadDiagnostic must still name %s" % name)


## PRECONDITION — the overlay opens and carries the label everything else measures.
func test_the_overlay_opens_and_renders() -> void:
	var o: Node = await _opened_at(1.0)
	assert_true(o._active, "F11 must open the overlay — every arm below needs _process to have run")
	var l: RichTextLabel = _label_of(o)
	assert_not_null(l, "the overlay must carry a RichTextLabel")
	if l != null:
		assert_gt(l.text.length(), 0, "the label must have been populated by _process")


## ARM 1 — the font follows the setting at EVERY preset step, not just the endpoints. Two endpoints
## cannot see a ladder that skips a rung: the field menu broke at 125% while 80% and 200% were fine.
func test_the_font_follows_the_setting_at_every_preset() -> void:
	var seen: Array = []
	var sizes: Array = []
	for scale in _presets():
		var l: RichTextLabel = _label_of(await _opened_at(float(scale)))
		if l == null:
			seen.append("%.2fx: NO LABEL" % scale)
			continue
		var px: int = int(l.get_theme_font_size("normal_font_size"))
		sizes.append(px)
		seen.append("%.2fx=%d" % [scale, px])
	assert_gt(seen.size(), 1, "CONTROL: the loop must have visited more than one preset: %s" % [seen])
	assert_eq(sizes.size(), seen.size(),
		"every preset must have produced a font size: %s" % [seen])
	var flat: Array = []
	for i in range(1, sizes.size()):
		if int(sizes[i]) <= int(sizes[i - 1]):
			flat.append("step %d did not grow" % i)
	assert_eq(flat, [],
		"the font must grow at EVERY preset step, not only between the endpoints: %s" % [seen])


## ARM 2 — pin the state the fix did not change. At the default the font must still be exactly the
## shipped 18, or every existing screenshot of this overlay moved.
func test_the_default_text_size_renders_the_shipped_font() -> void:
	var l: RichTextLabel = _label_of(await _opened_at(1.0))
	assert_not_null(l, "PRECONDITION: the label must exist")
	if l == null:
		return
	var consts: Dictionary = (load(SRC) as GDScript).get_script_constant_map()
	var base: int = int(consts.get("BASE_FONT_SIZE", -1))
	assert_eq(int(l.get_theme_font_size("normal_font_size")), base,
		"at 100%% the font must still be the shipped %d" % base)


## ARM 3 — reachability is STRUCTURAL: scrolling must be on, or content past the viewport is drawn
## nowhere and no amount of font scaling is honest.
func test_overflow_is_reachable_at_all() -> void:
	var l: RichTextLabel = _label_of(await _opened_at(2.0))
	assert_not_null(l, "PRECONDITION: the label must exist")
	if l == null:
		return
	assert_true(l.scroll_active,
		"scroll_active must be ON: the label is PRESET_FULL_RECT, so with scrolling off every row "
		+ "past the viewport is simply not drawn and cannot be reached by any input")


## ARM 3b — THE BOX IS REAL. Without this, arm 4 ("content exceeds the box") is satisfied by a
## zero-height box, which is what a 0-sized test parent would give it. Its own arm, deliberately: a
## precondition hoisted into arm 4 would make arm 4's first reach loud and say nothing about the rest.
func test_the_box_is_the_real_viewport() -> void:
	var l: RichTextLabel = _label_of(await _opened_at(2.0))
	assert_not_null(l, "PRECONDITION: the label must exist")
	if l == null:
		return
	assert_almost_eq(l.size.y, _view_size().y, 1.0,
		"the label must fill the real viewport height (%.0f), or every overflow measurement here is "
		% _view_size().y + "about a box that does not exist. Got %.0f" % l.size.y)


## ARM 4 — THE PREMISE, asserted rather than assumed. If the content fits at 200% then arm 5 is
## measuring nothing, so this states the overflow as its own claim and prints the numbers.
func test_the_content_overflows_the_box_at_200_percent() -> void:
	var l: RichTextLabel = _label_of(await _opened_at(2.0))
	assert_not_null(l, "PRECONDITION: the label must exist")
	if l == null:
		return
	var sb := l.get_v_scroll_bar()
	assert_not_null(sb, "the label must expose a vertical scrollbar once scrolling is on")
	if sb == null:
		return
	assert_gt(sb.max_value - sb.page, 0.0,
		"at 200%% the content must exceed the box, or arm 5 proves nothing: max_value=%.0f page=%.0f "
		% [sb.max_value, sb.page]
		+ "box=%.0f. If this reds, the overflow premise is wrong and the scroll arms are vacuous."
			% l.size.y)


## ARM 5 — a d-pad press MOVES the view, through MenuNav.step and the real `_input` path.
func test_a_dpad_press_scrolls_the_open_overlay() -> void:
	var o: Node = await _opened_at(2.0)
	var l: RichTextLabel = _label_of(o)
	assert_not_null(l, "PRECONDITION: the label must exist")
	if l == null:
		return
	var sb := l.get_v_scroll_bar()
	if sb == null:
		assert_not_null(sb, "PRECONDITION: the scrollbar must exist")
		return
	var before: float = sb.value
	o._input(_dpad("ui_down"))
	await get_tree().process_frame
	assert_gt(sb.value, before,
		"ui_down must scroll the open diagnostic: %.0f -> %.0f" % [before, sb.value])


## ARM 6 — THE CONTROL for arm 5. A closed overlay must not consume or act on a direction; without
## this, arm 5 is satisfied by a handler that scrolls whatever the overlay's state.
func test_a_closed_overlay_ignores_the_same_press() -> void:
	var o: Node = await _opened_at(2.0)
	var l: RichTextLabel = _label_of(o)
	assert_not_null(l, "PRECONDITION: the label must exist")
	if l == null:
		return
	var sb := l.get_v_scroll_bar()
	if sb == null:
		assert_not_null(sb, "PRECONDITION: the scrollbar must exist")
		return
	o._input(_f11())
	await get_tree().process_frame
	assert_false(o._active, "PRECONDITION: a second F11 must close the overlay")
	var before: float = sb.value
	o._input(_dpad("ui_down"))
	await get_tree().process_frame
	assert_almost_eq(sb.value, before, 0.001,
		"a CLOSED diagnostic must not act on ui_down — it is added to every session unconditionally, "
		+ "so a handler that ran while closed would steal a direction from the game underneath")


## FLOOR for the preset derivation — without it an empty list makes every preset loop above iterate
## ZERO times and pass, which is the shrinking-corpus shape a derived guard fails into silently.
func test_the_preset_list_derives_from_settings() -> void:
	var p: Array = _presets()
	assert_gt(p.size(), 1,
		"FLOOR: SettingsMenu.TEXT_SIZE_PRESETS must still resolve and hold more than one step — a "
		+ "rename leaves every preset loop here iterating nothing and passing. Got " + str(p))
	assert_true(p.has(1.0), "the derived presets must include the 1.0 default: " + str(p))
