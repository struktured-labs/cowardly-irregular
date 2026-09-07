extends Control
class_name AutogrindTemplatePicker

## Small selector for autogrind rule-template presets. Choosing a template installs
## it as a NEW named profile (via AutogrindSystem.create_new_autogrind_profile) —
## the player's existing profiles are never overwritten.

signal closed()
signal template_installed(profile_index: int)

const BG_COLOR = Color(0.05, 0.04, 0.08, 0.94)
const PANEL_BG = Color(0.06, 0.05, 0.10)
const BORDER_LIGHT = Color(0.5, 0.4, 0.6)
const BORDER_SHADOW = Color(0.2, 0.15, 0.25)
const HEADER_COLOR = Color(1.0, 1.0, 0.4)
const LABEL_COLOR = Color(0.6, 0.6, 0.7)
const ACCENT_COLOR = Color(0.9, 0.7, 1.0)

const AutogrindRuleTemplatesScript = preload("res://src/autogrind/AutogrindRuleTemplates.gd")

var _feedback_lbl: Label = null


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _ready() -> void:
	_build_ui()


func _build_ui() -> void:
	for child in get_children():
		child.queue_free()

	var vp_size := get_viewport().get_visible_rect().size
	if vp_size.x == 0 or vp_size.y == 0:
		vp_size = Vector2(1280, 720)

	var bg = ColorRect.new()
	bg.color = BG_COLOR
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var panel_w = min(vp_size.x - 120.0, 640.0)
	var panel_h = min(vp_size.y - 120.0, 520.0)
	var panel = Control.new()
	panel.position = Vector2((vp_size.x - panel_w) / 2.0, (vp_size.y - panel_h) / 2.0)
	panel.size = Vector2(panel_w, panel_h)
	add_child(panel)

	var panel_bg = ColorRect.new()
	panel_bg.color = PANEL_BG
	panel_bg.size = panel.size
	panel.add_child(panel_bg)
	_add_border(panel, panel.size)

	var title = Label.new()
	title.text = "LOAD RULE TEMPLATE"
	title.position = Vector2(20, 12)
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", HEADER_COLOR)
	panel.add_child(title)

	var sub = Label.new()
	sub.text = "Installs as a new named profile — your existing profiles are untouched."
	sub.position = Vector2(20, 40)
	sub.size = Vector2(panel_w - 40, 20)
	sub.add_theme_font_size_override("font_size", 11)
	sub.add_theme_color_override("font_color", LABEL_COLOR)
	panel.add_child(sub)

	var sep = ColorRect.new()
	sep.color = BORDER_LIGHT
	sep.position = Vector2(16, 62)
	sep.size = Vector2(panel_w - 32, 1)
	panel.add_child(sep)

	var scroll = ScrollContainer.new()
	scroll.position = Vector2(16, 72)
	scroll.size = Vector2(panel_w - 32, panel_h - 130)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)

	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 12)
	scroll.add_child(vbox)

	var templates := AutogrindRuleTemplatesScript.catalog()
	if templates.is_empty():
		var empty = Label.new()
		empty.text = "No rule templates available. data/autogrind_rule_templates.json missing or unreadable."
		empty.add_theme_font_size_override("font_size", 12)
		empty.add_theme_color_override("font_color", LABEL_COLOR)
		vbox.add_child(empty)
	else:
		for t in templates:
			vbox.add_child(_build_template_card(t, panel_w - 60.0))

	_feedback_lbl = Label.new()
	_feedback_lbl.position = Vector2(20, panel_h - 50)
	_feedback_lbl.size = Vector2(panel_w - 40, 20)
	_feedback_lbl.add_theme_font_size_override("font_size", 12)
	_feedback_lbl.add_theme_color_override("font_color", ACCENT_COLOR)
	panel.add_child(_feedback_lbl)

	var dismiss_lbl = Label.new()
	dismiss_lbl.text = "Press B or Esc to close"
	dismiss_lbl.position = Vector2(0, panel_h - 26)
	dismiss_lbl.size = Vector2(panel_w, 20)
	dismiss_lbl.add_theme_font_size_override("font_size", 11)
	dismiss_lbl.add_theme_color_override("font_color", LABEL_COLOR)
	dismiss_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(dismiss_lbl)


func _build_template_card(t: Dictionary, card_w: float) -> Control:
	var card = VBoxContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var name_lbl = Label.new()
	name_lbl.text = str(t.get("name", t.get("id", "?")))
	name_lbl.add_theme_font_size_override("font_size", 14)
	name_lbl.add_theme_color_override("font_color", ACCENT_COLOR)
	card.add_child(name_lbl)

	var desc_lbl = Label.new()
	desc_lbl.text = str(t.get("description", ""))
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	desc_lbl.custom_minimum_size = Vector2(card_w, 0)
	desc_lbl.add_theme_font_size_override("font_size", 11)
	desc_lbl.add_theme_color_override("font_color", LABEL_COLOR)
	card.add_child(desc_lbl)

	var rules_lbl = Label.new()
	rules_lbl.text = "Rules: %d" % (t.get("rules", []) as Array).size()
	rules_lbl.add_theme_font_size_override("font_size", 10)
	rules_lbl.add_theme_color_override("font_color", LABEL_COLOR)
	card.add_child(rules_lbl)

	var install_btn = Button.new()
	install_btn.text = "Install as new profile"
	install_btn.pressed.connect(_on_install_pressed.bind(str(t.get("id", ""))))
	card.add_child(install_btn)

	return card


func _on_install_pressed(template_id: String) -> void:
	var idx: int = AutogrindRuleTemplatesScript.install_as_new_profile(template_id, AutogrindSystem)
	if idx < 0:
		_feedback_lbl.text = "Could not install — profile slots full (max reached) or template not found."
		_feedback_lbl.add_theme_color_override("font_color", Color(0.9, 0.4, 0.4))
	else:
		_feedback_lbl.text = "Installed as profile #%d — active profile unchanged." % (idx + 1)
		_feedback_lbl.add_theme_color_override("font_color", ACCENT_COLOR)
		template_installed.emit(idx)


func _add_border(parent: Control, panel_size: Vector2) -> void:
	var top = ColorRect.new()
	top.color = BORDER_LIGHT
	top.size = Vector2(panel_size.x, 2)
	parent.add_child(top)
	var left_b = ColorRect.new()
	left_b.color = BORDER_LIGHT
	left_b.size = Vector2(2, panel_size.y)
	parent.add_child(left_b)
	var bottom = ColorRect.new()
	bottom.color = BORDER_SHADOW
	bottom.position = Vector2(0, panel_size.y - 2)
	bottom.size = Vector2(panel_size.x, 2)
	parent.add_child(bottom)
	var right_b = ColorRect.new()
	right_b.color = BORDER_SHADOW
	right_b.position = Vector2(panel_size.x - 2, 0)
	right_b.size = Vector2(2, panel_size.y)
	parent.add_child(right_b)


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		closed.emit()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_X, KEY_ESCAPE]:
			closed.emit()
			get_viewport().set_input_as_handled()
