extends RefCounted
class_name AbilityZoom

## One gesture for reading an ability up close, shared by the field Abilities menu and the battle ability submenu so
## it is one habit for the player (struktured 2026-11-07, design 23190). West face + keyboard A, an InputMap action
## so the hint derives; the description grows FACTOR on top of Text Size.

const ACTION := &"ability_zoom"
const FACTOR := 1.5


static func hint() -> String:
	return InputProfileManager.hint_for_action(String(ACTION))


static func pressed(event: InputEvent) -> bool:
	return InputMap.has_action(ACTION) and event.is_action_pressed(ACTION) and not event.is_echo()
