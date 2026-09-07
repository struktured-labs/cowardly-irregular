class_name MenuPaging
extends RefCounted

## Shared page-jump input for long scrolling menus (struktured 2026-07-25: "should be a fast scroll
## down feature in menus. settings menu is already huge... or page up/down buttons").
##
## Deliberately NOT a new InputMap action: the controller lane is actively rewriting bindings, and
## L1/R1 already exist as battle_defer/battle_advance. Menus that page are never live during battle,
## so reusing the shoulder actions costs nothing and adds no binding to keep in sync.

## Rows a page jump moves. Roughly a screenful in the menus that use it.
const PAGE_ROWS := 10


## -1 = page up, +1 = page down, 0 = not a paging input. PageUp/PageDown, Home/End's neighbours on
## keyboard; L1/R1 on gamepad.
static func page_delta(event: InputEvent) -> int:
	if event == null or event.is_echo():
		return 0
	if event is InputEventKey and (event as InputEventKey).pressed:
		match (event as InputEventKey).keycode:
			KEY_PAGEUP:
				return -1
			KEY_PAGEDOWN:
				return 1
	if event.is_action_pressed("battle_defer"):
		return -1
	if event.is_action_pressed("battle_advance"):
		return 1
	return 0
