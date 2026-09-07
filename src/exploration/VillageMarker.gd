extends Node2D
class_name VillageMarker

## VillageMarker — large visible village indicator on overworld.
## Draws a cluster of procedural house sprites + floating name banner.
## Visible from a distance through Mode 7 perspective.

var village_name: String = "Village"
var roof_color: Color = Color(0.65, 0.2, 0.15)
var wall_color: Color = Color(0.75, 0.65, 0.5)

var _label: Label
var _banner_bg: ColorRect


func _ready() -> void:
	_draw_buildings()
	_draw_banner()


func _draw_buildings() -> void:
	# Draw 3 house sprites in a cluster — big enough to see through Mode 7
	var offsets = [Vector2(-20, -8), Vector2(8, -12), Vector2(-6, 8)]
	var sizes = [Vector2(24, 20), Vector2(20, 18), Vector2(18, 16)]

	for i in range(3):
		var house = Sprite2D.new()
		var img = Image.create(32, 32, false, Image.FORMAT_RGBA8)
		var w = int(sizes[i].x)
		var h = int(sizes[i].y)
		var cx = 16
		var cy = 16

		# Wall
		var wc = wall_color.darkened(i * 0.08)
		for y in range(cy, cy + h):
			for x in range(cx - w / 2, cx + w / 2):
				if x >= 0 and x < 32 and y >= 0 and y < 32:
					img.set_pixel(x, y, wc)

		# Roof (triangle)
		var rc = roof_color.darkened(i * 0.05)
		for ry in range(h / 2):
			var rw = w / 2 - ry
			for rx in range(-rw, rw + 1):
				var px = cx + rx
				var py = cy - ry
				if px >= 0 and px < 32 and py >= 0 and py < 32:
					img.set_pixel(px, py, rc)

		# Door
		var door_x = cx - 2
		var door_y = cy + h - 6
		for dy in range(5):
			for dx in range(4):
				var px = door_x + dx
				var py = door_y + dy
				if px >= 0 and px < 32 and py >= 0 and py < 32:
					img.set_pixel(px, py, Color(0.25, 0.18, 0.1))

		# Window
		var win_x = cx + 3
		var win_y = cy + 3
		for dy in range(3):
			for dx in range(3):
				var px = win_x + dx
				var py = win_y + dy
				if px >= 0 and px < 32 and py >= 0 and py < 32:
					img.set_pixel(px, py, Color(0.7, 0.85, 1.0, 0.8))

		house.texture = ImageTexture.create_from_image(img)
		house.position = offsets[i]
		house.scale = Vector2(2.5, 2.5)  # Large enough to see through Mode 7
		house.z_index = 1
		add_child(house)


func _draw_banner() -> void:
	# Floating name banner above the village
	_banner_bg = ColorRect.new()
	_banner_bg.color = Color(0.0, 0.0, 0.0, 0.5)
	_banner_bg.size = Vector2(village_name.length() * 8 + 16, 20)
	_banner_bg.position = Vector2(-_banner_bg.size.x / 2, -50)
	_banner_bg.z_index = 5
	add_child(_banner_bg)

	_label = Label.new()
	_label.text = village_name
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.position = Vector2(-_banner_bg.size.x / 2 + 2, -50)
	_label.size = Vector2(_banner_bg.size.x, 20)
	_label.add_theme_font_size_override("font_size", 13)
	_label.add_theme_color_override("font_color", Color(0.95, 0.85, 0.5))
	_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_label.add_theme_constant_override("shadow_offset_x", 1)
	_label.add_theme_constant_override("shadow_offset_y", 1)
	_label.z_index = 6
	add_child(_label)
