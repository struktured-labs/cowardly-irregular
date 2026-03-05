extends Node

## InputProfileManager - Manages controller button profiles and runtime remapping.
## Handles 8BitDo SN30, 8BitDo Ultimate Pro 2, and Custom profiles.
## Persists custom bindings to user://input/controls.json.

const CONFIG_PATH = "user://input/controls.json"
const CONFIG_VERSION = 1

## Remappable actions (gamepad only - keyboard stays fixed)
const REMAPPABLE_ACTIONS = [
	"ui_accept",
	"ui_cancel",
	"battle_advance",
	"battle_defer",
	"battle_toggle_auto",
	"ui_menu",
]

## Human-readable labels for actions
const ACTION_LABELS = {
	"ui_accept": "Confirm",
	"ui_cancel": "Cancel",
	"battle_advance": "Advance",
	"battle_defer": "Defer",
	"battle_toggle_auto": "Toggle Auto",
	"ui_menu": "Menu",
}

## Built-in profile definitions: action -> button index(es)
## Button indices follow SDL GameController standard:
##   0=A(South), 1=B(East), 2=X(West), 3=Y(North)
##   4=Back/Select, 6=Guide, 7=Start
##   9=LeftShoulder(LB/L), 10=RightShoulder(RB/R)
##   11=DPadUp, 12=DPadDown, 13=DPadLeft, 14=DPadRight
const PROFILE_SN30 = {
	"ui_accept": [1],        # B (East) = SNES A
	"ui_cancel": [0],        # A (South) = SNES B
	"battle_advance": [10],  # RB/R
	"battle_defer": [9],     # LB/L
	"battle_toggle_auto": [4], # Select/Back
	"ui_menu": [6, 7],       # Start (both for compatibility)
}

const PROFILE_ULTIMATE_PRO_2 = {
	"ui_accept": [1],
	"ui_cancel": [0],
	"battle_advance": [10],
	"battle_defer": [9],
	"battle_toggle_auto": [4],
	"ui_menu": [6, 7],
}

## Profile names
const PROFILE_NAMES = ["8BitDo SN30", "8BitDo Ultimate Pro 2", "Custom"]

## Human-readable button labels by index
const BUTTON_LABELS = {
	0: "A (South)",
	1: "B (East)",
	2: "X (West)",
	3: "Y (North)",
	4: "Select",
	5: "Guide",
	6: "Start",
	7: "Start",
	9: "LB (L)",
	10: "RB (R)",
	11: "D-Up",
	12: "D-Down",
	13: "D-Left",
	14: "D-Right",
	15: "Paddle 1",
	16: "Paddle 2",
	17: "Paddle 3",
	18: "Paddle 4",
}

## Runtime state
var active_profile: String = "8BitDo SN30"
var custom_bindings: Dictionary = {}


func _ready() -> void:
	# Initialize custom bindings from SN30 defaults
	custom_bindings = PROFILE_SN30.duplicate(true)
	load_config()
	apply_profile(active_profile)


func get_profile_bindings(profile_name: String) -> Dictionary:
	match profile_name:
		"8BitDo SN30":
			return PROFILE_SN30
		"8BitDo Ultimate Pro 2":
			return PROFILE_ULTIMATE_PRO_2
		"Custom":
			return custom_bindings
		_:
			return PROFILE_SN30


func apply_profile(profile_name: String) -> void:
	active_profile = profile_name
	var bindings = get_profile_bindings(profile_name)

	for action in REMAPPABLE_ACTIONS:
		if not bindings.has(action):
			continue
		_replace_joypad_buttons(action, bindings[action])

	print("[InputProfileManager] Applied profile: %s" % profile_name)


func _replace_joypad_buttons(action: String, button_indices: Array) -> void:
	# Remove existing joypad button events (keep keyboard + joypad motion)
	var existing_events = InputMap.action_get_events(action)
	for event in existing_events:
		if event is InputEventJoypadButton:
			InputMap.action_erase_event(action, event)

	# Add new joypad button events
	for btn_index in button_indices:
		var new_event = InputEventJoypadButton.new()
		new_event.button_index = btn_index
		new_event.pressed = true
		new_event.device = -1  # All devices (GamepadFilter handles device filtering)
		InputMap.action_add_event(action, new_event)


func set_custom_binding(action: String, button_indices: Array) -> void:
	if action not in REMAPPABLE_ACTIONS:
		return
	custom_bindings[action] = button_indices
	if active_profile == "Custom":
		_replace_joypad_buttons(action, button_indices)
	save_config()


func get_current_button_indices(action: String) -> Array:
	var bindings = get_profile_bindings(active_profile)
	if bindings.has(action):
		return bindings[action]
	return []


func get_button_label(button_index: int) -> String:
	if BUTTON_LABELS.has(button_index):
		return BUTTON_LABELS[button_index]
	return "Button %d" % button_index


func get_action_button_label(action: String) -> String:
	var indices = get_current_button_indices(action)
	if indices.is_empty():
		return "None"
	var labels = []
	for idx in indices:
		labels.append(get_button_label(idx))
	return " / ".join(labels)


func detect_conflicts() -> Array:
	var bindings = get_profile_bindings(active_profile)
	var conflicts = []
	var button_to_actions: Dictionary = {}

	for action in REMAPPABLE_ACTIONS:
		if not bindings.has(action):
			continue
		for btn_index in bindings[action]:
			if not button_to_actions.has(btn_index):
				button_to_actions[btn_index] = []
			button_to_actions[btn_index].append(action)

	for btn_index in button_to_actions:
		var actions = button_to_actions[btn_index]
		if actions.size() > 1:
			conflicts.append({
				"button": btn_index,
				"actions": actions,
				"label": get_button_label(btn_index),
			})

	return conflicts


func reset_custom_to_preset() -> void:
	var source = get_profile_bindings(active_profile)
	if active_profile == "Custom":
		source = PROFILE_SN30
	custom_bindings = source.duplicate(true)
	if active_profile == "Custom":
		apply_profile("Custom")
	save_config()


func cycle_profile(delta: int) -> String:
	var idx = PROFILE_NAMES.find(active_profile)
	if idx < 0:
		idx = 0
	idx = wrapi(idx + delta, 0, PROFILE_NAMES.size())
	apply_profile(PROFILE_NAMES[idx])
	save_config()
	return active_profile


func save_config() -> void:
	# Ensure directory exists
	var dir = DirAccess.open("user://")
	if dir and not dir.dir_exists("input"):
		dir.make_dir("input")

	var data = {
		"version": CONFIG_VERSION,
		"active_profile": active_profile,
		"custom_bindings": {},
	}

	# Serialize custom bindings (convert arrays for JSON)
	for action in custom_bindings:
		var indices = custom_bindings[action]
		if indices is Array:
			data["custom_bindings"][action] = indices
		else:
			data["custom_bindings"][action] = [indices]

	var json_str = JSON.stringify(data, "\t")
	var file = FileAccess.open(CONFIG_PATH, FileAccess.WRITE)
	if file:
		file.store_string(json_str)
		file.close()
		print("[InputProfileManager] Config saved")


func load_config() -> void:
	if not FileAccess.file_exists(CONFIG_PATH):
		return

	var file = FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if not file:
		return

	var json_str = file.get_as_text()
	file.close()

	var json = JSON.new()
	var err = json.parse(json_str)
	if err != OK:
		push_warning("[InputProfileManager] Failed to parse config: %s" % json.get_error_message())
		return

	var data = json.get_data()
	if not data is Dictionary:
		return

	if data.has("active_profile") and data["active_profile"] in PROFILE_NAMES:
		active_profile = data["active_profile"]

	if data.has("custom_bindings") and data["custom_bindings"] is Dictionary:
		for action in data["custom_bindings"]:
			if action in REMAPPABLE_ACTIONS:
				var val = data["custom_bindings"][action]
				if val is Array:
					custom_bindings[action] = val
				else:
					custom_bindings[action] = [int(val)]

	print("[InputProfileManager] Config loaded (profile: %s)" % active_profile)
