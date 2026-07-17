class_name DayNightOverlay
extends CanvasLayer
## Full-screen multiply tint driven by GameState.day_phase (struktured 2026-07-16:
## "I want nice visuals on this too"). Outdoor exploration only — GameLoop flips
## set_outdoor() on scene builds; interiors keep PR-153's own night modulate,
## battles/UI live on higher layers (menu 50, cutscenes 95) and stay untinted.

## Phase-anchored multiply colors, lerped continuously — no popping at band edges.
const TINT_ANCHORS: Array = [
	[0.00, Color(0.75, 0.68, 0.82)],
	[0.05, Color(1.0, 0.87, 0.80)],
	[0.10, Color(1.0, 1.0, 1.0)],
	[0.50, Color(1.0, 1.0, 1.0)],
	[0.55, Color(1.0, 0.78, 0.62)],
	[0.60, Color(0.62, 0.62, 0.85)],
	[0.70, Color(0.45, 0.50, 0.78)],
	[0.90, Color(0.45, 0.50, 0.78)],
	[1.00, Color(0.75, 0.68, 0.82)],
]

var _rect: ColorRect = null
var _outdoor: bool = false


func _ready() -> void:
	layer = 40
	_rect = ColorRect.new()
	_rect.name = "DayNightTint"
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_MUL
	_rect.material = mat
	add_child(_rect)
	_rect.visible = false


func set_outdoor(outdoor: bool) -> void:
	_outdoor = outdoor


func _process(_delta: float) -> void:
	if _rect == null:
		return
	var gs = get_node_or_null("/root/GameState")
	if not _outdoor or gs == null or not ("day_phase" in gs):
		_rect.visible = false
		return
	var tint: Color = tint_for_phase(fposmod(float(gs.day_phase), 1.0))
	# Skip the draw entirely in full daylight — multiply-by-white is a wasted fill.
	_rect.visible = not tint.is_equal_approx(Color(1, 1, 1))
	_rect.color = tint


static func tint_for_phase(p: float) -> Color:
	for i in range(TINT_ANCHORS.size() - 1):
		var a: Array = TINT_ANCHORS[i]
		var b: Array = TINT_ANCHORS[i + 1]
		if p >= float(a[0]) and p <= float(b[0]):
			var span: float = float(b[0]) - float(a[0])
			var t: float = 0.0 if span <= 0.0 else (p - float(a[0])) / span
			return (a[1] as Color).lerp(b[1] as Color, t)
	return Color(1, 1, 1)
