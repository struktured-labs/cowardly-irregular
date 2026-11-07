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
