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


## The KEY this classifier binds for each action — the single place the fallbacks are written down,
## so a footer legend cannot name a key classify_event does not accept.
const ACTION_KEYS := {"pause": "P", "adjust_rules": "R", "tier_cycle": "T"}


## The button token a legend should print for one of classify_event's actions, resolved against the
## pad in the player's hands. It lives HERE, beside the dispatch table, because both footers named
## "Select" and "Start" — the SNES vocabulary — for raw indices 4 and 6, which no Xbox, PlayStation
## or Switch pad carries, and told a keyboard player nothing at all about P/R/T.
static func hint_for(action_name: String, device_name: String = "") -> String:
	if action_name == "exit":
		# ui_cancel is a face button: hint_for_action already names it per family AND falls back to
		# the key, so "exit" needs no branch of its own here.
		var ipm := _profile_manager()
		return str(ipm.hint_for_action("ui_cancel", device_name)) if ipm else "B"
	var pad := _pad_token(action_name, device_name)
	return pad if pad != "" else str(ACTION_KEYS.get(action_name, ""))


static func _pad_token(action_name: String, device_name: String = "") -> String:
	var ipm := _profile_manager()
	if ipm == null:
		return ""
	match action_name:
		"pause":
			return str(ipm.button_name_for_index(JOY_BUTTON_BACK, device_name))
		"adjust_rules":
			return str(ipm.button_name_for_index(JOY_BUTTON_START, device_name))
		"tier_cycle":
			# Both shoulders, each named by the family: L+R · LB+RB · L1+R1.
			var l: String = str(ipm.button_name_for_index(JOY_BUTTON_LEFT_SHOULDER, device_name))
			var r: String = str(ipm.button_name_for_index(JOY_BUTTON_RIGHT_SHOULDER, device_name))
			return "%s+%s" % [l, r] if l != "" and r != "" else ""
	return ""


## Static context, so the SettingsMenu idiom needs the tree reached explicitly.
static func _profile_manager() -> Node:
	var loop := Engine.get_main_loop()
	if loop is SceneTree and loop.root:
		var n: Node = loop.root.get_node_or_null("/root/InputProfileManager")
		if n and n.has_method("button_name_for_index") and n.has_method("hint_for_action"):
			return n
	return null
