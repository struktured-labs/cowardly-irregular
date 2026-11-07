extends RefCounted
class_name AbilityZoom

## One gesture for reading an ability up close, shared by the field Abilities menu and the battle ability submenu so
## it is one habit for the player (struktured 2026-11-07, design 23190, v2 23219). West face + keyboard A, an
## InputMap action so the hint derives. The description fills its box; MIN_FACTOR is the floor that fill must clear
## over the unzoomed text at 100% (the fit still wins for text too long to reach it).

const ACTION := &"ability_zoom"
const MIN_FACTOR := 2.5


static func hint() -> String:
	return InputProfileManager.hint_for_action(String(ACTION))


static func pressed(event: InputEvent) -> bool:
	return InputMap.has_action(ACTION) and event.is_action_pressed(ACTION) and not event.is_echo()


## The largest px whose wrapped `text` fits `box`, measured off `font` (binary search; 1 if nothing fits).
static func fit_px(font: Font, text: String, box: Vector2, max_px: int = 400) -> int:
	var lo := 1
	var hi := max_px
	while lo < hi:
		var mid := (lo + hi + 1) / 2
		var sz: Vector2 = font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, box.x, mid)
		if sz.y <= box.y and sz.x <= box.x:
			lo = mid
		else:
			hi = mid - 1
	return lo
