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
