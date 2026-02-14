extends RefCounted
class_name RetroPanel

## Shared retro panel drawing utility
## Provides beveled 3D tile borders matching Win98Menu's SNES-era style

const TILE_SIZE = 4


static func create_panel(w: int, h: int, bg_color: Color, border_color: Color, shadow_color: Color) -> Control:
	"""Create a retro-style panel with beveled pixel tile borders"""
	var panel = Control.new()
	panel.custom_minimum_size = Vector2(w, h)
	panel.size = Vector2(w, h)

	# Background (inset by TILE_SIZE on each side)
	var bg = ColorRect.new()
	bg.color = bg_color
	bg.position = Vector2(TILE_SIZE, TILE_SIZE)
	bg.size = Vector2(w - TILE_SIZE * 2, h - TILE_SIZE * 2)
	panel.add_child(bg)

	add_border(panel, Vector2(w, h), border_color, shadow_color)

	return panel


static func add_border(parent: Control, panel_size: Vector2, border_color: Color, shadow_color: Color) -> void:
	"""Add beveled 3D tile border to an existing Control"""
	var w = int(panel_size.x)
	var h = int(panel_size.y)

	# Top border (bright)
	var top = ColorRect.new()
	top.color = border_color
	top.position = Vector2(TILE_SIZE, 0)
	top.size = Vector2(w - TILE_SIZE * 2, TILE_SIZE)
	parent.add_child(top)

	# Bottom border (shadow)
	var bottom = ColorRect.new()
	bottom.color = shadow_color
	bottom.position = Vector2(TILE_SIZE, h - TILE_SIZE)
	bottom.size = Vector2(w - TILE_SIZE * 2, TILE_SIZE)
	parent.add_child(bottom)

	# Left border (bright)
	var left = ColorRect.new()
	left.color = border_color
	left.position = Vector2(0, TILE_SIZE)
	left.size = Vector2(TILE_SIZE, h - TILE_SIZE * 2)
	parent.add_child(left)

	# Right border (shadow)
	var right = ColorRect.new()
	right.color = shadow_color
	right.position = Vector2(w - TILE_SIZE, TILE_SIZE)
	right.size = Vector2(TILE_SIZE, h - TILE_SIZE * 2)
	parent.add_child(right)

	# Corner tiles - bright top-left pair, dark bottom-right pair
	var tl = ColorRect.new()
	tl.color = border_color
	tl.position = Vector2(0, 0)
	tl.size = Vector2(TILE_SIZE, TILE_SIZE)
	parent.add_child(tl)

	var tr = ColorRect.new()
	tr.color = border_color
	tr.position = Vector2(w - TILE_SIZE, 0)
	tr.size = Vector2(TILE_SIZE, TILE_SIZE)
	parent.add_child(tr)

	var bl = ColorRect.new()
	bl.color = shadow_color
	bl.position = Vector2(0, h - TILE_SIZE)
	bl.size = Vector2(TILE_SIZE, TILE_SIZE)
	parent.add_child(bl)

	var br = ColorRect.new()
	br.color = shadow_color
	br.position = Vector2(w - TILE_SIZE, h - TILE_SIZE)
	br.size = Vector2(TILE_SIZE, TILE_SIZE)
	parent.add_child(br)
