extends RefCounted
class_name NewItemTag

## The small "NEW" marker on a newly picked-up item's row and on the menu entry that holds it (struktured 2026-11-01:
## "a newly picked up item should draw attention to itself somehow in the menu after"). One spelling, one colour and
## one measurement for every menu that shows it, so the three cannot drift apart.

const TEXT := "NEW"
const NODE_NAME := "NewTag"


static func make(base_font_size: int) -> Label:
	var tag := Label.new()
	tag.name = NODE_NAME
	tag.text = TEXT
	tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tag.add_theme_font_size_override("font_size", TextScale.scaled(base_font_size))
	tag.add_theme_color_override("font_color", AccessibilityPalette.new_item())
	return tag


## Pixel width of `text` at a base size, measured with the font a Label actually draws in.
static func text_width(text: String, base_font_size: int) -> float:
	var probe := Label.new()
	var font: Font = probe.get_theme_font("font")
	probe.free()
	if font == null:
		return float(text.length() * TextScale.scaled(base_font_size))
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, TextScale.scaled(base_font_size)).x


static func width(base_font_size: int) -> float:
	return text_width(TEXT, base_font_size)
