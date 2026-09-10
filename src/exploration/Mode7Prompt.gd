extends RefCounted
class_name Mode7Prompt

## World-space text is sampled and warped by the Mode 7 shader exactly like ground. These lift a
## Label off that surface onto a layer the shader never reads, and put it back for flat maps.

## Clears Mode7Overlay's own layers — 1 is the warped ground, 2 the upright player sprite.
const LAYER: int = 3
## Screen-space text is not scaled by perspective any more, so it is sized for reading.
const FONT_SIZE: int = 18
const OUTLINE: int = 5
## Distances above the player's drawn position (0.75 of viewport height). Two rows so an
## entrance prompt and a signpost standing on the same cell stack instead of overlapping.
const ROW_ACTION: float = 132.0
const ROW_INFO: float = 168.0
## Prompts draw over the player, never under: you arrive standing on the thing that prompts you.
const WORLD_Z: int = 100


## Moves the label onto its own CanvasLayer above the overlay. Returns the layer for the caller to hold.
static func lift(owner: Node, label: Label) -> CanvasLayer:
	var layer := CanvasLayer.new()
	layer.name = "PromptLayer"
	layer.layer = LAYER
	owner.add_child(layer)
	label.reparent(layer)
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
	label.add_theme_constant_override("outline_size", OUTLINE)
	return layer


## Spans the viewport so HORIZONTAL_ALIGNMENT_CENTER puts the text over the player's head.
static func place(label: Label, viewport: Vector2, row: float) -> void:
	label.size.x = viewport.x
	label.position = Vector2(0.0, viewport.y * 0.75 - row)


## Returns the label to world space; a scene can leave Mode 7 while a prompt is up.
static func drop(owner: Node, layer: CanvasLayer, label: Label, offset: Vector2, font_size: int) -> void:
	label.reparent(owner)
	label.size.x = 0.0
	label.position = offset
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_constant_override("outline_size", 0)
	if is_instance_valid(layer):
		layer.queue_free()


## Absolute, not relative: the trigger's own layer is 0 today and need not stay 0 if a map moves its doors.
static func pin_above_sprites(label: Label) -> void:
	label.z_index = WORLD_Z
	label.z_as_relative = false
