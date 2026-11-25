extends GutTest

## "MAP THIS PAD" put its four lines at fixed screen fractions (0.32/0.42/0.52/0.62) in a 480 px column with no wrap,
## while every font scaled with Text Size: the status line ran past the column and, at 200%, into the line below.
## They now wrap to one centred column that widens with Text Size and stack under each other, never off screen.

const CM := "res://src/ui/ControlsMenu.gd"
const PX := {"MappingTitle": 18, "prompt": 15, "status": 10, "idle": 11}

var _saved = null
var _saved_ts: float = 1.0


func before_each() -> void:
	_saved = GameState.text_size_scale
	_saved_ts = Engine.time_scale
	Engine.time_scale = 1.0


func after_each() -> void:
	GameState.text_size_scale = _saved
	Engine.time_scale = _saved_ts


func _presets() -> Array:
	var p: Array = (load("res://src/ui/SettingsMenu.gd") as GDScript).get_script_constant_map().get("TEXT_SIZE_PRESETS", [])
	assert_gt(p.size(), 1, "FLOOR: SettingsMenu.TEXT_SIZE_PRESETS must resolve, or every preset loop passes empty: " + str(p))
	return p


## A live walk on a 1280x720 menu, its idle warning showing (the fourth line), as a player who stalls sees it.
func _walk_at(scale: float) -> Control:
	GameState.text_size_scale = scale
	var vp := SubViewport.new()
	vp.size = Vector2i(1280, 720)
	add_child_autofree(vp)
	var m: Control = load(CM).new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	vp.add_child(m)
	await get_tree().process_frame
	m._build_mapping_overlay()
	m._mapping_overlay.visible = true
	m._mapping = ControllerMappingCapture.new("0300000000000000000000000000000000", "A Pad With A Rather Long Product Name", "Linux")
	m._mapping_idle = float(m.MAPPING_IDLE_LIMIT) - float(m.MAPPING_IDLE_WARN_AT) + 1.0
	m._refresh_mapping_prompt()
	await get_tree().process_frame
	return m


func _lines(m: Control) -> Array:
	return [m._mapping_overlay.get_node_or_null("MappingTitle"), m._mapping_prompt, m._mapping_status, m._mapping_idle_label]


## Each line starts below the one before, keeps its Text Size, and stays on screen in both directions.
func _judge(scale: float, m: Control) -> Array:
	var bad: Array = []
	var names: Array = ["MappingTitle", "prompt", "status", "idle"]
	var prev_bottom: float = -INF
	var ls: Array = _lines(m)
	for i in ls.size():
		var l: Label = ls[i]
		if l == null:
			bad.append("%.2fx line %s is missing" % [scale, names[i]])
			continue
		if l.get_theme_font_size("font_size") != TextScale.scaled(int(PX[names[i]])):
			bad.append("%.2fx %s drawn at %d px, the setting asks %d" % [scale, names[i], l.get_theme_font_size("font_size"), TextScale.scaled(int(PX[names[i]]))])
		if l.text == "":
			continue
		var h: float = l.get_minimum_size().y
		var w: float = maxf(l.size.x, l.get_minimum_size().x)
		if l.position.y < prev_bottom - 0.5:
			bad.append("%.2fx %s starts at %.0f, inside the line above (ends %.0f)" % [scale, names[i], l.position.y, prev_bottom])
		if l.position.x < -0.5 or l.position.x + w > m.size.x + 0.5:
			bad.append("%.2fx %s spans %.0f..%.0f on a %.0f screen" % [scale, names[i], l.position.x, l.position.x + w, m.size.x])
		if l.position.y + h > m.size.y + 0.5:
			bad.append("%.2fx %s ends at %.0f below a %.0f screen" % [scale, names[i], l.position.y + h, m.size.y])
		var one_line: float = l.get_theme_font("font").get_string_size(l.text.split("\n")[0], HORIZONTAL_ALIGNMENT_LEFT, -1, l.get_theme_font_size("font_size")).x
		if one_line > l.size.x + 0.5 and l.autowrap_mode == TextServer.AUTOWRAP_OFF:
			bad.append("%.2fx %s is %.0f wide on one line in a %.0f column and does not wrap" % [scale, names[i], one_line, l.size.x])
		prev_bottom = l.position.y + h
	return bad


## CONTROL: the status line's first row is wider than the old 480 px column at 200%, so the arms can see an overflow.
func test_control_the_status_outgrows_the_old_column() -> void:
	var m: Control = await _walk_at(2.0)
	var s: Label = m._mapping_status
	var w: float = s.get_theme_font("font").get_string_size(s.text.split("\n")[1], HORIZONTAL_ALIGNMENT_LEFT, -1, s.get_theme_font_size("font_size")).x
	gut.p("STATUS row 2 at 2.0: %.0f px" % w)
	assert_gt(w, 480.0, "CONTROL: at 200% the skip/cancel row is wider than the authored 480 px column")
	assert_ne(str(m._mapping_idle_label.text), "", "PRECONDITION: the idle warning is showing, so all four lines are judged")


func test_the_walk_stacks_its_lines_at_every_size() -> void:
	var bad: Array = []
	for scale in _presets():
		var m: Control = await _walk_at(float(scale))
		bad.append_array(_judge(float(scale), m))
	assert_eq(bad, [], "the pad walk's lines stack and stay on screen: %s" % [bad])


## The refusal message replaces the status mid-walk; driven through the real handler with a button already bound.
func test_a_refusal_restacks_the_walk() -> void:
	var bad: Array = []
	for scale in _presets():
		var m: Control = await _walk_at(float(scale))
		var press := func(b: int) -> void:
			var ev := InputEventJoypadButton.new()
			ev.button_index = b
			ev.pressed = true
			m._handle_mapping_input(ev)
			var up := InputEventJoypadButton.new()
			up.button_index = b
			up.pressed = false
			m._handle_mapping_input(up)
		press.call(JOY_BUTTON_A)
		press.call(JOY_BUTTON_A)
		await get_tree().process_frame
		assert_string_contains(str(m._mapping_status.text), "already", "PRECONDITION: the second press of one button was refused")
		bad.append_array(_judge(float(scale), m))
	assert_eq(bad, [], "after a refusal the walk's lines still stack: %s" % [bad])


## 100%: each line keeps its authored height on screen (the column only wraps what was already wider than it).
func test_the_default_size_keeps_the_authored_heights() -> void:
	var m: Control = await _walk_at(1.0)
	var ys: Array = []
	for l in _lines(m):
		ys.append(snappedf((l as Label).position.y, 0.1))
	assert_eq(ys, [snappedf(720 * 0.32, 0.1), snappedf(720 * 0.42, 0.1), snappedf(720 * 0.52, 0.1), snappedf(720 * 0.62, 0.1)], "the four lines sit at their authored fractions at 100%")
