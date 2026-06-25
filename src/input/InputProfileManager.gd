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
## Button indices use the GODOT 4 JoyButton enum (matches SDL2 normalized):
##   0  = A          (Nintendo B / PS Cross / Xbox A — SOUTH face button)
##   1  = B          (Nintendo A / PS Circle / Xbox B — EAST face button)
##   2  = X          (Nintendo Y / PS Square / Xbox X — WEST face button)
##   3  = Y          (Nintendo X / PS Triangle / Xbox Y — NORTH face button)
##   4  = BACK       (Nintendo MINUS / PS Select / Xbox Back)
##   5  = GUIDE      (Nintendo HOME / PS Home / Xbox Guide)
##   6  = START      (Nintendo PLUS / PS Start / Xbox Start)
##   7  = LEFT_STICK (L3 click)
##   8  = RIGHT_STICK (R3 click)
##   9  = LEFT_SHOULDER  (Nintendo L / PS L1 / Xbox LB)
##   10 = RIGHT_SHOULDER (Nintendo R / PS R1 / Xbox RB)
##   11-14 = D-Pad U/D/L/R
##   Triggers (ZL/ZR / L2/R2 / LT/RT) are AXES 4/5, not buttons —
##   handled by motion events in project.godot, not here.
##
## Bug fix (2026-05-02): the prior PROFILE_ULTIMATE_PRO_2 used Godot 3's
## button numbers (4=LB, 5=RB, 6=Back, 7=Start) which silently misfired in
## Godot 4 — Start (button 6) was bound to battle_toggle_auto, so pressing
## Plus on Switch Pro would auto-enable autobattle every time. Both
## profiles now use Godot 4 numbers consistently.
const PROFILE_SN30 = {
	"ui_accept": [1],          # B (East face)
	"ui_cancel": [0],          # A (South face)
	"battle_advance": [10],    # RIGHT_SHOULDER (R)
	"battle_defer": [9],       # LEFT_SHOULDER (L)
	"battle_toggle_auto": [4], # BACK (Select/Minus)
	"ui_menu": [6],            # START (Plus)
}

const PROFILE_ULTIMATE_PRO_2 = {
	"ui_accept": [1],          # B (East face)
	"ui_cancel": [0],          # A (South face)
	"battle_advance": [10],    # RIGHT_SHOULDER (R)
	"battle_defer": [9],       # LEFT_SHOULDER (L)
	"battle_toggle_auto": [4], # BACK (Select/Minus)
	"ui_menu": [6],            # START (Plus)
}

## Profile names
const PROFILE_NAMES = ["8BitDo SN30", "8BitDo Ultimate Pro 2", "Custom"]

## Human-readable button labels by index — Godot 4 JoyButton enum.
## (Pre-2026-05-02 these labels were transcribed from Godot 3, which silently
## misled user-facing remap UI when the underlying button numbers shifted.)
const BUTTON_LABELS = {
	0: "A / South (Nintendo B)",
	1: "B / East (Nintendo A)",
	2: "X / West (Nintendo Y)",
	3: "Y / North (Nintendo X)",
	4: "Back / Select / Minus",
	5: "Guide / Home",
	6: "Start / Plus",
	7: "L3 (Left Stick Click)",
	8: "R3 (Right Stick Click)",
	9: "L / LB (Left Shoulder)",
	10: "R / RB (Right Shoulder)",
	11: "D-Up",
	12: "D-Down",
	13: "D-Left",
	14: "D-Right",
	15: "Misc1",
	16: "Paddle 1",
	17: "Paddle 2",
	18: "Paddle 3",
	19: "Paddle 4",
}

## Runtime state
var active_profile: String = "8BitDo Ultimate Pro 2"
var custom_bindings: Dictionary = {}


func _ready() -> void:
	# Initialize custom bindings from Ultimate Pro 2 defaults
	custom_bindings = PROFILE_ULTIMATE_PRO_2.duplicate(true)
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

	print("[InputProfileManager] Applying profile: %s" % profile_name)
	for action in REMAPPABLE_ACTIONS:
		if not bindings.has(action):
			continue
		var indices = bindings[action]
		print("[InputProfileManager]   %s -> buttons %s" % [action, str(indices)])
		_replace_joypad_buttons(action, indices)

	print("[InputProfileManager] Profile applied: %s" % profile_name)


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


## Read-only: derive a human-readable keyboard label for an action by
## scanning its current InputMap events. Used by ControlsMenu to surface
## kb bindings alongside gamepad bindings (per user request 2026-05-03:
## "make sure ... bindings for them is visible in the settings").
##
## Returns "—" if the action has no key event. Joins multiple keys with
## " / " (matches the gamepad label format).
func get_action_key_label(action: String) -> String:
	if not InputMap.has_action(action):
		return "—"
	var events := InputMap.action_get_events(action)
	var labels: Array[String] = []
	for ev in events:
		if ev is InputEventKey:
			var ke := ev as InputEventKey
			# Prefer keycode (logical) over physical_keycode for display so
			# users see the printed key name, e.g. "L" instead of "OS-keycode-76".
			var kc: Key = ke.keycode if ke.keycode != 0 else ke.physical_keycode
			if kc == 0:
				continue
			var name := OS.get_keycode_string(kc)
			if name == "":
				continue
			labels.append(name)
	return " / ".join(labels) if labels.size() > 0 else "—"


## Read-only: same idea for mouse bindings. Returns "—" if no mouse event
## is bound. Most actions in this game don't have explicit mouse bindings
## (mouse is handled at UI level via MenuMouseHelper), but ui_accept and
## ui_cancel often map to L/R-click logically; this surfaces anything
## actually wired up at the InputMap layer.
func get_action_mouse_label(action: String) -> String:
	if not InputMap.has_action(action):
		return "—"
	var events := InputMap.action_get_events(action)
	var labels: Array[String] = []
	for ev in events:
		if ev is InputEventMouseButton:
			var mb := ev as InputEventMouseButton
			match mb.button_index:
				MOUSE_BUTTON_LEFT:    labels.append("LMB")
				MOUSE_BUTTON_RIGHT:   labels.append("RMB")
				MOUSE_BUTTON_MIDDLE:  labels.append("MMB")
				MOUSE_BUTTON_WHEEL_UP:    labels.append("Wheel↑")
				MOUSE_BUTTON_WHEEL_DOWN:  labels.append("Wheel↓")
				MOUSE_BUTTON_XBUTTON1: labels.append("X1")
				MOUSE_BUTTON_XBUTTON2: labels.append("X2")
				_: labels.append("Mouse %d" % mb.button_index)
	return " / ".join(labels) if labels.size() > 0 else "—"


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
		source = PROFILE_ULTIMATE_PRO_2
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
	## Tick 168: surface save failures. Pre-fix a silent
	## `if file:` short-circuit meant a player who customized
	## their controls would think their bindings were saved (no
	## error toast, no warning) when the write actually failed
	## (perms, disk full, RO filesystem). Next launch reverts to
	## defaults — surprise loss of config.
	var file = FileAccess.open(CONFIG_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("[InputProfileManager] Could not open %s for write — custom input bindings will NOT persist across launches (error: %s)" % [CONFIG_PATH, FileAccess.get_open_error()])
		return
	file.store_string(json_str)
	file.close()
	print("[InputProfileManager] Config saved")


func load_config() -> void:
	## Tick 167: file-missing stays silent (legitimate first-launch
	## state — no config yet to load). FileAccess.open-fail and
	## root-type-mismatch were silent pre-fix; both deserve warnings
	## because they indicate a real problem (perms / corruption)
	## that the player would experience as "my custom input
	## profile didn't load" with no console hint.
	if not FileAccess.file_exists(CONFIG_PATH):
		return

	var file = FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if not file:
		push_warning("[InputProfileManager] Config exists at %s but FileAccess.open failed — using default profile" % CONFIG_PATH)
		return

	var json_str = file.get_as_text()
	file.close()

	var json = JSON.new()
	var err = json.parse(json_str)
	if err != OK:
		push_warning("[InputProfileManager] Failed to parse config: %s" % json.get_error_message())
		return

	var data = json.data
	if not (data is Dictionary):
		push_warning("[InputProfileManager] Config parsed but root is not a Dictionary — using default profile")
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
