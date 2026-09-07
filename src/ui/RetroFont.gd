extends Node
class_name RetroFont

## RetroFont - Old school 8-bit style bitmap font generator
## Creates a procedural pixel font with classic game aesthetic

const CHAR_WIDTH = 8
const CHAR_HEIGHT = 8
const FONT_SCALE = 1


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
