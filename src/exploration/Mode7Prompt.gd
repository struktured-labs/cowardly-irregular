extends RefCounted
class_name Mode7Prompt

## World-space text is sampled and warped by the Mode 7 shader exactly like ground. These lift a
## Label off that surface onto a layer the shader never reads, and put it back for flat maps.

## Clears Mode7Overlay's own layers — 1 is the warped ground, 2 the upright player sprite.
const LAYER: int = 3
## Screen-space text is not scaled by perspective any more, so it is sized for reading.
const FONT_SIZE: int = 18
const OUTLINE: int = 5
## Distances above the player's drawn position (0.75 of viewport height). Separate rows so
## surfaces that can be triggered on one cell stack instead of printing over each other.
const ROW_ACTION: float = 132.0
const ROW_INFO: float = 168.0
## A panel Control carries its own upward offset, so its row is measured from the panel, not the text.
const ROW_POPUP: float = 96.0
## Prompts draw over the player, never under: you arrive standing on the thing that prompts you.
const WORLD_Z: int = 100
## Screen-space prompts wrap inside this margin on each side.
const SCREEN_MARGIN: float = 48.0


## Moves any Control onto its own CanvasLayer above the overlay — the chest's loot popup is a
## panel with text inside it, not a bare Label. Returns the layer for the caller to hold.
static func lift_control(owner: Node, ctrl: Control) -> CanvasLayer:
	var layer := CanvasLayer.new()
	layer.name = "PromptLayer"
	layer.layer = LAYER
	owner.add_child(layer)
	ctrl.reparent(layer)
	return layer


## A Label also gets read-at-a-distance sizing, since perspective no longer shrinks it.
static func lift(owner: Node, label: Label) -> CanvasLayer:
	var layer := lift_control(owner, label)
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
	label.add_theme_constant_override("outline_size", OUTLINE)
	return layer


## For a Control whose children hang symmetrically off its origin: put the origin over the player.
static func place_control(ctrl: Control, viewport: Vector2, row: float) -> void:
	ctrl.position = Vector2(viewport.x * 0.5, viewport.y * 0.75 - row)


## Spans the viewport so HORIZONTAL_ALIGNMENT_CENTER puts the text over the player's head.
static func place(label: Label, viewport: Vector2, row: float) -> void:
	# A long lore line ran past both screen edges as one 18px line; wrap inside a margin instead.
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size.x = viewport.x - SCREEN_MARGIN * 2.0
	label.position = Vector2(SCREEN_MARGIN, viewport.y * 0.75 - row)


## Returns the label to world space; a scene can leave Mode 7 while a prompt is up.
static func drop(owner: Node, layer: CanvasLayer, label: Label, offset: Vector2, font_size: int) -> void:
	drop_control(owner, layer, label, offset)
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.size.x = 0.0
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_constant_override("outline_size", 0)


static func drop_control(owner: Node, layer: CanvasLayer, ctrl: Control, offset: Vector2) -> void:
	ctrl.reparent(owner)
	ctrl.position = offset
	if is_instance_valid(layer):
		layer.queue_free()


## Absolute, not relative: the trigger's own layer is 0 today and need not stay 0 if a map moves its doors.
static func pin_above_sprites(label: Label) -> void:
	label.z_index = WORLD_Z
	label.z_as_relative = false


## The world interactables' "<key> <action>" prompts: 10px tinted text with no edge, drawn under the player standing
## at them. Keep each tint, but give every one the exit labels' legibility: 12px, outlined, over the sprites.
const INTERACT_FONT: int = 12


static func style_interact_prompt(label: Label) -> void:
	label.add_theme_font_size_override("font_size", INTERACT_FONT)
	label.add_theme_constant_override("outline_size", 3)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	pin_above_sprites(label)


## Every ROW_INFO owner (NPC names, wanderer remarks, signs) lifts its label to ONE screen row, so two in range drew
## on top of each other ("Guard Paulsen" over a second name in W4). Owners join this group and implement
## `_info_row_label()`; only the one nearest the player draws, the rest are muted (self_modulate) until it leaves.
const INFO_GROUP := &"mode7_info_row"


static func owns_info_row(owner: Node2D) -> bool:
	if not owner.is_inside_tree():
		return true
	var player := owner.get_tree().get_first_node_in_group("player") as Node2D
	if player == null:
		return true
	var mine: float = owner.global_position.distance_to(player.global_position)
	for other in owner.get_tree().get_nodes_in_group(INFO_GROUP):
		if other == owner or not is_instance_valid(other) or not other.has_method("_info_row_label"):
			continue
		var l = other._info_row_label()
		if not (l is CanvasItem) or not (l as CanvasItem).is_visible_in_tree():
			continue
		var theirs: float = (other as Node2D).global_position.distance_to(player.global_position)
		if theirs < mine - 0.5 or (absf(theirs - mine) <= 0.5 and other.get_instance_id() < owner.get_instance_id()):
			return false
	return true


## Draws `label` on the shared info row only while `owner` holds it; restores full alpha when not in Mode 7.
static func share_info_row(owner: Node2D, label: CanvasItem, in_mode7: bool) -> void:
	label.self_modulate.a = 1.0 if (not in_mode7 or owns_info_row(owner)) else 0.0
