extends RefCounted
class_name AutogrindInputHelper

## Shared input classification for AutogrindMonitor/AutogrindDashboard.
## Both panels react to the same controller/keyboard shortcuts, so we route
## events to named actions here to avoid duplicating the dispatch table.
##
## Returns one of: "pause", "adjust_rules", "exit", "tier_cycle", or "".
static func classify_event(event: InputEvent) -> String:
	if event is InputEventJoypadButton and event.pressed:
		match event.button_index:
			JOY_BUTTON_BACK:
				return "pause"
			JOY_BUTTON_START:
				return "adjust_rules"
			JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER:
				if Input.is_joy_button_pressed(0, JOY_BUTTON_LEFT_SHOULDER) \
						and Input.is_joy_button_pressed(0, JOY_BUTTON_RIGHT_SHOULDER):
					return "tier_cycle"
	elif event.is_action_pressed("ui_cancel") and not event.is_echo():
		return "exit"
	elif event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_P:
				return "pause"
			KEY_R:
				return "adjust_rules"
			KEY_T:
				return "tier_cycle"
	return ""
