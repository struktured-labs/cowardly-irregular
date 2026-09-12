extends Area2D
class_name ReadableProp

## A re-readable in-world document: paged, gamepad-driven, and re-sourced on every open.
##
## The provider is a Callable returning an Array of entries, invoked FRESH each
## time the prop is opened. That is what makes "does this book change as the
## player's corruption rises?" a data question rather than a structural one —
## a fixed provider returns a constant array, a reactive one reads state. The
## mechanism cannot tell the difference and does not need to.
##
## Entry forms accepted (mix freely):
##   "some text"                      -> a page with no heading
##   {"heading": "...", "body": "..."} -> a headed page
##
## Panel is a CanvasLayer child, NOT a Control parented to this Node2D. That
## distinction is load-bearing: the 2026-07-25 "spawns a menu out of sight to
## the right of the inn" bug was a Control under a Node2D reading screen-center
## pixels as WORLD coords, so the camera left it behind (InnInterior:1487).

const PANEL_W: float = 420.0
const PANEL_H: float = 240.0
const LOCK_NAME: String = "readable_prop"
## Signpost's recipe verbatim — one label treatment for the two classes that are the same object.
const FLAT_OFFSET := Vector2(-40, -32)
const FLAT_FONT: int = 10


## ⛔ `if InputProfileManager:` guards the AUTOLOAD, not a pad — so the "B" fallback never fired in a
## real game and `glyph_for_action` handed a KEYBOARD player an xbox glyph. Measured with no pad:
## close_glyph() -> Ⓐ, while ui_cancel binds X/Escape. `hint_for_action` is the pair's safe half —
## pad glyph when a pad is connected, the KEY when not.
static func close_glyph(device_name: String = "") -> String:
	if InputProfileManager:
		return InputProfileManager.hint_for_action("ui_cancel", device_name)
	return "X"  # autoload absent (isolated tests only); ui_cancel's first keyboard binding

@export var display_name: String = "Notebook"

var _provider: Callable = Callable()
var _entries: Array = []
var _page: int = 0
var _layer: CanvasLayer = null
var _label: Label = null
var _player_nearby: bool = false
var _prompt_layer: CanvasLayer = null
var _body_label: Label = null
var _heading_label: Label = null
var _footer_label: Label = null


func setup(prop_name: String, provider: Callable) -> void:
	display_name = prop_name
	_provider = provider
	if _label != null:
		_label.text = display_name


func _ready() -> void:
	add_to_group("interactables")
	collision_layer = InteractGeometry.LAYER_INTERACTABLE
	collision_mask = InteractGeometry.MASK_PLAYER
	if get_node_or_null("CollisionShape2D") == null:
		add_child(_build_zone())
	_setup_label()
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


## A ReadableProp draws NOTHING of its own, so without this it is an invisible hotspot on scenery —
## survivable in a crowded village, undiscoverable beside one statue in an empty overworld quadrant.
func _setup_label() -> void:
	_label = Label.new()
	_label.text = display_name
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.position = FLAT_OFFSET
	_label.add_theme_font_size_override("font_size", FLAT_FONT)
	_label.add_theme_color_override("font_color", Color(0.95, 0.9, 0.7))
	_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.8))
	_label.add_theme_constant_override("shadow_offset_x", 1)
	_label.add_theme_constant_override("shadow_offset_y", 1)
	_label.visible = false
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	Mode7Prompt.pin_above_sprites(_label)
	add_child(_label)


## ROW_ACTION, not ROW_INFO: this is a thing you press, so it stacks with signs rather than over them.
func _process(_delta: float) -> void:
	if _label == null:
		return
	if InteractGeometry.is_mode7():
		if _prompt_layer == null:
			_prompt_layer = Mode7Prompt.lift(self, _label)
		_label.visible = _player_nearby and not is_open()
		if _label.visible:
			Mode7Prompt.place(_label, get_viewport_rect().size, Mode7Prompt.ROW_ACTION)
	elif _prompt_layer != null:
		Mode7Prompt.drop(self, _prompt_layer, _label, FLAT_OFFSET, FLAT_FONT)
		_label.visible = _player_nearby and not is_open()
		_prompt_layer = null
	else:
		_label.visible = _player_nearby and not is_open()


func _on_body_entered(body: Node2D) -> void:
	if InteractGeometry.is_player(body):
		_player_nearby = true


func _on_body_exited(body: Node2D) -> void:
	if InteractGeometry.is_player(body):
		_player_nearby = false


## Mode 7 recipe copied from Signpost, the sibling this class is: circle + the billboard Y-stretch.
func _build_zone() -> CollisionShape2D:
	var shape := CollisionShape2D.new()
	if InteractGeometry.is_mode7():
		var circle := CircleShape2D.new()
		circle.radius = InteractGeometry.READABLE_RADIUS_MODE7
		shape.shape = circle
		shape.scale = Vector2(1.0, InteractGeometry.MODE7_Y_STRETCH)
	else:
		var rect := RectangleShape2D.new()
		rect.size = InteractGeometry.READABLE_BOX_FLAT
		shape.shape = rect
	return shape


func is_open() -> bool:
	return _layer != null and is_instance_valid(_layer)


## Entry point for OverworldController's interact dispatch.
func interact(_player: Node2D) -> void:
	if is_open():
		return
	_entries = _fetch_entries()
	if _entries.is_empty():
		return
	_page = 0
	_open_panel()
	if SoundManager:
		SoundManager.play_ui("menu_select")


## Re-invoked on EVERY open so a reactive provider needs no invalidation hook.
func _fetch_entries() -> Array:
	if not _provider.is_valid():
		return []
	var raw = _provider.call()
	return raw if raw is Array else []


func _entry_at(i: int) -> Dictionary:
	if i < 0 or i >= _entries.size():
		return {"heading": "", "body": ""}
	var e = _entries[i]
	if e is Dictionary:
		return {"heading": str(e.get("heading", "")), "body": str(e.get("body", ""))}
	return {"heading": "", "body": str(e)}


func _open_panel() -> void:
	_layer = CanvasLayer.new()
	_layer.name = "ReadablePropLayer"
	_layer.layer = 60

	var holder := Control.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(holder)

	var panel := Panel.new()
	panel.size = Vector2(PANEL_W, PANEL_H)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-PANEL_W / 2.0, -PANEL_H / 2.0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.11, 0.09, 0.97)
	style.border_color = Color(0.62, 0.56, 0.42)
	style.set_border_width_all(3)
	style.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", style)
	holder.add_child(panel)

	_heading_label = Label.new()
	_heading_label.position = Vector2(14, 10)
	_heading_label.size = Vector2(PANEL_W - 28, 22)
	_heading_label.add_theme_font_size_override("font_size", 13)
	_heading_label.add_theme_color_override("font_color", Color(0.92, 0.84, 0.58))
	panel.add_child(_heading_label)

	_body_label = Label.new()
	_body_label.position = Vector2(14, 38)
	_body_label.size = Vector2(PANEL_W - 28, PANEL_H - 74)
	_body_label.add_theme_font_size_override("font_size", 12)
	_body_label.add_theme_color_override("font_color", Color(0.88, 0.86, 0.80))
	_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	panel.add_child(_body_label)

	_footer_label = Label.new()
	_footer_label.position = Vector2(14, PANEL_H - 30)
	_footer_label.size = Vector2(PANEL_W - 28, 20)
	_footer_label.add_theme_font_size_override("font_size", 10)
	_footer_label.add_theme_color_override("font_color", Color(0.62, 0.58, 0.48))
	_footer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(_footer_label)

	add_child(_layer)
	_render_page()
	if InputLockManager:
		InputLockManager.push_lock(LOCK_NAME)


func _render_page() -> void:
	var e := _entry_at(_page)
	if _heading_label:
		_heading_label.text = e["heading"] if e["heading"] != "" else display_name
	if _body_label:
		_body_label.text = e["body"]
	if _footer_label:
		var close := "[%s] Close" % close_glyph()
		var nav := "[<-/->] Page   " + close if _entries.size() > 1 else close
		_footer_label.text = "%d / %d      %s" % [_page + 1, _entries.size(), nav]


func _close_panel() -> void:
	if InputLockManager:
		InputLockManager.pop_lock(LOCK_NAME)
	if _layer and is_instance_valid(_layer):
		_layer.queue_free()
	_layer = null
	_body_label = null
	_heading_label = null
	_footer_label = null


func _unhandled_input(event: InputEvent) -> void:
	if not is_open():
		return
	if event.is_action_pressed("ui_cancel"):
		_close_panel()
		get_viewport().set_input_as_handled()
		if SoundManager:
			SoundManager.play_ui("menu_cancel")  # menu_back exists in neither manifest nor SOUNDS (orphan audit)
		return
	if _entries.size() > 1 and event.is_action_pressed("ui_right"):
		_page = mini(_page + 1, _entries.size() - 1)
		_render_page()
		get_viewport().set_input_as_handled()
		return
	if _entries.size() > 1 and event.is_action_pressed("ui_left"):
		_page = maxi(_page - 1, 0)
		_render_page()
		get_viewport().set_input_as_handled()
