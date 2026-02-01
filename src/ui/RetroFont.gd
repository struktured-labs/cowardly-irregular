extends Node
class_name RetroFont

## RetroFont - Old school 8-bit style bitmap font generator
## Creates a procedural pixel font with classic game aesthetic

const CHAR_WIDTH = 8
const CHAR_HEIGHT = 8
const FONT_SCALE = 1


## Generate a retro bitmap font
static func create_retro_font() -> Font:
	"""Create a procedurally generated 8-bit style bitmap font"""

	# Create bitmap font
	var font_file = FontFile.new()

	# For now, we'll use Godot's default font but configure it for pixel-perfect rendering
	# In a full implementation, we'd generate bitmap glyphs

	# Set font properties for retro look
	font_file.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	font_file.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	font_file.multichannel_signed_distance_field = false
	font_file.force_autohinter = true
	font_file.hinting = TextServer.HINTING_NONE
	font_file.oversampling = 1.0

	return font_file


## Apply retro font theme to the entire game
static func apply_retro_theme() -> void:
	"""Apply retro font and styling to default theme"""

	# Create theme
	var theme = Theme.new()

	# Configure font with pixel-perfect settings
	var font = create_retro_font()

	# Set default font
	theme.set_default_font(font)
	theme.set_default_font_size(8)

	# Configure UI colors (12-bit palette)
	var color_primary = Color(0.9, 0.9, 1.0)      # Off-white text
	var color_secondary = Color(0.7, 0.7, 0.8)    # Gray
	var color_bg = Color(0.1, 0.1, 0.15)          # Dark blue-black
	var color_panel = Color(0.15, 0.15, 0.25)     # Slightly lighter
	var color_accent = Color(0.3, 0.6, 0.9)       # Blue accent

	# Label colors
	theme.set_color("font_color", "Label", color_primary)
	theme.set_color("font_shadow_color", "Label", Color.BLACK)

	# Button colors
	theme.set_color("font_color", "Button", color_primary)
	theme.set_color("font_hover_color", "Button", color_accent)
	theme.set_color("font_pressed_color", "Button", Color.YELLOW)
	theme.set_color("font_disabled_color", "Button", color_secondary)

	# Panel colors
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = color_panel
	panel_style.border_color = color_accent
	panel_style.border_width_left = 2
	panel_style.border_width_right = 2
	panel_style.border_width_top = 2
	panel_style.border_width_bottom = 2
	theme.set_stylebox("panel", "Panel", panel_style)

	# Apply to project settings (this would need to be set in project.godot)
	# For runtime, we return the theme
	#ProjectSettings.set_setting("gui/theme/custom", theme)


## Create a procedural bitmap font texture (alternative method)
static func generate_bitmap_font_texture() -> ImageTexture:
	"""Generate a bitmap font atlas with 8-bit style characters"""

	# Font atlas: 16x16 grid of 8x8 characters = 128x128 texture
	var atlas_width = 16 * CHAR_WIDTH
	var atlas_height = 16 * CHAR_HEIGHT

	var img = Image.create(atlas_width, atlas_height, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	# Define pixel patterns for characters (simple 8x8 bitmap font)
	var char_data = _get_character_patterns()

	# Draw each character
	for i in range(char_data.size()):
		var char_code = i + 32  # Start from space (ASCII 32)
		var row = i / 16
		var col = i % 16

		var x_offset = col * CHAR_WIDTH
		var y_offset = row * CHAR_HEIGHT

		if i < char_data.size() and char_data[i]:
			_draw_character(img, x_offset, y_offset, char_data[i])

	return ImageTexture.create_from_image(img)


static func _draw_character(img: Image, x_offset: int, y_offset: int, pattern: PackedByteArray) -> void:
	"""Draw a single character from bit pattern"""
	for y in range(CHAR_HEIGHT):
		if y >= pattern.size():
			break
		var row = pattern[y]
		for x in range(CHAR_WIDTH):
			if row & (1 << (7 - x)):
				img.set_pixel(x_offset + x, y_offset + y, Color.WHITE)


static func _get_character_patterns() -> Array:
	"""Define 8x8 bitmap patterns for ASCII characters (32-127)"""
	# This is a simplified set - a full implementation would include all printable ASCII

	var patterns = []

	# Space (32)
	patterns.append(PackedByteArray([
		0b00000000,
		0b00000000,
		0b00000000,
		0b00000000,
		0b00000000,
		0b00000000,
		0b00000000,
		0b00000000
	]))

	# ! (33)
	patterns.append(PackedByteArray([
		0b00010000,
		0b00010000,
		0b00010000,
		0b00010000,
		0b00010000,
		0b00000000,
		0b00010000,
		0b00000000
	]))

	# A (65 - for now we'll add a few key letters)
	# We'll add more as needed...

	# For brevity, returning basic patterns
	# A full implementation would include all 95 printable ASCII characters

	return patterns


## Create styled labels with retro font
static func create_retro_label(text: String, size: int = 8) -> Label:
	"""Create a label with retro font styling"""
	var label = Label.new()
	label.text = text

	# Apply pixel-perfect settings
	label.add_theme_font_size_override("font_size", size)

	# Add shadow for classic look
	var shadow_color = Color(0, 0, 0, 0.7)
	label.add_theme_color_override("font_shadow_color", shadow_color)
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)

	return label


## Configure RichTextLabel for battle log
static func configure_battle_log(rich_text_label: RichTextLabel) -> void:
	"""Configure a RichTextLabel for retro battle log appearance"""

	# Set font
	rich_text_label.add_theme_font_size_override("normal_font_size", 12)
	rich_text_label.add_theme_font_size_override("bold_font_size", 12)

	# Colors
	rich_text_label.add_theme_color_override("default_color", Color(0.9, 0.9, 1.0))

	# Background
	var bg_style = StyleBoxFlat.new()
	bg_style.bg_color = Color(0.05, 0.05, 0.1, 0.9)
	bg_style.border_color = Color(0.3, 0.6, 0.9)
	bg_style.border_width_left = 1
	bg_style.border_width_right = 1
	bg_style.border_width_top = 1
	bg_style.border_width_bottom = 1
	rich_text_label.add_theme_stylebox_override("normal", bg_style)
