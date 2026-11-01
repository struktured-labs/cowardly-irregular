extends CanvasLayer
class_name ChainCard

## struktured 2026-11-01 on chains: "it just jumps into the 2nd one, no warning". The beat between links: who is coming,
## which link this is, and what the breather gave back. Wall-clock, so battle speed cannot stretch it; Confirm skips it.

signal finished

const HOLD_SEC := 1.75
const SKIP_DEBOUNCE_SEC := 0.25

var hold_sec: float = HOLD_SEC
var title_text: String = ""
var detail_text: String = ""
var _t0: int = 0
var _done: bool = false


static func title_for(link: int, total: int) -> String:
	return "Another group closes in!  (Chain %d/%d)" % [link, total]


static func detail_for(restored: Dictionary) -> String:
	var hp: int = 0
	var mp: int = 0
	for k in restored:
		hp += int((restored[k] as Dictionary).get("hp", 0))
		mp += int((restored[k] as Dictionary).get("mp", 0))
	return "The party catches its breath:  +%d HP  +%d MP" % [hp, mp]


func _ready() -> void:
	layer = 97
	process_mode = Node.PROCESS_MODE_ALWAYS
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.0, 0.0, 0.05, 0.55)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var box := VBoxContainer.new()
	box.name = "Box"
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(box)
	box.add_child(_label("Title", title_text, 30, Color(1.0, 0.78, 0.3)))
	box.add_child(_label("Detail", detail_text, 20, Color(0.75, 1.0, 0.8)))
	box.position -= box.get_combined_minimum_size() / 2.0
	_t0 = Time.get_ticks_msec()


func _label(n: String, text: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.name = n
	l.text = text
	l.visible = text != ""
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", TextScale.scaled(size))
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0.05, 0.04, 0.02))
	l.add_theme_constant_override("outline_size", 6)
	return l


func _process(_delta: float) -> void:
	if not _done and Time.get_ticks_msec() - _t0 >= int(hold_sec * 1000.0):
		_finish()


func _input(event: InputEvent) -> void:
	if _done or Time.get_ticks_msec() - _t0 < int(SKIP_DEBOUNCE_SEC * 1000.0):
		return
	if event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		_finish()


func _finish() -> void:
	_done = true
	finished.emit()
